/*
 * GNSS AIDL HAL for the ZTE Axon 7 on mainline Linux (see Gnss.cpp).
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#pragma once

#include <aidl/android/hardware/gnss/BnGnss.h>

#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include "LocClient.h"

namespace aidl::android::hardware::gnss {

// CHECK: the method list below is IGnss V4 (hardware/interfaces/gnss/aidl/
// aidl_api/android.hardware.gnss/4). Every method has `override`, so a
// mismatch is a compile error at the line to fix; a newer interface version
// needs the methods it added (V5 or later: getExtensionGnssAssistanceInterface).
class Gnss : public BnGnss, public ::axon7m::gnss::LocClient::Listener {
  public:
    Gnss();
    ~Gnss() override;

    // Ends the modem's session and the reader thread (before the process exits).
    void shutdown();

    ndk::ScopedAStatus setCallback(const std::shared_ptr<IGnssCallback>& callback) override;
    ndk::ScopedAStatus close() override;
    ndk::ScopedAStatus start() override;
    ndk::ScopedAStatus stop() override;
    ndk::ScopedAStatus startSvStatus() override;
    ndk::ScopedAStatus stopSvStatus() override;
    ndk::ScopedAStatus startNmea() override;
    ndk::ScopedAStatus stopNmea() override;
    ndk::ScopedAStatus setPositionMode(const PositionModeOptions& options) override;
    ndk::ScopedAStatus injectTime(int64_t timeMs, int64_t timeReferenceMs,
                                  int32_t uncertaintyMs) override;
    ndk::ScopedAStatus injectLocation(const GnssLocation& location) override;
    ndk::ScopedAStatus injectBestLocation(const GnssLocation& location) override;
    ndk::ScopedAStatus deleteAidingData(GnssAidingData aidingDataFlags) override;

    // No extensions.
    ndk::ScopedAStatus getExtensionPsds(std::shared_ptr<IGnssPsds>* ret) override;
    ndk::ScopedAStatus getExtensionGnssConfiguration(
            std::shared_ptr<IGnssConfiguration>* ret) override;
    ndk::ScopedAStatus getExtensionGnssMeasurement(
            std::shared_ptr<IGnssMeasurementInterface>* ret) override;
    ndk::ScopedAStatus getExtensionGnssPowerIndication(
            std::shared_ptr<IGnssPowerIndication>* ret) override;
    ndk::ScopedAStatus getExtensionGnssBatching(std::shared_ptr<IGnssBatching>* ret) override;
    ndk::ScopedAStatus getExtensionGnssGeofence(std::shared_ptr<IGnssGeofence>* ret) override;
    ndk::ScopedAStatus getExtensionGnssNavigationMessage(
            std::shared_ptr<IGnssNavigationMessageInterface>* ret) override;
    ndk::ScopedAStatus getExtensionAGnss(std::shared_ptr<IAGnss>* ret) override;
    ndk::ScopedAStatus getExtensionAGnssRil(std::shared_ptr<IAGnssRil>* ret) override;
    ndk::ScopedAStatus getExtensionGnssDebug(std::shared_ptr<IGnssDebug>* ret) override;
    ndk::ScopedAStatus getExtensionGnssVisibilityControl(
            std::shared_ptr<visibility_control::IGnssVisibilityControl>* ret) override;
    ndk::ScopedAStatus getExtensionGnssAntennaInfo(
            std::shared_ptr<IGnssAntennaInfo>* ret) override;
    ndk::ScopedAStatus getExtensionMeasurementCorrections(
            std::shared_ptr<measurement_corrections::IMeasurementCorrectionsInterface>* ret)
            override;

    // LocClient::Listener, on the reader thread
    void onPosition(const ::axon7m::gnss::LocPosition& position) override;
    void onSvInfo(const std::vector<::axon7m::gnss::LocSv>& svs) override;
    void onNmea(const std::string& sentence) override;

  private:
    void updateSession();  // with mutex_ held
    void reportStatus(const std::shared_ptr<IGnssCallback>& callback,
                      IGnssCallback::GnssStatusValue status);

    std::mutex mutex_;  // guards the members up to intervalMs_
    std::shared_ptr<IGnssCallback> callback_;
    bool started_ = false;   // start(): locations wanted
    bool svStatus_ = false;  // startSvStatus()
    bool nmea_ = false;      // startNmea()
    uint32_t intervalMs_ = 1000;

    std::vector<uint16_t> usedSvIds_;  // of the last fix; reader thread only

    ::axon7m::gnss::LocClient loc_;  // last member: its thread calls into this object
};

}  // namespace aidl::android::hardware::gnss
