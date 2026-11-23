/*
 * SPDX-License-Identifier: Apache-2.0
 */
#include "Radio.h"

#include "ModemState.h"

#include <aidl/android/hardware/radio/RadioConst.h>
#include <aidl/android/hardware/radio/RadioIndicationType.h>
#include <libminradio/debug.h>
#include <libminradio/response.h>

#define RADIO_MODULE "axon7m"

namespace axon7m::radio {

using ::aidl::android::hardware::radio::RadioConst;
using ::aidl::android::hardware::radio::RadioError;
using ::aidl::android::hardware::radio::RadioIndicationType;
using ::aidl::android::hardware::radio::RadioTechnology;
using ::android::hardware::radio::minimal::errorResponse;
using ::android::hardware::radio::minimal::noError;
using ::ndk::ScopedAStatus;
namespace aidlConfig = ::aidl::android::hardware::radio::config;
namespace aidlData = ::aidl::android::hardware::radio::data;
namespace aidlModem = ::aidl::android::hardware::radio::modem;
namespace aidlNet = ::aidl::android::hardware::radio::network;
namespace aidlSim = ::aidl::android::hardware::radio::sim;
constexpr auto ok = &ScopedAStatus::ok;

// ---- config

ScopedAStatus RadioConfig::getSimSlotsStatus(int32_t serial) {
    LOG_CALL;
    auto cs = cachedCardStatus();
    aidlConfig::SimSlotStatus slot{};
    slot.cardState = cs ? cs->cardState : aidlSim::CardStatus::STATE_ABSENT;
    slot.atr = "";
    slot.eid = "";
    slot.portInfo = {{.iccId = "", .logicalSlotId = 0, .portActive = true}};
    respond()->getSimSlotsStatusResponse(noError(serial), {slot});
    return ok();
}

// ---- data: QMI WDS call + QMAP rmnet link (ipa2-lite, Nura patches 0059-0062)

ScopedAStatus RadioData::setupDataCall(
        int32_t serial, ::aidl::android::hardware::radio::AccessNetwork accessNetwork,
        const aidlData::DataProfileInfo& profile, bool roamingAllowed,
        aidlData::DataRequestReason reason, const std::vector<aidlData::LinkAddress>&,
        const std::vector<std::string>&, int32_t,
        const std::optional<aidlData::SliceInfo>&, bool) {
    LOG_CALL << "network=" << static_cast<int>(accessNetwork) << " reason="
             << static_cast<int>(reason) << " apn_len=" << profile.apn.size();
    int32_t cid = setupDataCallCid();
    DataCallSetup call = mCalls.setup(cid, profile, roamingAllowed);
    call.result.cid = cid;
    if (call.ok) {
        setupDataCallBase(call.result);  // stores it and sends dataCallListChanged
        respond()->setupDataCallResponse(noError(serial), call.result);
    } else {
        // Every failure gets both a RadioError and a 3GPP-style data fail cause;
        // DataCall.cpp logs the exact QMI WDS message, error and TLVs.
        LOG(ERROR) << "DATA setup failed cid=" << cid << " radio_error="
                   << static_cast<int>(call.error) << " fail_cause="
                   << static_cast<int>(call.result.cause);
        respond()->setupDataCallResponse(errorResponse(serial, call.error), call.result);
    }
    return ok();
}

void RadioData::runDebugDataCall() {
    LOG(INFO) << "DATA debug trigger (debug.axon7m.data_test)";
    aidlData::DataProfileInfo profile;
    profile.apn = "";
    profile.protocol = aidlData::PdpProtocolType::IP;
    profile.authType = aidlData::ApnAuthType::NO_PAP_NO_CHAP;
    int32_t cid = setupDataCallCid();
    DataCallSetup call = mCalls.setup(cid, profile, false);
    call.result.cid = cid;
    if (call.ok) {
        setupDataCallBase(call.result);
        LOG(INFO) << "DATA debug call up cid=" << cid << " ifname=" << call.result.ifname;
    } else {
        LOG(ERROR) << "DATA debug call failed cid=" << cid << " radio_error="
                   << static_cast<int>(call.error) << " fail_cause="
                   << static_cast<int>(call.result.cause);
    }
}

ScopedAStatus RadioData::deactivateDataCall(int32_t serial, int32_t cid,
                                            aidlData::DataRequestReason reason) {
    LOG_CALL << cid << " reason=" << static_cast<int>(reason);
    RadioError error = mCalls.deactivate(cid);
    if (error == RadioError::NONE) deactivateDataCallBase(cid);
    respond()->deactivateDataCallResponse(errorResponse(serial, error));
    return ok();
}

ScopedAStatus RadioData::getDataCallList(int32_t serial) {
    LOG_CALL;
    respond()->getDataCallListResponse(noError(serial), mCalls.list());
    return ok();
}

// ---- modem

RadioModem::RadioModem(std::shared_ptr<minimal::SlotContext> context)
    : minimal::RadioModem(context, {{RadioTechnology::LTE, RadioTechnology::HSPA,
                                     RadioTechnology::UMTS, RadioTechnology::GSM}}) {}

ScopedAStatus RadioModem::setRadioPower(int32_t serial, bool powerOn, bool forEmergencyCall,
                                        bool preferredForEmergencyCall) {
    LOG_CALL << powerOn;
    if (!powerOn) {
        // The GNSS HAL needs the modem's QMI services even in airplane mode;
        // do not take it offline here (RIL-PLAN 3.1, deferred until GNSS has
        // its own power policy).
        LOG(INFO) << "radio off requested: modem stays online for GNSS";
        respond()->setRadioPowerResponse(noError(serial));
        return ok();
    }
    if (!setOperatingModeOnline()) {
        respond()->setRadioPowerResponse(errorResponse(serial, RadioError::MODEM_ERR));
        return ok();
    }
    respond()->setRadioPowerResponse(noError(serial));
    return ok();
}

ScopedAStatus RadioModem::getImei(int32_t serial) {
    LOG_CALL;
    auto imei = cachedImei();
    if (!imei) {
        respond()->getImeiResponse(errorResponse(serial, RadioError::MODEM_ERR), std::nullopt);
        return ok();
    }
    aidlModem::ImeiInfo info{
            .type = aidlModem::ImeiInfo::ImeiType::PRIMARY,
            .imei = *imei,
            .svn = "00",
    };
    respond()->getImeiResponse(noError(serial), info);
    return ok();
}

ScopedAStatus RadioModem::getBasebandVersion(int32_t serial) {
    LOG_CALL;
    respond()->getBasebandVersionResponse(noError(serial),
                                          cachedRevision().value_or("unknown"));
    return ok();
}

// ---- network

ScopedAStatus RadioNetwork::getDataRegistrationState(int32_t serial) {
    LOG_CALL;
    auto reg = cachedRegState();
    if (!reg) {
        respond()->getDataRegistrationStateResponse(errorResponse(serial, RadioError::MODEM_ERR),
                                                    {});
        return ok();
    }
    respond()->getDataRegistrationStateResponse(noError(serial), *reg);
    return ok();
}

ScopedAStatus RadioNetwork::getVoiceRegistrationState(int32_t serial) {
    LOG_CALL;
    auto reg = cachedRegState();
    if (!reg) {
        respond()->getVoiceRegistrationStateResponse(errorResponse(serial, RadioError::MODEM_ERR),
                                                     {});
        return ok();
    }
    reg->accessTechnologySpecificInfo = {};
    respond()->getVoiceRegistrationStateResponse(noError(serial), *reg);
    return ok();
}

ScopedAStatus RadioNetwork::getSignalStrength(int32_t serial) {
    LOG_CALL;
    respond()->getSignalStrengthResponse(noError(serial), cachedSignalStrength());
    return ok();
}

void RadioNetwork::poll() {
    if (!indicate) return;  // the framework has not connected yet
    std::lock_guard l(mPollLock);
    auto reg = cachedRegState();
    if (reg) {
        int st = static_cast<int>(reg->regState) * 100 + static_cast<int>(reg->rat);
        if (mLastReg != st || mLastPlmn != reg->registeredPlmn) {
            mLastReg = st;
            mLastPlmn = reg->registeredPlmn;
            LOG(INFO) << "registration " << toString(reg->regState) << " " << toString(reg->rat)
                      << " " << reg->registeredPlmn;
            indicate()->networkStateChanged(RadioIndicationType::UNSOLICITED);
        }
    }
    auto s = cachedSignalStrength();
    int level = std::max({s.lte.signalStrength == RadioConst::VALUE_UNAVAILABLE ? -1
                                                                                 : s.lte.signalStrength,
                          s.wcdma.signalStrength == RadioConst::VALUE_UNAVAILABLE
                                  ? -1
                                  : s.wcdma.signalStrength,
                          s.gsm.signalStrength == RadioConst::VALUE_UNAVAILABLE
                                  ? -1
                                  : s.gsm.signalStrength});
    if (level != mLastLevel) {
        mLastLevel = level;
        indicate()->currentSignalStrength(RadioIndicationType::UNSOLICITED, s);
    }
}

// ---- SIM

ScopedAStatus RadioSim::getIccCardStatus(int32_t serial) {
    LOG_CALL;
    auto cs = cachedCardStatus();
    if (!cs) {
        aidlSim::CardStatus none{};
        none.cardState = aidlSim::CardStatus::STATE_ABSENT;
        none.gsmUmtsSubscriptionAppIndex = -1;
        none.cdmaSubscriptionAppIndex = -1;
        none.imsSubscriptionAppIndex = -1;
        respond()->getIccCardStatusResponse(errorResponse(serial, RadioError::MODEM_ERR), none);
        return ok();
    }
    respond()->getIccCardStatusResponse(noError(serial), *cs);
    return ok();
}

ScopedAStatus RadioSim::getImsiForApp(int32_t serial, const std::string& aid) {
    LOG_CALL << aid;
    auto imsi = cachedImsi();
    if (!imsi) {
        respond()->getImsiForAppResponse(errorResponse(serial, RadioError::SIM_ERR), "");
        return ok();
    }
    respond()->getImsiForAppResponse(noError(serial), *imsi);
    return ok();
}

ScopedAStatus RadioSim::iccIoForApp(int32_t serial, const aidlSim::IccIo& iccIo) {
    LOG_CALL << iccIo.command << " " << iccIo.fileId;
    // SW 6A82: file not found
    respond()->iccIoForAppResponse(noError(serial), {.sw1 = 0x6A, .sw2 = 0x82, .simResponse = ""});
    return ok();
}

ScopedAStatus RadioSim::iccOpenLogicalChannel(int32_t serial, const std::string& aid, int32_t) {
    LOG_CALL << aid;
    respond()->iccOpenLogicalChannelResponse(errorResponse(serial, RadioError::MISSING_RESOURCE), 0,
                                             {});
    return ok();
}

ScopedAStatus RadioSim::iccTransmitApduBasicChannel(int32_t serial, const aidlSim::SimApdu&) {
    LOG_CALL;
    respond()->iccTransmitApduBasicChannelResponse(
            errorResponse(serial, RadioError::REQUEST_NOT_SUPPORTED), {});
    return ok();
}

ScopedAStatus RadioSim::iccTransmitApduLogicalChannel(int32_t serial, const aidlSim::SimApdu&) {
    LOG_CALL;
    respond()->iccTransmitApduLogicalChannelResponse(
            errorResponse(serial, RadioError::REQUEST_NOT_SUPPORTED), {});
    return ok();
}

void RadioSim::poll() {
    if (!indicate) return;
    std::lock_guard l(mPollLock);
    auto cs = cachedCardStatus();
    if (!cs) return;
    std::pair<int, int> now{cs->cardState,
                            cs->applications.empty() ? -1 : cs->applications[0].appState};
    if (mLast != now) {
        LOG(INFO) << "SIM card state " << now.first << ", application state " << now.second;
        mLast = now;
        indicate()->simStatusChanged(RadioIndicationType::UNSOLICITED);
    }
}

}  // namespace axon7m::radio
