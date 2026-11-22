/*
 * Radio AIDL HAL for the ZTE Axon 7 on mainline Linux: AOSP's libminradio
 * (copied to ../minradio, built without its fuzzing sanitizers) answers
 * every request; these subclasses fill in what the modem tells over QMI.
 *
 * What works: modem identity (IMEI, baseband version), SIM card state,
 * network registration, operator and signal strength (polled every 5 s and cached,
 * changes are indicated), and mobile-data calls over QMI WDS/WDA/DPM with a
 * QMAP rmnet link on rmnet_ipa0 (ipa2-lite). Not yet: SIM file access (a
 * present SIM never finishes loading), SMS, calls (no q6voice). The radio
 * power switch is only reported: the modem stays online for GNSS.
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#pragma once

#include <libminradio/config/RadioConfig.h>
#include <libminradio/data/RadioData.h>
#include <libminradio/modem/RadioModem.h>
#include <libminradio/network/RadioNetwork.h>
#include <libminradio/sim/RadioSim.h>

#include "DataCall.h"

#include <mutex>
#include <optional>

namespace axon7m::radio {

namespace minimal = ::android::hardware::radio::minimal;

class RadioConfig : public minimal::RadioConfig {
  protected:
    ::ndk::ScopedAStatus getSimSlotsStatus(int32_t serial) override;
};

class RadioData : public minimal::RadioData {
  public:
    using minimal::RadioData::RadioData;

  protected:
    ::ndk::ScopedAStatus setupDataCall(
            int32_t serial, ::aidl::android::hardware::radio::AccessNetwork accessNetwork,
            const ::aidl::android::hardware::radio::data::DataProfileInfo& dataProfileInfo,
            bool roamingAllowed, ::aidl::android::hardware::radio::data::DataRequestReason reason,
            const std::vector<::aidl::android::hardware::radio::data::LinkAddress>& addresses,
            const std::vector<std::string>& dnses, int32_t pduSessionId,
            const std::optional<::aidl::android::hardware::radio::data::SliceInfo>& sliceInfo,
            bool matchAllRuleAllowed) override;
    ::ndk::ScopedAStatus deactivateDataCall(
            int32_t serial, int32_t cid,
            ::aidl::android::hardware::radio::data::DataRequestReason reason) override;
    ::ndk::ScopedAStatus getDataCallList(int32_t serial) override;

  private:
    DataCallManager mCalls;
};

class RadioModem : public minimal::RadioModem {
  public:
    RadioModem(std::shared_ptr<minimal::SlotContext> context);

  protected:
    ::ndk::ScopedAStatus setRadioPower(int32_t serial, bool powerOn, bool forEmergencyCall,
                                       bool preferredForEmergencyCall) override;
    ::ndk::ScopedAStatus getImei(int32_t serial) override;
    ::ndk::ScopedAStatus getBasebandVersion(int32_t serial) override;
};

class RadioNetwork : public minimal::RadioNetwork {
  public:
    using minimal::RadioNetwork::RadioNetwork;
    // poll thread: tell the framework when registration or signal changed
    void poll();

  protected:
    ::ndk::ScopedAStatus getDataRegistrationState(int32_t serial) override;
    ::ndk::ScopedAStatus getVoiceRegistrationState(int32_t serial) override;
    ::ndk::ScopedAStatus getSignalStrength(int32_t serial) override;

  private:
    std::mutex mPollLock;
    std::optional<int> mLastReg;
    std::optional<std::string> mLastPlmn;
    int mLastLevel = -1;
};

class RadioSim : public minimal::RadioSim {
  public:
    using minimal::RadioSim::RadioSim;
    void poll();

  protected:
    ::ndk::ScopedAStatus getIccCardStatus(int32_t serial) override;
    ::ndk::ScopedAStatus getImsiForApp(int32_t serial, const std::string& aid) override;
    // no access to the real SIM's files and channels yet: answer with errors
    // instead of libminradio's virtual SIM (its file system CHECKs requests
    // a real SIM gets, which would abort the HAL)
    ::ndk::ScopedAStatus iccIoForApp(
            int32_t serial, const ::aidl::android::hardware::radio::sim::IccIo& iccIo) override;
    ::ndk::ScopedAStatus iccOpenLogicalChannel(int32_t serial, const std::string& aid,
                                               int32_t p2) override;
    ::ndk::ScopedAStatus iccTransmitApduBasicChannel(
            int32_t serial, const ::aidl::android::hardware::radio::sim::SimApdu& message) override;
    ::ndk::ScopedAStatus iccTransmitApduLogicalChannel(
            int32_t serial, const ::aidl::android::hardware::radio::sim::SimApdu& message) override;

  private:
    std::mutex mPollLock;
    std::optional<std::pair<int, int>> mLast;  // card state, first app state
};

}  // namespace axon7m::radio
