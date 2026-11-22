/*
 * Own IRadioMessaging for the Axon 7: QMI WMS (service 5) over QRTR.
 * 3GPP SMS is mapped to Raw Send / Send Ack / Event Report, with transfer-only
 * routes so nothing has to be stored on the (read-only) EFS or on the SIM.
 * CDMA, IMS and cell broadcast requests get REQUEST_NOT_SUPPORTED responses.
 * No SMS can be exercised until a SIM and a network registration are present.
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#pragma once

#include "Qmi.h"

#include <aidl/android/hardware/radio/messaging/BnRadioMessaging.h>
#include <aidl/android/hardware/radio/messaging/IRadioMessagingIndication.h>
#include <aidl/android/hardware/radio/messaging/IRadioMessagingResponse.h>

#include <libminradio/SlotContext.h>

#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <vector>

namespace axon7m::radio {

namespace aidlMsg = ::aidl::android::hardware::radio::messaging;
namespace minimal = ::android::hardware::radio::minimal;

class RadioMessaging : public aidlMsg::BnRadioMessaging {
  public:
    explicit RadioMessaging(std::shared_ptr<minimal::SlotContext> context);

    ::ndk::ScopedAStatus setResponseFunctions(
            const std::shared_ptr<aidlMsg::IRadioMessagingResponse>& radioMessagingResponse,
            const std::shared_ptr<aidlMsg::IRadioMessagingIndication>& radioMessagingIndication)
            override;

    ::ndk::ScopedAStatus acknowledgeLastIncomingCdmaSms(int32_t serial, const aidlMsg::CdmaSmsAck& smsAck) override;
    ::ndk::ScopedAStatus deleteSmsOnRuim(int32_t serial, int32_t index) override;
    ::ndk::ScopedAStatus deleteSmsOnSim(int32_t serial, int32_t index) override;
    ::ndk::ScopedAStatus getCdmaBroadcastConfig(int32_t serial) override;
    ::ndk::ScopedAStatus getGsmBroadcastConfig(int32_t serial) override;
    ::ndk::ScopedAStatus sendCdmaSms(int32_t serial, const aidlMsg::CdmaSmsMessage& sms) override;
    ::ndk::ScopedAStatus sendCdmaSmsExpectMore(int32_t serial, const aidlMsg::CdmaSmsMessage& sms) override;
    ::ndk::ScopedAStatus sendImsSms(int32_t serial, const aidlMsg::ImsSmsMessage& message) override;
    ::ndk::ScopedAStatus setCdmaBroadcastActivation(int32_t serial, bool activate) override;
    ::ndk::ScopedAStatus setCdmaBroadcastConfig(int32_t serial, const std::vector<aidlMsg::CdmaBroadcastSmsConfigInfo>& configInfo) override;
    ::ndk::ScopedAStatus setGsmBroadcastActivation(int32_t serial, bool activate) override;
    ::ndk::ScopedAStatus setGsmBroadcastConfig(int32_t serial, const std::vector<aidlMsg::GsmBroadcastSmsConfigInfo>& configInfo) override;
    ::ndk::ScopedAStatus writeSmsToRuim(int32_t serial, const aidlMsg::CdmaSmsWriteArgs& cdmaSms) override;
    ::ndk::ScopedAStatus writeSmsToSim(int32_t serial, const aidlMsg::SmsWriteArgs& smsWriteArgs) override;
    // Overrides implemented over QMI WMS (not in the generated stub list):
    ::ndk::ScopedAStatus responseAcknowledgement() override;
    ::ndk::ScopedAStatus acknowledgeIncomingGsmSmsWithPdu(int32_t serial, bool success,
                                                           const std::string& ackPdu) override;
    ::ndk::ScopedAStatus acknowledgeLastIncomingGsmSms(
            int32_t serial, bool success, aidlMsg::SmsAcknowledgeFailCause cause) override;
    ::ndk::ScopedAStatus getSmscAddress(int32_t serial) override;
    ::ndk::ScopedAStatus reportSmsMemoryStatus(int32_t serial, bool available) override;
    ::ndk::ScopedAStatus sendSms(int32_t serial, const aidlMsg::GsmSmsMessage& message) override;
    ::ndk::ScopedAStatus sendSmsExpectMore(int32_t serial,
                                           const aidlMsg::GsmSmsMessage& message) override;
    ::ndk::ScopedAStatus setSmscAddress(int32_t serial, const std::string& smsc) override;

    // Startup: ask the modem for MT message indications and route all classes
    // to the transfer path (the EFS is read-only on this port).
    void start();
    // WMS Event Report indication.
    void onIndication(uint16_t msg, const QmiResponse& response);

  private:
    std::shared_ptr<aidlMsg::IRadioMessagingResponse> respond() const {
        std::lock_guard l(mLock);
        return mResponse;
    }
    std::shared_ptr<aidlMsg::IRadioMessagingIndication> indicate() const {
        std::lock_guard l(mLock);
        return mIndication;
    }
    ::ndk::ScopedAStatus sendSmsImpl(int32_t serial, const std::string& smscPdu,
                                     const std::string& pdu);

    mutable std::mutex mLock;
    std::shared_ptr<aidlMsg::IRadioMessagingResponse> mResponse;
    std::shared_ptr<aidlMsg::IRadioMessagingIndication> mIndication;
    std::mutex mTransactionLock;
    std::optional<uint32_t> mLastTransaction;
};

}  // namespace axon7m::radio
