/*
 * SPDX-License-Identifier: Apache-2.0
 */
#define LOG_TAG "radio-axon7m"

#include "DataCall.h"

#include "Qmi.h"

#include <aidl/android/hardware/radio/RadioConst.h>
#include <android-base/logging.h>

#include <arpa/inet.h>
#include <net/if.h>

#include <linux/netlink.h>
#include <linux/rtnetlink.h>
#include <sys/socket.h>
#include <unistd.h>

#include <cerrno>
#include <cstring>
#include <iomanip>
#include <optional>
#include <sstream>
#include <string>
#include <utility>

// android's NDK headers do not declare the rmnet link attributes; the values
// are uapi (include/uapi/linux/if_link.h in the phone's 7.3.1 kernel).
#define AXON7_IFLA_RMNET_MUX_ID 1
#define AXON7_IFLA_RMNET_FLAGS 2
#define AXON7_IFLA_LINKINFO 18
#define AXON7_IFLA_INFO_KIND 1
#define AXON7_IFLA_INFO_DATA 2
#ifndef IFLA_IFNAME
#define IFLA_IFNAME 3
#endif
#ifndef IFLA_MTU
#define IFLA_MTU 4
#endif
#ifndef IFLA_LINK
#define IFLA_LINK 5
#endif
// RMNET_FLAGS_{INGRESS_DEAGGREGATION,INGRESS_MAP_CKSUMV4,EGRESS_MAP_CKSUMV4}
#define AXON7_RMNET_FLAGS (0x01u | 0x04u | 0x08u)

namespace axon7m::radio {

namespace {

using ::aidl::android::hardware::radio::RadioConst;
using ::aidl::android::hardware::radio::RadioError;
namespace aidlData = ::aidl::android::hardware::radio::data;

// QMI protocol errors from libqril/lib/libqril_qmi.h, only the ones a data
// call can plausibly return on this 2016 MPSS.
constexpr uint16_t kQmiCallFailed = 14;
constexpr uint16_t kQmiNoNetworkFound = 13;
constexpr uint16_t kQmiMissingArgument = 17;
constexpr uint16_t kQmiNetworkUnsupported = 24;
constexpr uint16_t kQmiInvalidPdpType = 28;
constexpr uint16_t kQmiInvalidArgument = 48;
constexpr uint16_t kQmiNetworkNotReady = 53;
constexpr uint16_t kQmiInvalidOperation = 70;
constexpr uint16_t kQmiNotSupported = 94;
constexpr uint16_t kQmiNoSim = 102;

const char* qmiErrorName(uint16_t error) {
    switch (error) {
        case kQmiCallFailed: return "CALL_FAILED";
        case kQmiNoNetworkFound: return "NO_NETWORK_FOUND";
        case kQmiMissingArgument: return "MISSING_ARGUMENT";
        case kQmiNetworkUnsupported: return "NETWORK_UNSUPPORTED";
        case kQmiInvalidPdpType: return "INVALID_PDP_TYPE";
        case kQmiInvalidArgument: return "INVALID_ARGUMENT";
        case kQmiNetworkNotReady: return "NETWORK_NOT_READY";
        case kQmiInvalidOperation: return "INVALID_OPERATION";
        case kQmiNotSupported: return "NOT_SUPPORTED";
        case kQmiNoSim: return "NO_SIM";
        default: return "unknown";
    }
}

std::string hex(const std::vector<uint8_t>& v, size_t limit = 16) {
    std::ostringstream o;
    o << std::hex << std::setfill('0');
    for (size_t i = 0; i < v.size() && i < limit; i++) o << std::setw(2) << (int)v[i];
    if (v.size() > limit) o << "...";
    return o.str();
}

// Log every WDS/WDA/DPM exchange (message, result, QMI error, TLV inventory).
// APN, user and password TLVs are never printed, only their presence.
void logQmi(const char* op, uint16_t msg, const std::optional<QmiResponse>& r) {
    std::ostringstream o;
    o << op << " 0x" << std::hex << std::setw(4) << std::setfill('0') << msg << ": ";
    if (!r) {
        o << "NO ANSWER";
    } else {
        o << std::dec << "result=" << r->result << " error=" << r->error << " ("
          << qmiErrorName(r->error) << ") tlvs=";
        for (const auto& [type, value] : r->tlvs) {
            o << std::hex << std::setw(2) << std::setfill('0') << (int)type << "/" << std::dec
              << value.size() << " ";
        }
        for (int t : {0x10, 0x11}) {  // WDS call-end reason / verbose reason
            if (const auto* v = r->tlv(static_cast<uint8_t>(t)))
                o << " reason" << std::hex << t << "=" << hex(*v);
        }
    }
    if (r && r->ok()) {
        LOG(INFO) << o.str();
    } else {
        LOG(ERROR) << o.str();
    }
}

std::optional<QmiResponse> qmi(uint32_t service, const char* op, uint16_t msg,
                               const std::vector<uint8_t>& tlvs, int timeoutMs = 3000) {
    auto r = qmiRequest(service, msg, tlvs, timeoutMs);
    logQmi(op, msg, r);
    return r;
}

struct Failure {
    RadioError radio;
    aidlData::DataCallFailCause cause;
};

Failure failureFor(const std::optional<QmiResponse>& r) {
    if (!r) return {RadioError::MODEM_ERR, aidlData::DataCallFailCause::ERROR_UNSPECIFIED};
    switch (r->error) {
        case kQmiNoSim:
            return {RadioError::SIM_ERR, aidlData::DataCallFailCause::DATA_REGISTRATION_FAIL};
        case kQmiNoNetworkFound:
        case kQmiNetworkNotReady:
        case kQmiNetworkUnsupported:
            return {RadioError::NETWORK_ERR, aidlData::DataCallFailCause::NETWORK_FAILURE};
        case kQmiMissingArgument:
        case kQmiInvalidPdpType:
        case kQmiInvalidArgument:
            return {RadioError::INVALID_ARGUMENTS,
                    aidlData::DataCallFailCause::INVALID_MANDATORY_INFO};
        case kQmiInvalidOperation:
            return {RadioError::MODEM_ERR, aidlData::DataCallFailCause::SERVICE_OPTION_NOT_SUPPORTED};
        case kQmiNotSupported:
            return {RadioError::REQUEST_NOT_SUPPORTED,
                    aidlData::DataCallFailCause::SERVICE_OPTION_NOT_SUPPORTED};
        case kQmiCallFailed: {
            const auto* reason = r->tlv(0x10);
            uint16_t code = 0;
            if (reason && reason->size() >= 2 && getLe(*reason, 0, &code) && code != 0 &&
                code < 0x100) {
                return {RadioError::MODEM_ERR, static_cast<aidlData::DataCallFailCause>(code)};
            }
            return {RadioError::MODEM_ERR, aidlData::DataCallFailCause::NETWORK_FAILURE};
        }
        default:
            return {RadioError::MODEM_ERR, aidlData::DataCallFailCause::ERROR_UNSPECIFIED};
    }
}

// 3GPP PDP type -> QMI WDS IP family preference (QmiWdsIpFamily).
uint8_t ipFamily(const aidlData::DataProfileInfo& profile) {
    switch (profile.protocol) {
        case aidlData::PdpProtocolType::IPV6: return 6;
        case aidlData::PdpProtocolType::IPV4V6: return 8;
        default: return 4;
    }
}

uint8_t qmiAuth(const aidlData::DataProfileInfo& profile) {
    switch (profile.authType) {
        case aidlData::ApnAuthType::PAP_NO_CHAP: return 1;
        case aidlData::ApnAuthType::NO_PAP_CHAP: return 2;
        case aidlData::ApnAuthType::PAP_CHAP: return 3;
        default: return 0;
    }
}

void putEndpoint(std::vector<uint8_t>* b, uint8_t type) {
    std::vector<uint8_t> ep;
    putTlvU32(&ep, 0, 4);  // QMI_DATA_ENDPOINT_TYPE_EMBEDDED (IPA)
    putTlvU32(&ep, 4, 1);  // interface number
    putTlvBytes(b, type, ep.data(), ep.size());
}

// ---- rtnetlink: create/destroy an rmnet virtual link on rmnet_ipa0

void addAttr(std::vector<uint8_t>* b, uint16_t type, const void* data, size_t len) {
    size_t off = b->size();
    size_t pad = (4 - (len % 4)) % 4;
    b->resize(off + 4 + len + pad, 0);
    auto* a = reinterpret_cast<nlattr*>(b->data() + off);
    a->nla_len = 4 + len;
    a->nla_type = type;
    if (len) std::memcpy(b->data() + off + 4, data, len);
}

size_t beginNest(std::vector<uint8_t>* b, uint16_t type) {
    size_t off = b->size();
    b->resize(off + 4, 0);
    auto* a = reinterpret_cast<nlattr*>(b->data() + off);
    a->nla_type = type | NLA_F_NESTED;
    a->nla_len = 4;
    return off;
}

void endNest(std::vector<uint8_t>* b, size_t off) {
    reinterpret_cast<nlattr*>(b->data() + off)->nla_len = b->size() - off;
}

uint32_t gSeq = 1;

bool netlink(uint16_t type, uint16_t flags, const std::vector<uint8_t>& body, std::string* err) {
    int fd = socket(AF_NETLINK, SOCK_RAW, NETLINK_ROUTE);
    if (fd < 0) {
        *err = "socket: " + std::string(std::strerror(errno));
        return false;
    }
    timeval tv{3, 0};
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    std::vector<uint8_t> msg;
    nlmsghdr h{};
    h.nlmsg_len = sizeof(h) + body.size();
    h.nlmsg_type = type;
    h.nlmsg_flags = flags;
    h.nlmsg_seq = gSeq++;
    const auto* hp = reinterpret_cast<const uint8_t*>(&h);
    msg.insert(msg.end(), hp, hp + sizeof(h));
    msg.insert(msg.end(), body.begin(), body.end());
    ssize_t n = send(fd, msg.data(), msg.size(), 0);
    if (n != static_cast<ssize_t>(msg.size())) {
        *err = "send: " + std::string(std::strerror(errno));
        close(fd);
        return false;
    }
    std::vector<uint8_t> buf(8192);
    bool ok = false;
    while (!ok) {
        n = recv(fd, buf.data(), buf.size(), 0);
        if (n < static_cast<ssize_t>(sizeof(nlmsghdr))) {
            *err = "no netlink ack";
            break;
        }
        const auto* rh = reinterpret_cast<const nlmsghdr*>(buf.data());
        if (rh->nlmsg_seq != h.nlmsg_seq) continue;
        if (rh->nlmsg_type == NLMSG_DONE) break;
        if (rh->nlmsg_type == NLMSG_ERROR) {
            if (n < static_cast<ssize_t>(sizeof(nlmsghdr) + sizeof(nlmsgerr))) {
                *err = "short netlink error";
                break;
            }
            const auto* e = reinterpret_cast<const nlmsgerr*>(rh + 1);
            if (e->error == 0) {
                ok = true;
            } else {
                *err = "kernel: " + std::string(std::strerror(-e->error));
            }
        }
        break;
    }
    close(fd);
    return ok;
}

bool addRmnetLink(const std::string& name, uint8_t muxId, unsigned parentIndex, uint32_t mtu,
                  std::string* err) {
    ifinfomsg ifi{};
    ifi.ifi_family = AF_UNSPEC;
    std::vector<uint8_t> body(sizeof(ifi));
    std::memcpy(body.data(), &ifi, sizeof(ifi));
    addAttr(&body, IFLA_LINK, &parentIndex, sizeof(parentIndex));
    addAttr(&body, IFLA_IFNAME, name.c_str(), name.size() + 1);
    if (mtu >= 576 && mtu <= 65535) addAttr(&body, IFLA_MTU, &mtu, sizeof(mtu));
    size_t linkInfo = beginNest(&body, AXON7_IFLA_LINKINFO);
    const char kind[] = "rmnet";
    addAttr(&body, AXON7_IFLA_INFO_KIND, kind, sizeof(kind));  // IFLA_INFO_KIND
    size_t infoData = beginNest(&body, AXON7_IFLA_INFO_DATA);
    uint16_t mux = muxId;
    addAttr(&body, AXON7_IFLA_RMNET_MUX_ID, &mux, sizeof(mux));
    struct {
        uint32_t flags;
        uint32_t mask;
    } flags{AXON7_RMNET_FLAGS, 0xffffffffu};
    addAttr(&body, AXON7_IFLA_RMNET_FLAGS, &flags, sizeof(flags));
    endNest(&body, infoData);
    endNest(&body, linkInfo);
    return netlink(RTM_NEWLINK, NLM_F_REQUEST | NLM_F_ACK | NLM_F_CREATE | NLM_F_EXCL, body, err);
}

bool delRmnetLink(const std::string& name, std::string* err) {
    unsigned index = if_nametoindex(name.c_str());
    if (!index) return true;
    ifinfomsg ifi{};
    ifi.ifi_family = AF_UNSPEC;
    ifi.ifi_index = index;
    std::vector<uint8_t> body(sizeof(ifi));
    std::memcpy(body.data(), &ifi, sizeof(ifi));
    return netlink(RTM_DELLINK, NLM_F_REQUEST | NLM_F_ACK, body, err);
}

bool readIpv4(const std::vector<uint8_t>& v, std::string* out) {
    if (v.size() < 4) return false;
    uint32_t le = 0;
    if (!getLe(v, 0, &le)) return false;
    uint32_t be = htonl(le);
    char buf[INET_ADDRSTRLEN] = {};
    if (!inet_ntop(AF_INET, &be, buf, sizeof(buf))) return false;
    *out = buf;
    return true;
}

std::string prefixFromMask(uint32_t mask) {
    uint32_t bits = 0;
    while (mask & 0x80000000u) {
        bits++;
        mask <<= 1;
    }
    return std::to_string(bits);
}

}  // namespace

DataCallSetup DataCallManager::setup(int32_t cid, const aidlData::DataProfileInfo& profile,
                                     bool roamingAllowed) {
    DataCallSetup out;
    out.result.cid = cid;
    out.result.suggestedRetryTime = RadioConst::VALUE_UNAVAILABLE_LONG;

    std::lock_guard<std::mutex> lock(mLock);
    if (mCalls.count(cid)) {
        out.result.cause = aidlData::DataCallFailCause::NSAPI_IN_USE;
        out.error = RadioError::INVALID_ARGUMENTS;
        return out;
    }
    unsigned parent = if_nametoindex("rmnet_ipa0");
    if (!parent) {
        LOG(ERROR) << "DATA setup: rmnet_ipa0 not present (ipa2-lite not loaded?)";
        out.result.cause = aidlData::DataCallFailCause::ERROR_UNSPECIFIED;
        out.error = RadioError::RADIO_NOT_AVAILABLE;
        return out;
    }
    uint8_t muxId = 0;
    std::string ifname;
    for (uint8_t candidate = mNextMux; candidate != mNextMux - 1 && candidate != 0; candidate++) {
        std::string name = "rmnet_data" + std::to_string(candidate);
        bool used = false;
        for (const auto& entry : mCalls) used |= entry.second.muxId == candidate;
        if (!used && if_nametoindex(name.c_str()) == 0) {
            muxId = candidate;
            ifname = name;
            break;
        }
    }
    if (!muxId) {
        out.result.cause = aidlData::DataCallFailCause::INSUFFICIENT_RESOURCES;
        out.error = RadioError::NO_RESOURCES;
        return out;
    }
    LOG(INFO) << "DATA setup cid=" << cid << " apn_len=" << profile.apn.size()
              << " family=" << (int)ipFamily(profile) << " mux=" << (int)muxId
              << " roaming=" << roamingAllowed << " ifname=" << ifname;

    // Port/format/mux binding first (qrild's sequence), then the call itself.
    {
        std::vector<uint8_t> t;
        std::vector<uint8_t> port;
        putTlvU32(&port, 0, 4);
        putTlvU32(&port, 4, 1);
        putTlvU32(&port, 8, 0);
        putTlvU32(&port, 12, 0);
        putTlvBytes(&t, 0x11, port.data(), port.size());
        auto r = qmi(kDpm, "DPM_OPEN_PORT", 0x20, t);
        if (!r || !r->ok()) LOG(WARNING) << "DATA DPM open port unavailable, continuing";
    }
    {
        std::vector<uint8_t> t;
        putTlvU32(&t, 0x01, 1);
        auto r = qmi(kWds, "WDS_BIND_SUBSCRIPTION", 0xAF, t);
        if (!r || !r->ok()) LOG(WARNING) << "DATA WDS bind subscription unavailable, continuing";
    }
    {
        std::vector<uint8_t> t;
        putTlvU32(&t, 0x11, 1);  // QMAP link protocol
        putTlvU32(&t, 0x12, 0);  // no uplink aggregation
        putTlvU32(&t, 0x13, 0);  // no downlink aggregation
        putEndpoint(&t, 0x17);
        auto r = qmi(kWda, "WDA_SET_DATA_FORMAT", 0x20, t);
        if (!r || !r->ok()) LOG(WARNING) << "DATA WDA set data format unavailable, continuing";
    }
    {
        std::vector<uint8_t> t;
        putEndpoint(&t, 0x10);
        putTlvU8(&t, 0x11, muxId);
        auto r = qmi(kWds, "WDS_BIND_MUX_DATA_PORT", 0xA2, t);
        if (!r || !r->ok()) {
            // This 2016 MPSS answers error 1 (INVALID) to the mux/DPM/format
            // binding calls; qmicli's IPA setup does not need them to bring
            // up a call. Continue so START_NETWORK_INTERFACE tells us the real
            // reason (e.g. NO_SIM) instead of failing on an optional call.
            LOG(WARNING) << "DATA WDS mux binding unsupported (" << (r ? r->error : 0xffff)
                         << "), continuing";
        }
    }

    std::vector<uint8_t> t;
    if (!profile.apn.empty()) putTlvString(&t, 0x14, profile.apn);
    putTlvU8(&t, 0x19, ipFamily(profile));
    putTlvU8(&t, 0x35, 1);  // QMI_WDS_CALL_TYPE_EMBEDDED
    putEndpoint(&t, 0x3B);
    if (uint8_t auth = qmiAuth(profile)) putTlvU8(&t, 0x16, auth);
    if (!profile.user.empty()) putTlvString(&t, 0x17, profile.user);
    if (!profile.password.empty()) putTlvString(&t, 0x18, profile.password);
    auto start = qmi(kWds, "WDS_START_NETWORK_INTERFACE", 0x20, t, 8000);
    if (!start || !start->ok()) {
        auto f = failureFor(start);
        out.error = f.radio;
        out.result.cause = f.cause;
        return out;
    }
    uint32_t handle = 0;
    if (const auto* h = start->tlv(0x01); h && h->size() >= 4 && getLe(*h, 0, &handle)) {
        LOG(INFO) << "DATA WDS packet data handle=" << handle;
    } else {
        LOG(ERROR) << "DATA WDS start network: no packet data handle";
        out.result.cause = aidlData::DataCallFailCause::ERROR_UNSPECIFIED;
        out.error = RadioError::MODEM_ERR;
        return out;
    }

    // Request DNS, IP, gateway, MTU and IP family (QmiWdsRequestedSettings bits).
    std::vector<uint8_t> maskTlv;
    putTlvU32(&maskTlv, 0x10, 0xb210);
    auto settings = qmi(kWds, "WDS_GET_CURRENT_SETTINGS", 0x2D, maskTlv);
    if (!settings || !settings->ok()) {
        LOG(WARNING) << "DATA WDS get current settings failed; reporting the call without "
                        "address information";
    }

    std::string address, gateway, mask;
    uint32_t mtu = 0;
    std::vector<std::string> dnses;
    if (settings && settings->ok()) {
        if (const auto* v = settings->tlv(0x1e); v && readIpv4(*v, &address)) {
            uint32_t m = 0;
            if (const auto* mt = settings->tlv(0x21); mt && mt->size() >= 4 && getLe(*mt, 0, &m))
                mask = prefixFromMask(m);
        }
        if (const auto* v = settings->tlv(0x20)) readIpv4(*v, &gateway);
        for (int t : {0x15, 0x16}) {
            if (const auto* v = settings->tlv(static_cast<uint8_t>(t))) {
                std::string dns;
                if (readIpv4(*v, &dns)) dnses.push_back(dns);
            }
        }
        if (const auto* v = settings->tlv(0x29); v && v->size() >= 4 && getLe(*v, 0, &mtu) &&
                                                  mtu >= 576 && mtu <= 65535) {
            mtu &= ~1u;  // AIDL requires an even MTU
        }
        LOG(INFO) << "DATA settings: ipv4=" << !address.empty() << " dns=" << dnses.size()
                  << " mtu=" << mtu << " (addresses not logged)";
    }
    if (!mtu) mtu = profile.mtuV4 ? profile.mtuV4 : 1500;

    std::string err;
    if (!addRmnetLink(ifname, muxId, parent, mtu, &err)) {
        LOG(ERROR) << "DATA rmnet netlink add " << ifname << ": " << err;
        // Roll the modem call back: a data call without its link is useless.
        std::vector<uint8_t> stop;
        putTlvU32(&stop, 0x01, handle);
        qmi(kWds, "WDS_STOP_NETWORK_INTERFACE", 0x21, stop);
        out.result.cause = aidlData::DataCallFailCause::ERROR_UNSPECIFIED;
        out.error = RadioError::INTERNAL_ERR;
        return out;
    }
    LOG(INFO) << "DATA rmnet link " << ifname << " mux=" << (int)muxId << " mtu=" << mtu
              << " created on rmnet_ipa0";

    out.result.cause = aidlData::DataCallFailCause::NONE;
    out.result.suggestedRetryTime = 0;
    out.result.active = aidlData::SetupDataCallResult::DATA_CONNECTION_STATUS_ACTIVE;
    out.result.ifname = ifname;
    out.result.mtuV4 = mtu;
    out.result.dnses = std::move(dnses);
    if (!address.empty()) {
        aidlData::LinkAddress addr;
        addr.address = address + "/" + (mask.empty() ? "32" : mask);
        out.result.addresses.push_back(std::move(addr));
    }
    if (!gateway.empty()) out.result.gateways.push_back(std::move(gateway));
    mCalls[cid] = Call{handle, muxId, ifname, out.result};
    mNextMux = muxId == 255 ? 1 : muxId + 1;
    out.ok = true;
    out.error = RadioError::NONE;
    return out;
}

RadioError DataCallManager::deactivate(int32_t cid) {
    std::lock_guard<std::mutex> lock(mLock);
    auto it = mCalls.find(cid);
    if (it == mCalls.end()) return RadioError::NONE;
    Call call = it->second;
    std::vector<uint8_t> t;
    putTlvU32(&t, 0x01, call.handle);
    auto r = qmi(kWds, "WDS_STOP_NETWORK_INTERFACE", 0x21, t);
    if (r && r->ok()) {
        std::vector<uint8_t> unbind;
        putEndpoint(&unbind, 0x10);
        putTlvU8(&unbind, 0x11, 0);
        qmi(kWds, "WDS_BIND_MUX_DATA_PORT", 0xA2, unbind);
        std::string err;
        if (!delRmnetLink(call.ifname, &err))
            LOG(WARNING) << "DATA rmnet link delete " << call.ifname << ": " << err;
        mCalls.erase(it);
        return RadioError::NONE;
    }
    return failureFor(r).radio;
}

std::vector<aidlData::SetupDataCallResult> DataCallManager::list() const {
    std::lock_guard<std::mutex> lock(mLock);
    std::vector<aidlData::SetupDataCallResult> calls;
    for (const auto& [cid, call] : mCalls) calls.push_back(call.report);
    return calls;
}

}  // namespace axon7m::radio
