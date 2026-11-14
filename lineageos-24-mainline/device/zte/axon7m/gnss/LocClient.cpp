/*
 * QMI LOC (location service of the modem) over QRTR, a port of postmarketOS'
 * axon7-gps (Python) that works on the same phone.
 *
 * QRTR: datagram sockets, socket(AF_QIPCRTR, SOCK_DGRAM), addresses are
 * (node, port). Services are found with the kernel's name service: send a
 * control packet QRTR_TYPE_NEW_LOOKUP {service, instance = 0 (any)} to the
 * local node's control port 0xfffffffe; the name service answers on that
 * socket with one QRTR_TYPE_NEW_SERVER {service, instance, node, port} per
 * server, then an all-zero NEW_SERVER (end of list), and afterwards keeps
 * sending NEW_SERVER/DEL_SERVER as servers come and go. LOC is on the modem,
 * so it exists only while the modem runs: without a server the lookup is
 * redone every 5 s on a new socket (closing the old one drops its lookup).
 *
 * QMI on QRTR has no QMUX header. A message is, little-endian:
 *   u8 flags (0 request, 2 response, 4 indication), u16 transaction id,
 *   u16 message id, u16 length of the TLVs that follow
 *   TLVs: u8 type, u16 length, value
 * Responses carry TLV 0x02 {u16 result (0 = ok), u16 error}.
 *
 * LOC messages used (ids as in axon7-gps; TLV layouts from the QMI LOC
 * interface, as in libqmi's qmi-service-loc.json):
 *   0x21 REG_EVENTS   0x01 u64 event mask: 1 position, 2 SV info, 4 NMEA
 *   0x3E SET_NMEA     0x01 u32 sentence type mask
 *   0x22 START        0x01 u8 session id, 0x10 u32 recurrence (1 periodic),
 *                     0x12 u32 intermediate reports (1 on),
 *                     0x13 u32 minimum interval in ms
 *   0x23 STOP         0x01 u8 session id
 *   0x24 POSITION indication, 0x25 SV_INFO indication, 0x26 NMEA indication
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#define LOG_TAG "gnss-axon7m"

#include "LocClient.h"

#include <android-base/logging.h>

#include <poll.h>
#include <sys/eventfd.h>
#include <unistd.h>

#include <algorithm>
#include <cerrno>
#include <cmath>
#include <cstring>
#include <type_traits>

namespace axon7m::gnss {

namespace {

constexpr uint32_t kLocService = 16;
constexpr int kLookupRetryMs = 5000;

constexpr uint8_t kQmiRequest = 0, kQmiResponse = 2, kQmiIndication = 4;
constexpr size_t kQmiHeaderLen = 7;
constexpr uint16_t kMsgRegEvents = 0x21, kMsgStart = 0x22, kMsgStop = 0x23, kMsgSetNmea = 0x3E;
constexpr uint16_t kIndPosition = 0x24, kIndSvInfo = 0x25, kIndNmea = 0x26;
constexpr uint8_t kSessionId = 7;  // any id; STOP names the same one

// The phone is little-endian like QMI, so values are copied as they are.
template <typename T>
void put(std::vector<uint8_t>* out, T v) {
    static_assert(std::is_trivially_copyable<T>::value);
    const auto* p = reinterpret_cast<const uint8_t*>(&v);
    out->insert(out->end(), p, p + sizeof(T));
}

template <typename T>
void putTlv(std::vector<uint8_t>* out, uint8_t type, T v) {
    put<uint8_t>(out, type);
    put<uint16_t>(out, sizeof(T));
    put<T>(out, v);
}

struct Tlv {
    const uint8_t* data = nullptr;
    size_t len = 0;
    explicit operator bool() const { return data != nullptr; }
};

// Value of the TLV `type` (the last one, if repeated), bounds-checked.
Tlv findTlv(const uint8_t* b, size_t n, uint8_t type) {
    Tlv found;
    size_t i = 0;
    while (i + 3 <= n) {
        uint16_t len;
        memcpy(&len, b + i + 1, 2);
        if (i + 3 + len > n) break;
        if (b[i] == type) found = {b + i + 3, len};
        i += 3 + len;
    }
    return found;
}

template <typename T>
bool get(const Tlv& t, size_t off, T* out) {
    if (!t || off + sizeof(T) > t.len) return false;
    memcpy(out, t.data + off, sizeof(T));
    return true;
}

template <typename T>
std::optional<T> value(const uint8_t* b, size_t n, uint8_t type) {
    T v;
    if (!get(findTlv(b, n, type), 0, &v)) return std::nullopt;
    if constexpr (std::is_floating_point<T>::value) {
        if (!std::isfinite(v)) return std::nullopt;
    }
    return v;
}

}  // namespace

LocClient::LocClient(Listener* listener) : listener_(listener), buf_(65536) {
    wakeFd_ = eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK);
    PLOG_IF(ERROR, wakeFd_ < 0) << "eventfd";
    thread_ = std::thread([this] { run(); });
}

LocClient::~LocClient() {
    shutdown();
    closeFd(&wakeFd_);
}

void LocClient::setSession(bool wanted, uint32_t intervalMs) {
    {
        std::lock_guard<std::mutex> lock(mutex_);
        wanted_ = wanted;
        intervalMs_ = intervalMs;
    }
    uint64_t one = 1;
    if (wakeFd_ >= 0) (void)!write(wakeFd_, &one, sizeof(one));
}

void LocClient::shutdown() {
    std::lock_guard<std::mutex> lock(joinMutex_);
    exit_ = true;
    uint64_t one = 1;
    if (wakeFd_ >= 0) (void)!write(wakeFd_, &one, sizeof(one));
    if (thread_.joinable()) thread_.join();
}

void LocClient::closeFd(int* fd) {
    if (*fd >= 0) close(*fd);
    *fd = -1;
}

// Name service lookup of LOC on a new control socket (find_loc in axon7-gps).
void LocClient::startLookup() {
    closeFd(&ctrlFd_);
    nextLookup_ = Clock::now() + std::chrono::milliseconds(kLookupRetryMs);

    int fd = socket(AF_QIPCRTR, SOCK_DGRAM | SOCK_CLOEXEC | SOCK_NONBLOCK, 0);
    if (fd < 0) {
        PLOG_IF(ERROR, !waitingLogged_) << "socket(AF_QIPCRTR) for the lookup";
        waitingLogged_ = true;
        return;
    }
    // A new socket has the local node's id and port 0 (the port is assigned
    // on the first send); the name service is on that node's control port.
    sockaddr_qrtr self{};
    socklen_t len = sizeof(self);
    qrtr_ctrl_pkt pkt{};
    pkt.cmd = QRTR_TYPE_NEW_LOOKUP;
    pkt.server.service = kLocService;
    if (getsockname(fd, reinterpret_cast<sockaddr*>(&self), &len) < 0) {
        PLOG_IF(ERROR, !waitingLogged_) << "getsockname on the QRTR socket";
        waitingLogged_ = true;
        close(fd);
        return;
    }
    sockaddr_qrtr ns{};
    ns.sq_family = AF_QIPCRTR;
    ns.sq_node = self.sq_node;
    ns.sq_port = QRTR_PORT_CTRL;
    if (sendto(fd, &pkt, sizeof(pkt), 0, reinterpret_cast<sockaddr*>(&ns), sizeof(ns)) < 0) {
        PLOG_IF(ERROR, !waitingLogged_) << "QRTR lookup of the LOC service";
        waitingLogged_ = true;
        close(fd);
        return;
    }
    if (!waitingLogged_) LOG(INFO) << "waiting for the modem's LOC service on QRTR";
    waitingLogged_ = true;
    ctrlFd_ = fd;
}

void LocClient::handleCtrl() {
    for (;;) {
        qrtr_ctrl_pkt pkt{};
        ssize_t n = recv(ctrlFd_, &pkt, sizeof(pkt), 0);
        if (n < 0) {
            if (errno == EAGAIN || errno == EINTR) return;
            // e.g. ENETRESET: the name service restarted and forgot the lookup
            PLOG(WARNING) << "QRTR lookup socket";
            serviceLost("lookup socket error");
            closeFd(&ctrlFd_);
            nextLookup_ = Clock::now();
            return;
        }
        if (static_cast<size_t>(n) < sizeof(pkt) || pkt.server.service != kLocService) continue;
        if (pkt.cmd == QRTR_TYPE_NEW_SERVER && pkt.server.port != 0) {
            if (haveService_ && service_.sq_node == pkt.server.node &&
                service_.sq_port == pkt.server.port) {
                continue;
            }
            service_ = {};
            service_.sq_family = AF_QIPCRTR;
            service_.sq_node = pkt.server.node;
            service_.sq_port = pkt.server.port;
            haveService_ = true;
            active_ = false;
            waitingLogged_ = false;
            LOG(INFO) << "LOC service at QRTR node " << service_.sq_node << " port "
                      << service_.sq_port;
        } else if (pkt.cmd == QRTR_TYPE_DEL_SERVER && haveService_ &&
                   service_.sq_node == pkt.server.node && service_.sq_port == pkt.server.port) {
            serviceLost("modem went away");
        }
    }
}

// The lookup socket stays open, so the name service announces the next LOC
// server (after a modem restart) by itself; the 5 s retry is the fallback.
void LocClient::serviceLost(const char* why) {
    if (!haveService_) return;
    LOG(WARNING) << "LOC service lost (" << why << ")";
    haveService_ = false;
    active_ = false;
    nextLookup_ = Clock::now() + std::chrono::milliseconds(kLookupRetryMs);
}

bool LocClient::sendQmi(uint16_t msg, const std::vector<uint8_t>& payload) {
    std::vector<uint8_t> b;
    b.reserve(kQmiHeaderLen + payload.size());
    put<uint8_t>(&b, kQmiRequest);
    put<uint16_t>(&b, ++txn_);
    put<uint16_t>(&b, msg);
    put<uint16_t>(&b, static_cast<uint16_t>(payload.size()));
    b.insert(b.end(), payload.begin(), payload.end());
    if (sendto(dataFd_, b.data(), b.size(), 0, reinterpret_cast<sockaddr*>(&service_),
               sizeof(service_)) < 0) {
        PLOG(WARNING) << "QMI LOC request 0x" << std::hex << msg;
        serviceLost("send failed");
        return false;
    }
    return true;
}

// As axon7-gps: events, all NMEA sentence types, then a periodic session
// with intermediate reports.
bool LocClient::sendStart(uint32_t intervalMs) {
    std::vector<uint8_t> p;
    putTlv<uint64_t>(&p, 0x01, 0x07);  // position, SV info, NMEA
    if (!sendQmi(kMsgRegEvents, p)) return false;
    p.clear();
    putTlv<uint32_t>(&p, 0x01, 0xFFFF);
    if (!sendQmi(kMsgSetNmea, p)) return false;
    p.clear();
    putTlv<uint8_t>(&p, 0x01, kSessionId);
    putTlv<uint32_t>(&p, 0x10, 1);  // periodic fixes
    putTlv<uint32_t>(&p, 0x12, 1);  // intermediate reports on
    putTlv<uint32_t>(&p, 0x13, intervalMs);
    return sendQmi(kMsgStart, p);
}

// Brings the modem's session in line with setSession().
void LocClient::reconcile() {
    bool wanted;
    uint32_t intervalMs;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        wanted = wanted_ && !exit_;
        intervalMs = intervalMs_;
    }
    if (haveService_ && active_ && (!wanted || intervalMs != activeIntervalMs_)) {
        std::vector<uint8_t> p;
        putTlv<uint8_t>(&p, 0x01, kSessionId);
        if (sendQmi(kMsgStop, p)) LOG(INFO) << "LOC session stopped";
        active_ = false;
    }
    if (haveService_ && wanted && !active_ && sendStart(intervalMs)) {
        active_ = true;
        activeIntervalMs_ = intervalMs;
        LOG(INFO) << "LOC session started, interval " << intervalMs << " ms";
    }
}

void LocClient::handleData() {
    for (;;) {
        sockaddr_qrtr from{};
        socklen_t fromLen = sizeof(from);
        ssize_t n = recvfrom(dataFd_, buf_.data(), buf_.size(), 0,
                             reinterpret_cast<sockaddr*>(&from), &fromLen);
        if (n < 0) {
            if (errno == EAGAIN || errno == EINTR) return;
            PLOG(WARNING) << "QRTR socket";
            serviceLost("socket error");
            closeFd(&dataFd_);  // reopened by run()
            return;
        }
        if (!haveService_ || from.sq_node != service_.sq_node ||
            from.sq_port != service_.sq_port || static_cast<size_t>(n) < kQmiHeaderLen) {
            continue;  // not from LOC (e.g. a control packet of the kernel)
        }
        const uint8_t* b = buf_.data();
        uint8_t flags = b[0];
        uint16_t msg, len;
        memcpy(&msg, b + 3, 2);
        memcpy(&len, b + 5, 2);
        if (kQmiHeaderLen + len > static_cast<size_t>(n)) continue;
        const uint8_t* tlvs = b + kQmiHeaderLen;
        if (flags == kQmiResponse) {
            uint16_t result = 0, error = 0;
            Tlv r = findTlv(tlvs, len, 0x02);
            if (get(r, 0, &result) && get(r, 2, &error) && result != 0) {
                LOG(WARNING) << "QMI LOC request 0x" << std::hex << msg << " failed, error 0x"
                             << error;
            }
        } else if (flags == kQmiIndication) {
            handleIndication(msg, tlvs, len);
        }
    }
}

void LocClient::handleIndication(uint16_t msg, const uint8_t* b, size_t n) {
    if (msg == kIndNmea) {
        // 0x01: the sentence, NUL-terminated, with line end
        Tlv t = findTlv(b, n, 0x01);
        if (!t) return;
        const char* text = reinterpret_cast<const char*>(t.data);
        std::string s(text, strnlen(text, t.len));
        while (!s.empty() && (s.back() == '\r' || s.back() == '\n' || s.back() == ' ')) {
            s.pop_back();
        }
        if (!s.empty()) listener_->onNmea(s);
    } else if (msg == kIndSvInfo) {
        // 0x10: u8 count, then 28 bytes per satellite (sv_list in axon7-gps):
        //   u32 valid mask (1 system, 2 id, 4 health, 8 state, 0x10 info
        //   mask, 0x20 elevation, 0x40 azimuth, 0x80 snr), u32 system,
        //   u16 id, u8 health, u32 state, u8 info mask (1 ephemeris,
        //   2 almanac), float elevation, float azimuth, float snr
        std::vector<LocSv> svs;
        Tlv t = findTlv(b, n, 0x10);
        uint8_t count = 0;
        get(t, 0, &count);
        for (size_t k = 0; k < count; k++) {
            size_t o = 1 + 28 * k;
            uint32_t valid;
            uint8_t info;
            LocSv sv;
            if (!get(t, o, &valid) || !get(t, o + 4, &sv.system) || !get(t, o + 8, &sv.svId) ||
                !get(t, o + 11, &sv.state) || !get(t, o + 15, &info) ||
                !get(t, o + 16, &sv.elevation) || !get(t, o + 20, &sv.azimuth) ||
                !get(t, o + 24, &sv.snr)) {
                break;
            }
            if ((valid & 0x03) != 0x03) continue;  // no system or id
            if (!(valid & 0x08)) sv.state = 0;
            sv.hasEphemeris = (valid & 0x10) && (info & 0x01);
            sv.hasAlmanac = (valid & 0x10) && (info & 0x02);
            if (!(valid & 0x20) || !std::isfinite(sv.elevation)) sv.elevation = 0;
            if (!(valid & 0x40) || !std::isfinite(sv.azimuth)) sv.azimuth = 0;
            if (!(valid & 0x80) || !std::isfinite(sv.snr)) sv.snr = 0;
            svs.push_back(sv);
        }
        listener_->onSvInfo(svs);
    } else if (msg == kIndPosition) {
        // CHECK: TLV numbers beyond 0x01/0x10/0x11/0x12 (those are used by
        // axon7-gps on this phone) are from the QMI LOC interface definition
        // and not yet seen on the phone.
        LocPosition p;
        p.sessionStatus = value<uint32_t>(b, n, 0x01).value_or(UINT32_MAX);
        p.latitude = value<double>(b, n, 0x10);
        p.longitude = value<double>(b, n, 0x11);
        p.horizontalUncertainty = value<float>(b, n, 0x12);
        p.speed = value<float>(b, n, 0x18);
        p.speedUncertainty = value<float>(b, n, 0x19);
        p.altitudeEllipsoid = value<float>(b, n, 0x1A);
        p.verticalUncertainty = value<float>(b, n, 0x1C);
        p.heading = value<float>(b, n, 0x20);
        p.headingUncertainty = value<float>(b, n, 0x21);
        p.utcMs = value<uint64_t>(b, n, 0x25);
        // 0x2C: satellites used in the fix: u8 count, u16 ids
        Tlv used = findTlv(b, n, 0x2C);
        uint8_t count = 0;
        get(used, 0, &count);
        for (size_t k = 0; k < count; k++) {
            uint16_t id;
            if (!get(used, 1 + 2 * k, &id)) break;
            p.usedSvIds.push_back(id);
        }
        listener_->onPosition(p);
    }
}

void LocClient::run() {
    while (!exit_) {
        if (dataFd_ < 0) {
            dataFd_ = socket(AF_QIPCRTR, SOCK_DGRAM | SOCK_CLOEXEC | SOCK_NONBLOCK, 0);
            PLOG_IF(ERROR, dataFd_ < 0 && !waitingLogged_) << "socket(AF_QIPCRTR)";
        }
        if (!haveService_ && (ctrlFd_ < 0 || Clock::now() >= nextLookup_)) startLookup();
        if (dataFd_ >= 0) reconcile();

        pollfd fds[3] = {{wakeFd_, POLLIN, 0}, {dataFd_, POLLIN, 0}, {ctrlFd_, POLLIN, 0}};
        int timeout = -1;  // with a service: wait for packets or setSession()
        if (!haveService_ || dataFd_ < 0) {
            auto left = std::chrono::duration_cast<std::chrono::milliseconds>(nextLookup_ -
                                                                              Clock::now());
            timeout = static_cast<int>(std::clamp<long long>(left.count() + 1, 1, kLookupRetryMs));
        }
        int r = poll(fds, 3, timeout);  // negative fds are ignored
        if (r < 0) {
            if (errno == EINTR) continue;
            PLOG(ERROR) << "poll";
            break;
        }
        if (fds[0].revents) {
            uint64_t v;
            (void)!read(wakeFd_, &v, sizeof(v));
        }
        if (ctrlFd_ >= 0 && fds[2].revents) handleCtrl();
        if (dataFd_ >= 0 && fds[1].revents) handleData();
    }
    // exit_ is set (or poll failed): end the session
    exit_ = true;
    if (dataFd_ >= 0) reconcile();
    closeFd(&ctrlFd_);
    closeFd(&dataFd_);
}

}  // namespace axon7m::gnss
