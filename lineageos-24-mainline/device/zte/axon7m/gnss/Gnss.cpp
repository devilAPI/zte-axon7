/*
 * GNSS AIDL HAL for the ZTE Axon 7 on mainline Linux. The receiver is in the
 * modem (MSM8996); LocClient talks to its QMI LOC service over QRTR and this
 * file maps that to android.hardware.gnss:
 *   start()/startSvStatus()/startNmea()  one periodic LOC session while any
 *                                        of them is on
 *   position reports with a fix          gnssLocationCb
 *   satellite reports (heard ones)       gnssSvStatusCb
 *   NMEA sentences                       gnssNmeaCb
 * Standalone positioning only: no assistance data (PSDS, SUPL, time or
 * location injection), no measurements, geofences or batching. Without
 * assistance the first fix takes about 10 minutes outdoors.
 * Structure after AOSP's default service (hardware/interfaces/gnss/aidl/
 * default, Apache-2.0).
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#define LOG_TAG "gnss-axon7m"

#include "Gnss.h"

#include <android-base/logging.h>
#include <android/binder_manager.h>
#include <android/binder_process.h>

#include <signal.h>
#include <time.h>
#include <unistd.h>

#include <algorithm>
#include <thread>

namespace aidl::android::hardware::gnss {

using ::axon7m::gnss::LocPosition;
using ::axon7m::gnss::LocSv;
using ::axon7m::gnss::LocSystem;

namespace {

constexpr uint32_t kMinIntervalMs = 1000;  // the interval axon7-gps uses

int64_t clockMs(clockid_t clock) {
    timespec ts{};
    clock_gettime(clock, &ts);
    return static_cast<int64_t>(ts.tv_sec) * 1000 + ts.tv_nsec / 1000000;
}

int64_t bootTimeNs() {
    timespec ts{};
    clock_gettime(CLOCK_BOOTTIME, &ts);
    return static_cast<int64_t>(ts.tv_sec) * 1000000000 + ts.tv_nsec;
}

// Extensions: none. @nullable ones return null; the others cannot (the NDK
// backend refuses to write a null binder), so they return an error, which
// the framework logs and takes as "not there".
// CHECK: which getExtension*() are @nullable in the interface version built
// against (here as in V4); only the log output depends on it.
ndk::ScopedAStatus noExtension() {
    return ndk::ScopedAStatus::fromExceptionCode(EX_UNSUPPORTED_OPERATION);
}

// The modem's satellite numbers (LocClient.h) to Android's per-constellation
// ones (GnssSvInfo.svid). False for systems Android does not know.
bool toAndroidSv(const LocSv& sv, GnssConstellationType* constellation, int32_t* svid) {
    int32_t id = sv.svId;
    switch (static_cast<LocSystem>(sv.system)) {
        case LocSystem::GPS:
            *constellation = GnssConstellationType::GPS;
            break;
        case LocSystem::SBAS:
            *constellation = GnssConstellationType::SBAS;
            if (id >= 33 && id <= 64) id += 87;  // PRN 120-151
            break;
        case LocSystem::GLONASS:
            *constellation = GnssConstellationType::GLONASS;
            if (id >= 65 && id <= 96) id -= 64;  // slot 1-32
            break;
        case LocSystem::QZSS:
            *constellation = GnssConstellationType::QZSS;
            break;
        case LocSystem::COMPASS:
        case LocSystem::BDS:
            *constellation = GnssConstellationType::BEIDOU;
            if (id > 200) id -= 200;
            break;
        case LocSystem::GALILEO:
            *constellation = GnssConstellationType::GALILEO;
            if (id > 300) id -= 300;
            break;
        default:
            return false;
    }
    *svid = id;
    return id > 0;
}

}  // namespace

Gnss::Gnss() : loc_(this) {}

Gnss::~Gnss() {
    loc_.shutdown();
}

void Gnss::shutdown() {
    loc_.shutdown();
}

void Gnss::updateSession() {
    loc_.setSession(started_ || svStatus_ || nmea_, intervalMs_);
}

void Gnss::reportStatus(const std::shared_ptr<IGnssCallback>& callback,
                        IGnssCallback::GnssStatusValue status) {
    if (!callback) return;
    auto ret = callback->gnssStatusCb(status);
    if (!ret.isOk()) LOG(WARNING) << "gnssStatusCb: " << ret.getDescription();
}

ndk::ScopedAStatus Gnss::setCallback(const std::shared_ptr<IGnssCallback>& callback) {
    if (!callback) return ndk::ScopedAStatus::fromServiceSpecificError(ERROR_INVALID_ARGUMENT);
    {
        std::lock_guard<std::mutex> lock(mutex_);
        callback_ = callback;
    }
    // SCHEDULING: the modem makes the fixes at the interval of
    // setPositionMode() by itself. Nothing else: no MSB/MSA, single shot,
    // measurements, geofencing, ...
    auto ret = callback->gnssSetCapabilitiesCb(IGnssCallback::CAPABILITY_SCHEDULING);
    if (!ret.isOk()) LOG(WARNING) << "gnssSetCapabilitiesCb: " << ret.getDescription();

    IGnssCallback::GnssSystemInfo info;
    // 2015: before the year from which raw measurements are expected (the
    // phone is from 2016)
    info.yearOfHw = 2015;
    info.name = "Qualcomm MSM8996 modem, QMI LOC over QRTR (axon7m)";
    ret = callback->gnssSetSystemInfoCb(info);
    if (!ret.isOk()) LOG(WARNING) << "gnssSetSystemInfoCb: " << ret.getDescription();
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Gnss::close() {
    std::lock_guard<std::mutex> lock(mutex_);
    started_ = svStatus_ = nmea_ = false;
    callback_ = nullptr;
    updateSession();
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Gnss::start() {
    std::shared_ptr<IGnssCallback> callback;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (started_) return ndk::ScopedAStatus::ok();
        started_ = true;
        updateSession();
        callback = callback_;
    }
    // The session itself starts when the modem's LOC service is there
    // (LocClient); the framework only needs to know that it was asked for.
    reportStatus(callback, IGnssCallback::GnssStatusValue::SESSION_BEGIN);
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Gnss::stop() {
    std::shared_ptr<IGnssCallback> callback;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!started_) return ndk::ScopedAStatus::ok();
        started_ = false;
        updateSession();
        callback = callback_;
    }
    reportStatus(callback, IGnssCallback::GnssStatusValue::SESSION_END);
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Gnss::startSvStatus() {
    std::lock_guard<std::mutex> lock(mutex_);
    svStatus_ = true;
    updateSession();
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Gnss::stopSvStatus() {
    std::lock_guard<std::mutex> lock(mutex_);
    svStatus_ = false;
    updateSession();
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Gnss::startNmea() {
    std::lock_guard<std::mutex> lock(mutex_);
    nmea_ = true;
    updateSession();
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Gnss::stopNmea() {
    std::lock_guard<std::mutex> lock(mutex_);
    nmea_ = false;
    updateSession();
    return ndk::ScopedAStatus::ok();
}

// Only the interval is used (standalone, periodic). A running session is
// restarted with the new interval by LocClient.
ndk::ScopedAStatus Gnss::setPositionMode(const PositionModeOptions& options) {
    std::lock_guard<std::mutex> lock(mutex_);
    intervalMs_ = static_cast<uint32_t>(
            std::max<int64_t>(options.minIntervalMs, kMinIntervalMs));
    updateSession();
    return ndk::ScopedAStatus::ok();
}

// No assistance: accepted and ignored, so that the framework does not log an
// error for every time or network location it offers.
ndk::ScopedAStatus Gnss::injectTime(int64_t, int64_t, int32_t) {
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Gnss::injectLocation(const GnssLocation&) {
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Gnss::injectBestLocation(const GnssLocation&) {
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Gnss::deleteAidingData(GnssAidingData) {
    LOG(INFO) << "deleteAidingData: not implemented, the modem keeps its data";
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Gnss::getExtensionPsds(std::shared_ptr<IGnssPsds>* ret) {
    *ret = nullptr;
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Gnss::getExtensionGnssConfiguration(std::shared_ptr<IGnssConfiguration>*) {
    return noExtension();
}

ndk::ScopedAStatus Gnss::getExtensionGnssMeasurement(
        std::shared_ptr<IGnssMeasurementInterface>*) {
    return noExtension();
}

ndk::ScopedAStatus Gnss::getExtensionGnssPowerIndication(
        std::shared_ptr<IGnssPowerIndication>*) {
    return noExtension();
}

ndk::ScopedAStatus Gnss::getExtensionGnssBatching(std::shared_ptr<IGnssBatching>* ret) {
    *ret = nullptr;
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Gnss::getExtensionGnssGeofence(std::shared_ptr<IGnssGeofence>* ret) {
    *ret = nullptr;
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Gnss::getExtensionGnssNavigationMessage(
        std::shared_ptr<IGnssNavigationMessageInterface>* ret) {
    *ret = nullptr;
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Gnss::getExtensionAGnss(std::shared_ptr<IAGnss>*) {
    return noExtension();
}

ndk::ScopedAStatus Gnss::getExtensionAGnssRil(std::shared_ptr<IAGnssRil>*) {
    return noExtension();
}

ndk::ScopedAStatus Gnss::getExtensionGnssDebug(std::shared_ptr<IGnssDebug>*) {
    return noExtension();
}

ndk::ScopedAStatus Gnss::getExtensionGnssVisibilityControl(
        std::shared_ptr<visibility_control::IGnssVisibilityControl>*) {
    return noExtension();
}

ndk::ScopedAStatus Gnss::getExtensionGnssAntennaInfo(std::shared_ptr<IGnssAntennaInfo>*) {
    return noExtension();
}

ndk::ScopedAStatus Gnss::getExtensionMeasurementCorrections(
        std::shared_ptr<measurement_corrections::IMeasurementCorrectionsInterface>* ret) {
    *ret = nullptr;
    return ndk::ScopedAStatus::ok();
}

void Gnss::onPosition(const LocPosition& p) {
    // As axon7-gps: a fix is a report with status 0 (success) and a
    // position. Intermediate reports (status 1, in progress) are not passed
    // on. CHECK on the phone: if fixes of a periodic session come with
    // status 1 only, accept `p.sessionStatus <= 1` here.
    if (p.sessionStatus != 0 || !p.latitude || !p.longitude) {
        usedSvIds_.clear();
        return;
    }
    usedSvIds_ = p.usedSvIds;

    std::shared_ptr<IGnssCallback> callback;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!started_) return;  // session only for SV status or NMEA
        callback = callback_;
    }
    if (!callback) return;

    GnssLocation loc;
    loc.gnssLocationFlags = GnssLocation::HAS_LAT_LONG;
    loc.latitudeDegrees = *p.latitude;
    loc.longitudeDegrees = *p.longitude;
    if (p.altitudeEllipsoid) {
        loc.gnssLocationFlags |= GnssLocation::HAS_ALTITUDE;
        loc.altitudeMeters = *p.altitudeEllipsoid;
    }
    if (p.speed) {
        loc.gnssLocationFlags |= GnssLocation::HAS_SPEED;
        loc.speedMetersPerSec = *p.speed;
    }
    if (p.heading) {
        loc.gnssLocationFlags |= GnssLocation::HAS_BEARING;
        loc.bearingDegrees = *p.heading;
    }
    if (p.horizontalUncertainty) {
        loc.gnssLocationFlags |= GnssLocation::HAS_HORIZONTAL_ACCURACY;
        loc.horizontalAccuracyMeters = *p.horizontalUncertainty;
    }
    if (p.verticalUncertainty) {
        loc.gnssLocationFlags |= GnssLocation::HAS_VERTICAL_ACCURACY;
        loc.verticalAccuracyMeters = *p.verticalUncertainty;
    }
    if (p.speedUncertainty) {
        loc.gnssLocationFlags |= GnssLocation::HAS_SPEED_ACCURACY;
        loc.speedAccuracyMetersPerSecond = *p.speedUncertainty;
    }
    if (p.headingUncertainty) {
        loc.gnssLocationFlags |= GnssLocation::HAS_BEARING_ACCURACY;
        loc.bearingAccuracyDegrees = *p.headingUncertainty;
    }
    // UTC of the fix from the modem; the system clock if it sent none
    loc.timestampMillis = p.utcMs ? static_cast<int64_t>(*p.utcMs) : clockMs(CLOCK_REALTIME);
    loc.elapsedRealtime.flags = ElapsedRealtime::HAS_TIMESTAMP_NS;
    loc.elapsedRealtime.timestampNs = bootTimeNs();  // time of arrival

    auto ret = callback->gnssLocationCb(loc);
    if (!ret.isOk()) LOG(WARNING) << "gnssLocationCb: " << ret.getDescription();
}

void Gnss::onSvInfo(const std::vector<LocSv>& svs) {
    std::shared_ptr<IGnssCallback> callback;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!started_ && !svStatus_) return;
        callback = callback_;
    }
    if (!callback) return;

    std::vector<IGnssCallback::GnssSvInfo> list;
    for (const LocSv& sv : svs) {
        IGnssCallback::GnssSvInfo info;
        // The modem lists every satellite it searches for; Android wants
        // the ones with a signal (as "heard" in axon7-gps --status).
        if (sv.snr <= 0 || !toAndroidSv(sv, &info.constellation, &info.svid)) continue;
        info.cN0Dbhz = sv.snr;
        info.basebandCN0DbHz = sv.snr;  // the modem reports one value
        info.elevationDegrees = sv.elevation;
        info.azimuthDegrees = sv.azimuth;
        info.carrierFrequencyHz = 0;  // not reported (no HAS_CARRIER_FREQUENCY)
        int32_t flags = static_cast<int32_t>(IGnssCallback::GnssSvFlags::NONE);
        if (sv.hasEphemeris) {
            flags |= static_cast<int32_t>(IGnssCallback::GnssSvFlags::HAS_EPHEMERIS_DATA);
        }
        if (sv.hasAlmanac) {
            flags |= static_cast<int32_t>(IGnssCallback::GnssSvFlags::HAS_ALMANAC_DATA);
        }
        // CHECK on the phone: the position report's list of used satellites
        // (TLV 0x2C) is assumed to use the same numbers as the SV report.
        if (std::find(usedSvIds_.begin(), usedSvIds_.end(), sv.svId) != usedSvIds_.end()) {
            flags |= static_cast<int32_t>(IGnssCallback::GnssSvFlags::USED_IN_FIX);
        }
        info.svFlag = flags;
        list.push_back(info);
    }
    auto ret = callback->gnssSvStatusCb(list);
    if (!ret.isOk()) LOG(WARNING) << "gnssSvStatusCb: " << ret.getDescription();
}

void Gnss::onNmea(const std::string& sentence) {
    std::shared_ptr<IGnssCallback> callback;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!started_ && !nmea_) return;
        callback = callback_;
    }
    if (!callback) return;
    auto ret = callback->gnssNmeaCb(clockMs(CLOCK_REALTIME), sentence);
    if (!ret.isOk()) LOG(WARNING) << "gnssNmeaCb: " << ret.getDescription();
}

}  // namespace aidl::android::hardware::gnss

using aidl::android::hardware::gnss::Gnss;

int main() {
    // SIGTERM (init stopping the service) and SIGINT are taken by a thread
    // that ends the modem's session before the process exits. Blocked here,
    // before any other thread exists, so that all threads inherit the mask.
    sigset_t signals;
    sigemptyset(&signals);
    sigaddset(&signals, SIGTERM);
    sigaddset(&signals, SIGINT);
    pthread_sigmask(SIG_BLOCK, &signals, nullptr);

    ABinderProcess_setThreadPoolMaxThreadCount(0);
    std::shared_ptr<Gnss> gnss = ndk::SharedRefBase::make<Gnss>();

    std::thread([gnss, signals] {
        int sig = 0;
        while (sigwait(&signals, &sig) != 0) {
        }
        LOG(INFO) << "signal " << sig << ", stopping";
        gnss->shutdown();
        _exit(0);
    }).detach();

    const std::string instance = std::string(Gnss::descriptor) + "/default";
    binder_status_t status = AServiceManager_addService(gnss->asBinder().get(), instance.c_str());
    CHECK_EQ(status, STATUS_OK) << "cannot register " << instance;

    ABinderProcess_joinThreadPool();
    return EXIT_FAILURE;  // not reached
}
