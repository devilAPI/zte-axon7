/*
 * SPDX-License-Identifier: Apache-2.0
 */
#define LOG_TAG "radio-axon7m"

#include "RadioMessaging.h"

#include <aidl/android/hardware/radio/RadioIndicationType.h>
#include <libminradio/debug.h>
#include <libminradio/response.h>

#define RADIO_MODULE "Messaging"

namespace axon7m::radio {

using ::aidl::android::hardware::radio::RadioError;
using ::aidl::android::hardware::radio::RadioIndicationType;
using ::android::hardware::radio::minimal::errorResponse;
using ::android::hardware::radio::minimal::noError;
using ::android::hardware::radio::minimal::notSupported;
using ::ndk::ScopedAStatus;
constexpr auto ok = &ScopedAStatus::ok;

RadioMessaging::RadioMessaging(std::shared_ptr<minimal::SlotContext> context) {
    (void)context;
}

ScopedAStatus RadioMessaging::setResponseFunctions(
        const std::shared_ptr<aidlMsg::IRadioMessagingResponse>& radioMessagingResponse,
        const std::shared_ptr<aidlMsg::IRadioMessagingIndication>& radioMessagingIndication) {
    std::lock_guard l(mLock);
    mResponse = radioMessagingResponse;
    mIndication = radioMessagingIndication;
    return ok();
}

ScopedAStatus RadioMessaging::acknowledgeLastIncomingCdmaSms(int32_t serial, const aidlMsg::CdmaSmsAck& smsAck) {
    LOG_CALL;
    if (respond()) respond()->acknowledgeLastIncomingCdmaSmsResponse(notSupported(serial));
    return ok();
}

ScopedAStatus RadioMessaging::deleteSmsOnRuim(int32_t serial, int32_t index) {
    LOG_CALL;
    if (respond()) respond()->deleteSmsOnRuimResponse(notSupported(serial));
    return ok();
}

ScopedAStatus RadioMessaging::deleteSmsOnSim(int32_t serial, int32_t index) {
    LOG_CALL;
    if (respond()) respond()->deleteSmsOnSimResponse(notSupported(serial));
    return ok();
}

ScopedAStatus RadioMessaging::getCdmaBroadcastConfig(int32_t serial) {
    LOG_CALL;
    if (respond()) respond()->getCdmaBroadcastConfigResponse(notSupported(serial), {});
    return ok();
}

ScopedAStatus RadioMessaging::getGsmBroadcastConfig(int32_t serial) {
    LOG_CALL;
    if (respond()) respond()->getGsmBroadcastConfigResponse(notSupported(serial), {});
    return ok();
}

ScopedAStatus RadioMessaging::sendCdmaSms(int32_t serial, const aidlMsg::CdmaSmsMessage& sms) {
    LOG_CALL;
    if (respond()) respond()->sendCdmaSmsResponse(notSupported(serial), {});
    return ok();
}

ScopedAStatus RadioMessaging::sendCdmaSmsExpectMore(int32_t serial, const aidlMsg::CdmaSmsMessage& sms) {
    LOG_CALL;
    if (respond()) respond()->sendCdmaSmsExpectMoreResponse(notSupported(serial), {});
    return ok();
}

ScopedAStatus RadioMessaging::sendImsSms(int32_t serial, const aidlMsg::ImsSmsMessage& message) {
    LOG_CALL;
    if (respond()) respond()->sendImsSmsResponse(notSupported(serial), {});
    return ok();
}

ScopedAStatus RadioMessaging::setCdmaBroadcastActivation(int32_t serial, bool activate) {
    LOG_CALL;
    if (respond()) respond()->setCdmaBroadcastActivationResponse(notSupported(serial));
    return ok();
}

ScopedAStatus RadioMessaging::setCdmaBroadcastConfig(int32_t serial, const std::vector<aidlMsg::CdmaBroadcastSmsConfigInfo>& configInfo) {
    LOG_CALL;
    if (respond()) respond()->setCdmaBroadcastConfigResponse(notSupported(serial));
    return ok();
}

ScopedAStatus RadioMessaging::setGsmBroadcastActivation(int32_t serial, bool activate) {
    LOG_CALL;
    if (respond()) respond()->setGsmBroadcastActivationResponse(notSupported(serial));
    return ok();
}

ScopedAStatus RadioMessaging::setGsmBroadcastConfig(int32_t serial, const std::vector<aidlMsg::GsmBroadcastSmsConfigInfo>& configInfo) {
    LOG_CALL;
    if (respond()) respond()->setGsmBroadcastConfigResponse(notSupported(serial));
    return ok();
}

ScopedAStatus RadioMessaging::writeSmsToRuim(int32_t serial, const aidlMsg::CdmaSmsWriteArgs& cdmaSms) {
    LOG_CALL;
    if (respond()) respond()->writeSmsToRuimResponse(notSupported(serial), {});
    return ok();
}

ScopedAStatus RadioMessaging::writeSmsToSim(int32_t serial, const aidlMsg::SmsWriteArgs& smsWriteArgs) {
    LOG_CALL;
    if (respond()) respond()->writeSmsToSimResponse(notSupported(serial), {});
    return ok();
}

// ---- QMI WMS: 3GPP point-to-point SMS -------------------------------------

// Hex strings from the AIDL (smscPdu, pdu) are concatenated as the modem's
// "raw data"; never log their contents (they contain the message and number).
static std::optional<std::vector<uint8_t>> decodeHex(const std::string& s) {
    if (s.size() % 2) return std::nullopt;
    auto nibble = [](char c) -> int {
        if (c >= '0' && c <= '9') return c - '0';
        if (c >= 'a' && c <= 'f') return c - 'a' + 10;
        if (c >= 'A' && c <= 'F') return c - 'A' + 10;
        return -1;
    };
    std::vector<uint8_t> out;
    out.reserve(s.size() / 2);
    for (size_t i = 0; i < s.size(); i += 2) {
        int hi = nibble(s[i]), lo = nibble(s[i + 1]);
        if (hi < 0 || lo < 0) return std::nullopt;
        out.push_back(static_cast<uint8_t>(hi << 4 | lo));
    }
    return out;
}

static std::vector<uint8_t> rawMessageTlv(const std::vector<uint8_t>& data) {
    // WMS Raw Send TLV 0x01: {u8 format (6 = 3GPP PtP), u16 len, data}
    std::vector<uint8_t> content = {6, static_cast<uint8_t>(data.size()),
                                    static_cast<uint8_t>(data.size() >> 8)};
    content.insert(content.end(), data.begin(), data.end());
    std::vector<uint8_t> tlv = {0x01, static_cast<uint8_t>(content.size()),
                                static_cast<uint8_t>(content.size() >> 8)};
    tlv.insert(tlv.end(), content.begin(), content.end());
    return tlv;
}

void RadioMessaging::start() {
    // Set Event Report: MT messages delivered over the transfer route.
    std::vector<uint8_t> event;
    putTlvU8(&event, 0x10, 1);
    auto report = qmiRequest(kWms, 0x01, event);
    LOG(INFO) << "WMS Set Event Report " << (report && report->ok() ? "ok" : "unsupported");

    // Transfer-only routes for every message class (values observed with WMS
    // Get Routes on this modem; storage 0xff = do not store). Class 2 used to
    // be stored on the SIM, which we cannot do while rmtfs is read-only.
    std::vector<uint8_t> routes = {0x01, 26, 0,  // u16 count + six 4-byte elements
                                   6, 0,  // six elements
                                   0, 0, 0xff, 2,
                                   0, 1, 0xff, 2,
                                   0, 2, 0xff, 2,
                                   0, 3, 0xff, 2,
                                   0, 4, 0xff, 2,
                                   0, 5, 0xff, 2};
    putTlvU8(&routes, 0x10, 1);
    auto setRoutes = qmiRequest(kWms, 0x32, routes);
    LOG(INFO) << "WMS Set Routes " << (setRoutes && setRoutes->ok() ? "ok" : "unsupported");
}

void RadioMessaging::onIndication(uint16_t msg, const QmiResponse& response) {
    if (msg != 0x01) return;  // WMS Event Report
    const auto* t = response.tlv(0x11);  // Transfer Route MT Message
    if (!t || t->size() < 8) return;
    uint32_t transaction = 0;
    uint16_t length = 0;
    getLe(*t, 1, &transaction);
    uint8_t format = (*t)[5];
    getLe(*t, 6, &length);
    if (8u + length > t->size()) return;
    if (format != 6) {  // 3GPP point-to-point
        LOG(WARNING) << "WMS MT message format " << static_cast<int>(format) << " ignored";
        return;
    }
    if ((*t)[0] != 0) {
        std::lock_guard l(mTransactionLock);
        mLastTransaction = transaction;
    }
    auto indicateCallback = indicate();
    if (!indicateCallback) return;  // framework has not called setResponseFunctions yet
    std::vector<uint8_t> pdu(t->begin() + 8, t->begin() + 8 + length);
    indicateCallback->newSms(RadioIndicationType::UNSOLICITED, pdu);
}

ScopedAStatus RadioMessaging::sendSmsImpl(int32_t serial, const std::string& smscPdu,
                                          const std::string& pdu) {
    LOG_CALL << "pdu bytes " << (smscPdu.size() + pdu.size()) / 2;
    auto raw = decodeHex(smscPdu + pdu);
    aidlMsg::SendSmsResult result{};
    if (!raw || raw->empty() || raw->size() > 65535) {
        if (respond()) respond()->sendSmsResponse(
                errorResponse(serial, RadioError::INVALID_ARGUMENT), result);
        return ok();
    }
    // SMS sends may take longer than the usual QMI timeout (network delivery).
    auto r = qmiRequest(kWms, 0x20, rawMessageTlv(*raw), 5000);
    if (r && r->ok()) {
        if (auto* ref = r->tlv(0x01); ref && ref->size() >= 2) getLe(*ref, 0, &result.messageRef);
        if (respond()) respond()->sendSmsResponse(noError(serial), result);
        return ok();
    }
    if (r) {
        if (auto* cause = r->tlv(0x12); cause && cause->size() >= 3) {
            uint16_t rp = 0;
            getLe(*cause, 0, &rp);
            result.errorCode = rp;
        }
    }
    if (respond()) respond()->sendSmsResponse(errorResponse(serial, RadioError::MODEM_ERR), result);
    return ok();
}

ScopedAStatus RadioMessaging::sendSms(int32_t serial, const aidlMsg::GsmSmsMessage& message) {
    return sendSmsImpl(serial, message.smscPdu, message.pdu);
}

ScopedAStatus RadioMessaging::sendSmsExpectMore(int32_t serial,
                                                const aidlMsg::GsmSmsMessage& message) {
    return sendSmsImpl(serial, message.smscPdu, message.pdu);
}

ScopedAStatus RadioMessaging::acknowledgeLastIncomingGsmSms(
        int32_t serial, bool success, aidlMsg::SmsAcknowledgeFailCause cause) {
    LOG_CALL << success;
    (void)cause;
    uint32_t transaction = 0;
    {
        std::lock_guard l(mTransactionLock);
        if (mLastTransaction) transaction = *mLastTransaction;
        mLastTransaction.reset();
    }
    if (!transaction) {
        if (respond()) respond()->acknowledgeLastIncomingGsmSmsResponse(
                errorResponse(serial, RadioError::REQUEST_NOT_SUPPORTED));
        return ok();
    }
    // WMS Send Ack TLV 0x01: {u32 transaction id, u8 protocol (1 = 3GPP),
    // u8 success}. No failure cause TLV: the framework only needs the ack.
    std::vector<uint8_t> tlv = {0x01, 6, 0,
                                static_cast<uint8_t>(transaction),
                                static_cast<uint8_t>(transaction >> 8),
                                static_cast<uint8_t>(transaction >> 16),
                                static_cast<uint8_t>(transaction >> 24),
                                1, static_cast<uint8_t>(success ? 1 : 0)};
    auto r = qmiRequest(kWms, 0x37, tlv);
    if (respond()) respond()->acknowledgeLastIncomingGsmSmsResponse(
            r && r->ok() ? noError(serial) : errorResponse(serial, RadioError::MODEM_ERR));
    return ok();
}

ScopedAStatus RadioMessaging::getSmscAddress(int32_t serial) {
    LOG_CALL;
    // This modem answers WMS 0x34 with QMI error 52 (INVALID_ID); newer
    // firmware returns TLV 0x01 = {char type[3], u8 len, digits}.
    auto r = qmiRequest(kWms, 0x34);
    const auto* a = r && r->ok() ? r->tlv(0x01) : nullptr;
    if (!a || a->size() < 4 || 4u + (*a)[3] > a->size()) {
        if (respond()) respond()->getSmscAddressResponse(
                errorResponse(serial, RadioError::REQUEST_NOT_SUPPORTED), "");
        return ok();
    }
    std::string digits(a->begin() + 4, a->begin() + 4 + (*a)[3]);
    if (respond()) respond()->getSmscAddressResponse(noError(serial), digits);
    return ok();
}

ScopedAStatus RadioMessaging::setSmscAddress(int32_t serial, const std::string& smsc) {
    LOG_CALL;
    (void)smsc;  // WMS Set SMSC (0x35) is not present on this 2016 firmware
    if (respond()) respond()->setSmscAddressResponse(
            errorResponse(serial, RadioError::REQUEST_NOT_SUPPORTED));
    return ok();
}

ScopedAStatus RadioMessaging::reportSmsMemoryStatus(int32_t serial, bool available) {
    LOG_CALL << available;
    // All message classes use the transfer route; no storage to report on.
    if (respond()) respond()->reportSmsMemoryStatusResponse(noError(serial));
    return ok();
}

ScopedAStatus RadioMessaging::acknowledgeIncomingGsmSmsWithPdu(int32_t serial, bool success,
                                                               const std::string& ackPdu) {
    LOG_CALL << success << " ack bytes " << ackPdu.size() / 2;
    if (respond()) respond()->acknowledgeIncomingGsmSmsWithPduResponse(
            errorResponse(serial, RadioError::REQUEST_NOT_SUPPORTED));
    return ok();
}

ScopedAStatus RadioMessaging::responseAcknowledgement() {
    return ok();
}

}  // namespace axon7m::radio
