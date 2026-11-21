/*
 * SPDX-License-Identifier: Apache-2.0
 */
#define LOG_TAG "radio-axon7m"

#include "RadioVoice.h"

#include <libminradio/debug.h>
#include <libminradio/response.h>

#define RADIO_MODULE "Voice"

namespace axon7m::radio {

using ::android::hardware::radio::minimal::notSupported;
using ::ndk::ScopedAStatus;
constexpr auto ok = &ScopedAStatus::ok;

RadioVoice::RadioVoice(std::shared_ptr<minimal::SlotContext> context) {
    (void)context;
}

ScopedAStatus RadioVoice::setResponseFunctions(
        const std::shared_ptr<aidlVoice::IRadioVoiceResponse>& radioVoiceResponse,
        const std::shared_ptr<aidlVoice::IRadioVoiceIndication>& radioVoiceIndication) {
    std::lock_guard l(mLock);
    mResponse = radioVoiceResponse;
    mIndication = radioVoiceIndication;
    return ok();
}

ScopedAStatus RadioVoice::acceptCall(int32_t serial) {
    LOG_CALL;
    if (respond()) respond()->acceptCallResponse(notSupported(serial));
    return ok();
}

ScopedAStatus RadioVoice::cancelPendingUssd(int32_t serial) {
    LOG_CALL;
    if (respond()) respond()->cancelPendingUssdResponse(notSupported(serial));
    return ok();
}

ScopedAStatus RadioVoice::conference(int32_t serial) {
    LOG_CALL;
    if (respond()) respond()->conferenceResponse(notSupported(serial));
    return ok();
}

ScopedAStatus RadioVoice::dial(int32_t serial, const aidlVoice::Dial& dialInfo) {
    LOG_CALL;
    if (respond()) respond()->dialResponse(notSupported(serial));
    return ok();
}

ScopedAStatus RadioVoice::emergencyDial(int32_t serial, const aidlVoice::Dial& dialInfo, int32_t categories, const std::vector<std::string>& urns, aidlVoice::EmergencyCallRouting routing, bool hasKnownUserIntentEmergency, bool isTesting) {
    LOG_CALL;
    if (respond()) respond()->emergencyDialResponse(notSupported(serial));
    return ok();
}

ScopedAStatus RadioVoice::exitEmergencyCallbackMode(int32_t serial) {
    LOG_CALL;
    if (respond()) respond()->exitEmergencyCallbackModeResponse(notSupported(serial));
    return ok();
}

ScopedAStatus RadioVoice::explicitCallTransfer(int32_t serial) {
    LOG_CALL;
    if (respond()) respond()->explicitCallTransferResponse(notSupported(serial));
    return ok();
}

ScopedAStatus RadioVoice::getCallForwardStatus(int32_t serial, const aidlVoice::CallForwardInfo& callInfo) {
    LOG_CALL;
    if (respond()) respond()->getCallForwardStatusResponse(notSupported(serial), {});
    return ok();
}

ScopedAStatus RadioVoice::getCallWaiting(int32_t serial, int32_t serviceClass) {
    LOG_CALL;
    if (respond()) respond()->getCallWaitingResponse(notSupported(serial), {}, {});
    return ok();
}

ScopedAStatus RadioVoice::getClip(int32_t serial) {
    LOG_CALL;
    if (respond()) respond()->getClipResponse(notSupported(serial), {});
    return ok();
}

ScopedAStatus RadioVoice::getClir(int32_t serial) {
    LOG_CALL;
    if (respond()) respond()->getClirResponse(notSupported(serial), {}, {});
    return ok();
}

ScopedAStatus RadioVoice::getCurrentCalls(int32_t serial) {
    LOG_CALL;
    if (respond()) respond()->getCurrentCallsResponse(notSupported(serial), {});
    return ok();
}

ScopedAStatus RadioVoice::getLastCallFailCause(int32_t serial) {
    LOG_CALL;
    if (respond()) respond()->getLastCallFailCauseResponse(notSupported(serial), {});
    return ok();
}

ScopedAStatus RadioVoice::getMute(int32_t serial) {
    LOG_CALL;
    if (respond()) respond()->getMuteResponse(notSupported(serial), {});
    return ok();
}

ScopedAStatus RadioVoice::getPreferredVoicePrivacy(int32_t serial) {
    LOG_CALL;
    if (respond()) respond()->getPreferredVoicePrivacyResponse(notSupported(serial), {});
    return ok();
}

ScopedAStatus RadioVoice::getTtyMode(int32_t serial) {
    LOG_CALL;
    if (respond()) respond()->getTtyModeResponse(notSupported(serial), {});
    return ok();
}

ScopedAStatus RadioVoice::handleStkCallSetupRequestFromSim(int32_t serial, bool accept) {
    LOG_CALL;
    if (respond()) respond()->handleStkCallSetupRequestFromSimResponse(notSupported(serial));
    return ok();
}

ScopedAStatus RadioVoice::hangup(int32_t serial, int32_t gsmIndex) {
    LOG_CALL;
    if (respond()) respond()->hangupConnectionResponse(notSupported(serial));
    return ok();
}

ScopedAStatus RadioVoice::hangupForegroundResumeBackground(int32_t serial) {
    LOG_CALL;
    if (respond()) respond()->hangupForegroundResumeBackgroundResponse(notSupported(serial));
    return ok();
}

ScopedAStatus RadioVoice::hangupWaitingOrBackground(int32_t serial) {
    LOG_CALL;
    if (respond()) respond()->hangupWaitingOrBackgroundResponse(notSupported(serial));
    return ok();
}

ScopedAStatus RadioVoice::isVoNrEnabled(int32_t serial) {
    LOG_CALL;
    if (respond()) respond()->isVoNrEnabledResponse(notSupported(serial), {});
    return ok();
}

ScopedAStatus RadioVoice::rejectCall(int32_t serial) {
    LOG_CALL;
    if (respond()) respond()->rejectCallResponse(notSupported(serial));
    return ok();
}

ScopedAStatus RadioVoice::responseAcknowledgement() {
    return ok();
}

ScopedAStatus RadioVoice::sendBurstDtmf(int32_t serial, const std::string& dtmf, int32_t on, int32_t off) {
    LOG_CALL;
    if (respond()) respond()->sendBurstDtmfResponse(notSupported(serial));
    return ok();
}

ScopedAStatus RadioVoice::sendCdmaFeatureCode(int32_t serial, const std::string& featureCode) {
    LOG_CALL;
    if (respond()) respond()->sendCdmaFeatureCodeResponse(notSupported(serial));
    return ok();
}

ScopedAStatus RadioVoice::sendDtmf(int32_t serial, const std::string& s) {
    LOG_CALL;
    if (respond()) respond()->sendDtmfResponse(notSupported(serial));
    return ok();
}

ScopedAStatus RadioVoice::sendUssd(int32_t serial, const std::string& ussd) {
    LOG_CALL;
    if (respond()) respond()->sendUssdResponse(notSupported(serial));
    return ok();
}

ScopedAStatus RadioVoice::separateConnection(int32_t serial, int32_t gsmIndex) {
    LOG_CALL;
    if (respond()) respond()->separateConnectionResponse(notSupported(serial));
    return ok();
}

ScopedAStatus RadioVoice::setCallForward(int32_t serial, const aidlVoice::CallForwardInfo& callInfo) {
    LOG_CALL;
    if (respond()) respond()->setCallForwardResponse(notSupported(serial));
    return ok();
}

ScopedAStatus RadioVoice::setCallWaiting(int32_t serial, bool enable, int32_t serviceClass) {
    LOG_CALL;
    if (respond()) respond()->setCallWaitingResponse(notSupported(serial));
    return ok();
}

ScopedAStatus RadioVoice::setClir(int32_t serial, int32_t status) {
    LOG_CALL;
    if (respond()) respond()->setClirResponse(notSupported(serial));
    return ok();
}

ScopedAStatus RadioVoice::setMute(int32_t serial, bool enable) {
    LOG_CALL;
    if (respond()) respond()->setMuteResponse(notSupported(serial));
    return ok();
}

ScopedAStatus RadioVoice::setPreferredVoicePrivacy(int32_t serial, bool enable) {
    LOG_CALL;
    if (respond()) respond()->setPreferredVoicePrivacyResponse(notSupported(serial));
    return ok();
}

ScopedAStatus RadioVoice::setTtyMode(int32_t serial, aidlVoice::TtyMode mode) {
    LOG_CALL;
    if (respond()) respond()->setTtyModeResponse(notSupported(serial));
    return ok();
}

ScopedAStatus RadioVoice::setVoNrEnabled(int32_t serial, bool enable) {
    LOG_CALL;
    if (respond()) respond()->setVoNrEnabledResponse(notSupported(serial));
    return ok();
}

ScopedAStatus RadioVoice::startDtmf(int32_t serial, const std::string& s) {
    LOG_CALL;
    if (respond()) respond()->startDtmfResponse(notSupported(serial));
    return ok();
}

ScopedAStatus RadioVoice::stopDtmf(int32_t serial) {
    LOG_CALL;
    if (respond()) respond()->stopDtmfResponse(notSupported(serial));
    return ok();
}

ScopedAStatus RadioVoice::switchWaitingOrHoldingAndActive(int32_t serial) {
    LOG_CALL;
    if (respond()) respond()->switchWaitingOrHoldingAndActiveResponse(notSupported(serial));
    return ok();
}

}  // namespace axon7m::radio
