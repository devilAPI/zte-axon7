/*
 * QMI messages and layouts: RIL-PLAN.md section 3.2 and 4 (UIM card status
 * from AOSPM libqril's qril_uim.qmi, NAS/DMS from libqmi's definitions).
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#define LOG_TAG "radio-axon7m"

#include "ModemState.h"

#include "Qmi.h"

#include <aidl/android/hardware/radio/RadioConst.h>
#include <aidl/android/hardware/radio/RadioTechnology.h>
#include <android-base/logging.h>
#include <libminradio/network/structs.h>

#include <algorithm>
#include <mutex>
#include <cstdio>

namespace axon7m::radio {

using ::aidl::android::hardware::radio::RadioConst;
using ::aidl::android::hardware::radio::RadioTechnology;
namespace net = ::aidl::android::hardware::radio::network;
namespace sim = ::aidl::android::hardware::radio::sim;

namespace {

std::string hex(const uint8_t* p, size_t n) {
    std::string s;
    char b[3];
    for (size_t i = 0; i < n; i++) {
        snprintf(b, sizeof(b), "%02x", p[i]);
        s += b;
    }
    return s;
}

std::optional<std::string> stringTlv(uint32_t service, uint16_t msg, uint8_t type) {
    auto r = qmiRequest(service, msg);
    if (!r || !r->ok()) return std::nullopt;
    auto* t = r->tlv(type);
    if (!t || t->empty()) return std::nullopt;
    std::string s(t->begin(), t->end());
    while (!s.empty() && (s.back() == '\0' || s.back() == ' ')) s.pop_back();
    return s;
}

sim::PinState pinState(uint8_t q) {
    switch (q) {
        case 1: return sim::PinState::ENABLED_NOT_VERIFIED;
        case 2: return sim::PinState::ENABLED_VERIFIED;
        case 3: return sim::PinState::DISABLED;
        case 4: return sim::PinState::ENABLED_BLOCKED;
        case 5: return sim::PinState::ENABLED_PERM_BLOCKED;
        default: return sim::PinState::UNKNOWN;
    }
}

}  // namespace

std::optional<sim::CardStatus> readCardStatus() {
    auto r = qmiRequest(kUim, 0x2F);
    if (!r || !r->ok()) return std::nullopt;
    auto* t = r->tlv(0x10);
    sim::CardStatus cs{};
    cs.cardState = sim::CardStatus::STATE_ABSENT;
    cs.gsmUmtsSubscriptionAppIndex = -1;
    cs.cdmaSubscriptionAppIndex = -1;
    cs.imsSubscriptionAppIndex = -1;
    cs.slotMap = {.physicalSlotId = 0, .portId = 0};
    if (!t || t->size() < 9) return cs;
    const std::vector<uint8_t>& b = *t;
    uint16_t gwPrimary = b[0] | b[1] << 8;
    size_t off = 8;
    uint8_t cards = b[off++];
    for (uint8_t c = 0; c < cards; c++) {
        if (off + 6 > b.size()) break;
        uint8_t state = b[off], upin = b[off + 1], napps = b[off + 5];
        off += 6;
        std::vector<sim::AppStatus> apps;
        for (uint8_t a = 0; a < napps; a++) {
            if (off + 7 > b.size()) return cs;
            sim::AppStatus app{};
            uint8_t type = b[off], st = b[off + 1];
            off += 6;
            uint8_t aidLen = b[off++];
            if (off + aidLen + 7 > b.size()) return cs;
            app.aidPtr = hex(&b[off], aidLen);
            off += aidLen;
            app.pin1Replaced = b[off];
            app.pin1 = pinState(b[off + 1]);
            app.pin2 = pinState(b[off + 4]);
            off += 7;
            app.appType = type <= 5 ? type : sim::AppStatus::APP_TYPE_UNKNOWN;
            switch (st) {
                case 1: app.appState = sim::AppStatus::APP_STATE_DETECTED; break;
                case 2: app.appState = sim::AppStatus::APP_STATE_PIN; break;
                case 3:
                case 5: app.appState = sim::AppStatus::APP_STATE_PUK; break;
                case 4: app.appState = sim::AppStatus::APP_STATE_SUBSCRIPTION_PERSO; break;
                case 7: app.appState = sim::AppStatus::APP_STATE_READY; break;
                default: app.appState = sim::AppStatus::APP_STATE_UNKNOWN; break;
            }
            apps.push_back(app);
        }
        if (c != 0) continue;  // single-SIM HAL: slot 1 only
        cs.cardState = state == 1   ? sim::CardStatus::STATE_PRESENT
                       : state == 2 ? sim::CardStatus::STATE_ERROR
                                    : sim::CardStatus::STATE_ABSENT;
        cs.universalPinState = pinState(upin);
        if (state == 1) {
            cs.applications = apps;
            // index_gw_primary: high byte slot, low byte application
            if (gwPrimary != 0xffff && (gwPrimary >> 8) == 0 && (gwPrimary & 0xff) < apps.size())
                cs.gsmUmtsSubscriptionAppIndex = gwPrimary & 0xff;
        }
    }
    return cs;
}

std::optional<net::RegStateResult> readRegState() {
    auto r = qmiRequest(kNas, 0x24);
    if (!r || !r->ok()) return std::nullopt;
    net::RegStateResult res{};
    res.cellIdentity = net::CellIdentity::make<net::CellIdentity::noinit>(true);
    auto* ss = r->tlv(0x01);
    if (!ss || ss->size() < 5) return res;
    uint8_t reg = (*ss)[0], nIf = (*ss)[4];
    uint8_t radioIf = 0;
    for (uint8_t i = 0; i < nIf && 5u + i < ss->size(); i++)
        radioIf = std::max(radioIf, (*ss)[5 + i]);  // LTE 8 > UMTS 5 > GSM 4
    bool roaming = false;
    if (auto* ro = r->tlv(0x10); ro && !ro->empty()) roaming = (*ro)[0] == 0;  // 0 = on
    switch (reg) {
        case 1: res.regState = roaming ? net::RegState::REG_ROAMING : net::RegState::REG_HOME; break;
        case 2: res.regState = net::RegState::NOT_REG_MT_SEARCHING_OP; break;
        case 3: res.regState = net::RegState::REG_DENIED; break;
        case 4: res.regState = net::RegState::UNKNOWN; break;
        default: res.regState = net::RegState::NOT_REG_MT_NOT_SEARCHING_OP; break;
    }
    res.rat = radioIf == 8   ? RadioTechnology::LTE
              : radioIf == 5 ? RadioTechnology::UMTS
              : radioIf == 4 ? RadioTechnology::GSM
                             : RadioTechnology::UNKNOWN;
    if (reg != 1) return res;

    // registered: PLMN (0x12: u16 mcc, u16 mnc, u8 len, description)
    std::string mcc, mnc, name;
    if (auto* p = r->tlv(0x12); p && p->size() >= 5) {
        uint16_t m = (*p)[0] | (*p)[1] << 8, n = (*p)[2] | (*p)[3] << 8;
        char b[8];
        snprintf(b, sizeof(b), "%03u", m);
        mcc = b;
        // 3-digit MNC: TLV 0x29 "MNC PCS digit include status" {u16 mcc, u16 mnc, u8 pcs}
        bool threeDigits = false;
        if (auto* d = r->tlv(0x29); d && d->size() >= 5) threeDigits = (*d)[4] != 0;
        snprintf(b, sizeof(b), threeDigits ? "%03u" : "%02u", n);
        mnc = b;
        uint8_t len = (*p)[4];
        if (5u + len <= p->size()) name.assign(p->begin() + 5, p->begin() + 5 + len);
    }
    net::OperatorInfo op{.alphaLong = name,
                         .alphaShort = name,
                         .operatorNumeric = mcc + mnc,
                         .status = net::OperatorInfo::STATUS_CURRENT};
    res.registeredPlmn = mcc + mnc;
    uint16_t lac = 0, tac = 0;
    uint32_t cid = 0;
    getLe(r->tlv(0x1D) ? *r->tlv(0x1D) : std::vector<uint8_t>{}, 0, &lac);
    getLe(r->tlv(0x1E) ? *r->tlv(0x1E) : std::vector<uint8_t>{}, 0, &cid);
    getLe(r->tlv(0x25) ? *r->tlv(0x25) : std::vector<uint8_t>{}, 0, &tac);
    const int unavailable = RadioConst::VALUE_UNAVAILABLE;
    if (res.rat == RadioTechnology::LTE) {
        net::CellIdentityLte c{};
        c.mcc = mcc;
        c.mnc = mnc;
        c.ci = cid ? static_cast<int>(cid) : unavailable;
        c.pci = unavailable;
        c.tac = tac ? tac : unavailable;
        c.earfcn = unavailable;
        c.operatorNames = op;
        c.bandwidth = unavailable;
        res.cellIdentity = net::CellIdentity::make<net::CellIdentity::lte>(c);
        res.accessTechnologySpecificInfo =
                net::AccessTechnologySpecificInfo::make<
                        net::AccessTechnologySpecificInfo::eutranInfo>(net::EutranRegistrationInfo{});
    } else if (res.rat == RadioTechnology::UMTS) {
        net::CellIdentityWcdma c{};
        c.mcc = mcc;
        c.mnc = mnc;
        c.lac = lac ? lac : unavailable;
        c.cid = cid ? static_cast<int>(cid) : unavailable;
        c.psc = unavailable;
        c.uarfcn = unavailable;
        c.operatorNames = op;
        res.cellIdentity = net::CellIdentity::make<net::CellIdentity::wcdma>(c);
    } else if (res.rat == RadioTechnology::GSM) {
        net::CellIdentityGsm c{};
        c.mcc = mcc;
        c.mnc = mnc;
        c.lac = lac ? lac : unavailable;
        c.cid = cid ? static_cast<int>(cid) : unavailable;
        c.arfcn = unavailable;
        c.bsic = static_cast<int8_t>(0xff);
        c.operatorNames = op;
        res.cellIdentity = net::CellIdentity::make<net::CellIdentity::gsm>(c);
    }
    return res;
}

net::SignalStrength readSignalStrength() {
    auto s = ::android::hardware::radio::minimal::structs::makeSignalStrength();
    auto r = qmiRequest(kNas, 0x4F);
    if (!r || !r->ok()) return s;
    if (auto* g = r->tlv(0x12); g && !g->empty()) {
        int rssi = static_cast<int8_t>((*g)[0]);  // dBm
        s.gsm.signalStrength =
                ::android::hardware::radio::minimal::structs::rssiToSignalStrength(rssi);
        s.gsm.bitErrorRate = 99;
    }
    if (auto* w = r->tlv(0x13); w && w->size() >= 3) {
        int rssi = static_cast<int8_t>((*w)[0]);
        s.wcdma.signalStrength =
                ::android::hardware::radio::minimal::structs::rssiToSignalStrength(rssi);
        s.wcdma.bitErrorRate = 99;
    }
    if (auto* l = r->tlv(0x14); l && l->size() >= 6) {
        int rssi = static_cast<int8_t>((*l)[0]);
        int rsrq = static_cast<int8_t>((*l)[1]);                       // dB, negative
        int rsrp = static_cast<int16_t>((*l)[2] | (*l)[3] << 8);      // dBm, negative
        int snr = static_cast<int16_t>((*l)[4] | (*l)[5] << 8);       // 0.1 dB
        s.lte.signalStrength =
                ::android::hardware::radio::minimal::structs::rssiToSignalStrength(rssi);
        s.lte.rsrp = ::android::hardware::radio::minimal::structs::validateRsrp(rsrp);
        s.lte.rsrq = ::android::hardware::radio::minimal::structs::validateRsrq(rsrq);
        s.lte.rssnr = (snr >= -200 && snr <= 300) ? snr : RadioConst::VALUE_UNAVAILABLE;
    }
    return s;
}

namespace {
std::mutex gCacheLock;
std::optional<sim::CardStatus> gCard;
std::optional<net::RegStateResult> gReg;
std::optional<net::SignalStrength> gSignal;
}  // namespace

void refreshModemState() {
    auto card = readCardStatus();
    auto reg = readRegState();
    auto signal = reg ? std::optional<net::SignalStrength>(readSignalStrength()) : std::nullopt;
    std::lock_guard l(gCacheLock);
    gCard = card;
    gReg = reg;
    gSignal = signal;
}

std::optional<sim::CardStatus> cachedCardStatus() {
    std::lock_guard l(gCacheLock);
    return gCard;
}

std::optional<net::RegStateResult> cachedRegState() {
    std::lock_guard l(gCacheLock);
    return gReg;
}

net::SignalStrength cachedSignalStrength() {
    std::lock_guard l(gCacheLock);
    return gSignal ? *gSignal : ::android::hardware::radio::minimal::structs::makeSignalStrength();
}

std::optional<std::string> readImei() {
    return stringTlv(kDms, 0x25, 0x11);
}

std::optional<std::string> readRevision() {
    return stringTlv(kDms, 0x23, 0x01);
}

std::optional<std::string> readImsi() {
    return stringTlv(kDms, 0x43, 0x01);
}

}  // namespace axon7m::radio
