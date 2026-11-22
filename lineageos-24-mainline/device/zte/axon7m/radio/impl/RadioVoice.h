/*
 * IRadioVoice stub for the Axon 7 HAL: the interface is declared in VINTF so
 * the framework can bind it, but no call methods are implemented yet (q6voice
 * is new in the kernel and call audio has not been proven). Every request gets
 * a REQUEST_NOT_SUPPORTED response, so no wakelock or bug detector timeouts.
 * config_voice_capable stays false; calls are not offered to the user.
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#pragma once

#include <aidl/android/hardware/radio/voice/BnRadioVoice.h>
#include <aidl/android/hardware/radio/voice/IRadioVoiceIndication.h>
#include <aidl/android/hardware/radio/voice/IRadioVoiceResponse.h>

#include <libminradio/SlotContext.h>

#include <memory>
#include <mutex>
#include <string>
#include <vector>

namespace axon7m::radio {

namespace aidlVoice = ::aidl::android::hardware::radio::voice;
namespace minimal = ::android::hardware::radio::minimal;

class RadioVoice : public aidlVoice::BnRadioVoice {
  public:
    explicit RadioVoice(std::shared_ptr<minimal::SlotContext> context);

    ::ndk::ScopedAStatus setResponseFunctions(
            const std::shared_ptr<aidlVoice::IRadioVoiceResponse>& radioVoiceResponse,
            const std::shared_ptr<aidlVoice::IRadioVoiceIndication>& radioVoiceIndication) override;

::ndk::ScopedAStatus acceptCall(int32_t serial) override;
    ::ndk::ScopedAStatus cancelPendingUssd(int32_t serial) override;
    ::ndk::ScopedAStatus conference(int32_t serial) override;
    ::ndk::ScopedAStatus dial(int32_t serial, const aidlVoice::Dial& dialInfo) override;
    ::ndk::ScopedAStatus emergencyDial(int32_t serial, const aidlVoice::Dial& dialInfo, int32_t categories, const std::vector<std::string>& urns, aidlVoice::EmergencyCallRouting routing, bool hasKnownUserIntentEmergency, bool isTesting) override;
    ::ndk::ScopedAStatus exitEmergencyCallbackMode(int32_t serial) override;
    ::ndk::ScopedAStatus explicitCallTransfer(int32_t serial) override;
    ::ndk::ScopedAStatus getCallForwardStatus(int32_t serial, const aidlVoice::CallForwardInfo& callInfo) override;
    ::ndk::ScopedAStatus getCallWaiting(int32_t serial, int32_t serviceClass) override;
    ::ndk::ScopedAStatus getClip(int32_t serial) override;
    ::ndk::ScopedAStatus getClir(int32_t serial) override;
    ::ndk::ScopedAStatus getCurrentCalls(int32_t serial) override;
    ::ndk::ScopedAStatus getLastCallFailCause(int32_t serial) override;
    ::ndk::ScopedAStatus getMute(int32_t serial) override;
    ::ndk::ScopedAStatus getPreferredVoicePrivacy(int32_t serial) override;
    ::ndk::ScopedAStatus getTtyMode(int32_t serial) override;
    ::ndk::ScopedAStatus handleStkCallSetupRequestFromSim(int32_t serial, bool accept) override;
    ::ndk::ScopedAStatus hangup(int32_t serial, int32_t gsmIndex) override;
    ::ndk::ScopedAStatus hangupForegroundResumeBackground(int32_t serial) override;
    ::ndk::ScopedAStatus hangupWaitingOrBackground(int32_t serial) override;
    ::ndk::ScopedAStatus isVoNrEnabled(int32_t serial) override;
    ::ndk::ScopedAStatus rejectCall(int32_t serial) override;
    ::ndk::ScopedAStatus responseAcknowledgement() override;
    ::ndk::ScopedAStatus sendBurstDtmf(int32_t serial, const std::string& dtmf, int32_t on, int32_t off) override;
    ::ndk::ScopedAStatus sendCdmaFeatureCode(int32_t serial, const std::string& featureCode) override;
    ::ndk::ScopedAStatus sendDtmf(int32_t serial, const std::string& s) override;
    ::ndk::ScopedAStatus sendUssd(int32_t serial, const std::string& ussd) override;
    ::ndk::ScopedAStatus separateConnection(int32_t serial, int32_t gsmIndex) override;
    ::ndk::ScopedAStatus setCallForward(int32_t serial, const aidlVoice::CallForwardInfo& callInfo) override;
    ::ndk::ScopedAStatus setCallWaiting(int32_t serial, bool enable, int32_t serviceClass) override;
    ::ndk::ScopedAStatus setClir(int32_t serial, int32_t status) override;
    ::ndk::ScopedAStatus setMute(int32_t serial, bool enable) override;
    ::ndk::ScopedAStatus setPreferredVoicePrivacy(int32_t serial, bool enable) override;
    ::ndk::ScopedAStatus setTtyMode(int32_t serial, aidlVoice::TtyMode mode) override;
    ::ndk::ScopedAStatus setVoNrEnabled(int32_t serial, bool enable) override;
    ::ndk::ScopedAStatus startDtmf(int32_t serial, const std::string& s) override;
    ::ndk::ScopedAStatus stopDtmf(int32_t serial) override;
    ::ndk::ScopedAStatus switchWaitingOrHoldingAndActive(int32_t serial) override;

  private:
    std::shared_ptr<aidlVoice::IRadioVoiceResponse> respond() const {
        std::lock_guard l(mLock);
        return mResponse;
    }

    mutable std::mutex mLock;
    std::shared_ptr<aidlVoice::IRadioVoiceResponse> mResponse;
    std::shared_ptr<aidlVoice::IRadioVoiceIndication> mIndication;
};

}  // namespace axon7m::radio
