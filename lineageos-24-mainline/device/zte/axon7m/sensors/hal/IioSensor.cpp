/*
 * IIO-backed sensors for the ZTE Axon 7 (see include/sensors-impl/IioSensor.h).
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#define LOG_TAG "axon7m-sensors"

#include "sensors-impl/IioSensor.h"

#include <dirent.h>
#include <fcntl.h>
#include <unistd.h>

#include <algorithm>
#include <cmath>
#include <cstring>
#include <fstream>
#include <map>
#include <sstream>

#include <android-base/properties.h>
#include <android-base/strings.h>
#include <log/log.h>
#include <utils/SystemClock.h>

namespace aidl {
namespace android {
namespace hardware {
namespace sensors {

using ::android::base::GetIntProperty;
using ::android::base::GetProperty;
using ::android::base::Split;
using ::android::base::Trim;

static constexpr int32_t kMaxDelayUs = 1000 * 1000;
static const char* const kIioDir = "/sys/bus/iio/devices";

IioDevice IioDevice::find(const std::string& name) {
    IioDevice dev;
    DIR* d = opendir(kIioDir);
    if (!d) return dev;
    while (struct dirent* e = readdir(d)) {
        int index;
        if (sscanf(e->d_name, "iio:device%d", &index) != 1) continue;
        std::string dir = std::string(kIioDir) + "/" + e->d_name;
        std::ifstream f(dir + "/name");
        std::string n;
        if (f && std::getline(f, n) && Trim(n) == name) {
            dev.dir = dir;
            dev.index = index;
            break;
        }
    }
    closedir(d);
    return dev;
}

std::string IioDevice::readAttr(const std::string& attr) const {
    std::ifstream f(dir + "/" + attr);
    std::string s;
    if (f) std::getline(f, s);
    return Trim(s);
}

bool IioDevice::writeAttr(const std::string& attr, const std::string& value) const {
    int fd = open((dir + "/" + attr).c_str(), O_WRONLY | O_CLOEXEC);
    if (fd < 0) return false;
    bool ok = write(fd, value.c_str(), value.size()) == (ssize_t)value.size();
    close(fd);
    return ok;
}

static std::array<float, 9> readMatrix(const std::string& chan) {
    std::array<float, 9> m = {0, -1, 0, -1, 0, 0, 0, 0, -1};
    std::string p = GetProperty("ro.vendor.sensors." + chan + ".matrix", "");
    auto v = Split(p, ",");
    if (v.size() == 9) {
        for (int i = 0; i < 9; i++) m[i] = strtof(Trim(v[i]).c_str(), nullptr);
    } else if (!p.empty()) {
        ALOGE("ro.vendor.sensors.%s.matrix: need 9 values, using the default", chan.c_str());
    }
    return m;
}

IioBufferedSensor::IioBufferedSensor(int32_t sensorHandle, ISensorsEventCallback* callback,
                                     const char* iioName, const char* chan, SensorType type,
                                     const char* name, const char* vendor, float maxRange,
                                     float unit, int32_t minDelayUs)
    : Sensor(callback), mIioName(iioName), mChan(chan), mUnit(unit), mMatrix(readMatrix(chan)) {
    mSensorInfo.sensorHandle = sensorHandle;
    mSensorInfo.name = name;
    mSensorInfo.vendor = vendor;
    mSensorInfo.version = 1;
    mSensorInfo.type = type;
    mSensorInfo.typeAsString = "";
    mSensorInfo.maxRange = maxRange;
    mSensorInfo.resolution = unit / 65536.0f;
    mSensorInfo.power = 0.2f;
    mSensorInfo.minDelayUs = minDelayUs;
    mSensorInfo.maxDelayUs = kMaxDelayUs;
    mSensorInfo.fifoReservedEventCount = 0;
    mSensorInfo.fifoMaxEventCount = 0;
    mSensorInfo.requiredPermission = "";
    mSensorInfo.flags = 0;  // continuous
}

// "le:s24/32>>0"
bool IioBufferedSensor::parseScan() {
    struct Elem {
        int index, bytes;
        int axis;  // 0..2 or -1
        Channel c;
    };
    std::vector<Elem> elems;
    const char* axes[] = {"x", "y", "z"};
    std::vector<std::string> names;
    for (int a = 0; a < 3; a++) names.push_back("in_" + mChan + "_" + axes[a]);
    names.push_back("in_timestamp");
    for (size_t n = 0; n < names.size(); n++) {
        mDev.writeAttr("buffer0/" + names[n] + "_en", "1");
        if (mDev.readAttr("buffer0/" + names[n] + "_en") != "1") {
            if (n < 3) {
                ALOGE("%s: %s not enabled", mIioName.c_str(), names[n].c_str());
                return false;
            }
            continue;  // no timestamp channel: fine
        }
        Elem e;
        e.axis = n < 3 ? (int)n : -1;
        e.index = atoi(mDev.readAttr("buffer0/" + names[n] + "_index").c_str());
        std::string t = mDev.readAttr("buffer0/" + names[n] + "_type");
        char endian[3] = {}, sign = 's';
        int real = 0, storage = 0, shift = 0;
        if (sscanf(t.c_str(), "%2[bl]e:%c%d/%d>>%d", endian, &sign, &real, &storage, &shift) < 4 ||
            storage % 8) {
            ALOGE("%s: cannot parse %s_type '%s'", mIioName.c_str(), names[n].c_str(), t.c_str());
            return false;
        }
        e.bytes = storage / 8;
        e.c.bytes = e.bytes;
        e.c.realBits = real;
        e.c.shift = shift;
        e.c.isSigned = sign == 's';
        e.c.bigEndian = endian[0] == 'b';
        elems.push_back(e);
    }
    std::sort(elems.begin(), elems.end(),
              [](const Elem& a, const Elem& b) { return a.index < b.index; });
    int off = 0, maxBytes = 1;
    for (auto& e : elems) {
        off = (off + e.bytes - 1) / e.bytes * e.bytes;  // natural alignment
        e.c.offset = off;
        off += e.bytes;
        maxBytes = std::max(maxBytes, e.bytes);
        if (e.axis >= 0) mAxis[e.axis] = e.c;
    }
    mScanBytes = (off + maxBytes - 1) / maxBytes * maxBytes;
    return mScanBytes > 0;
}

void IioBufferedSensor::applyRate() {
    if (mSamplingPeriodNs <= 0 || mSamplingPeriodNs == mAppliedPeriodNs) return;
    int hz = std::max<int64_t>(1, (1000000000LL + mSamplingPeriodNs / 2) / mSamplingPeriodNs);
    // the attribute may refuse changes while the buffer runs: best effort
    mDev.writeAttr("in_" + mChan + "_sampling_frequency", std::to_string(hz));
    mAppliedPeriodNs = mSamplingPeriodNs;
}

bool IioBufferedSensor::start() {
    if (!mDev.valid()) mDev = IioDevice::find(mIioName);
    if (!mDev.valid()) {
        ALOGE("%s: no IIO device", mIioName.c_str());
        return false;
    }
    mDev.writeAttr("buffer0/enable", "0");
    if (!parseScan()) return false;
    mScale = strtof(mDev.readAttr("in_" + mChan + "_scale").c_str(), nullptr);
    std::string trig = mIioName + "-dev" + std::to_string(mDev.index);
    if (!mDev.writeAttr("trigger/current_trigger", trig))
        ALOGW("%s: could not set trigger %s", mIioName.c_str(), trig.c_str());
    mDev.writeAttr("buffer0/length", "128");
    mAppliedPeriodNs = 0;
    applyRate();
    if (!mDev.writeAttr("buffer0/enable", "1")) {
        ALOGE("%s: could not enable the buffer", mIioName.c_str());
        return false;
    }
    std::string node = "/dev/iio:device" + std::to_string(mDev.index);
    mFd = open(node.c_str(), O_RDONLY | O_NONBLOCK | O_CLOEXEC);
    if (mFd < 0) {
        ALOGE("%s: open %s: %s", mIioName.c_str(), node.c_str(), strerror(errno));
        mDev.writeAttr("buffer0/enable", "0");
        return false;
    }
    ALOGI("%s: started, scale %g, %d-byte scans", mIioName.c_str(), mScale, mScanBytes);
    return true;
}

void IioBufferedSensor::stop() {
    if (mFd >= 0) close(mFd);
    mFd = -1;
    if (mDev.valid()) mDev.writeAttr("buffer0/enable", "0");
    mHave = false;
}

void IioBufferedSensor::activate(bool enable) {
    if (enable == mIsEnabled) return;
    if (enable) {
        std::lock_guard<std::mutex> lock(mRunMutex);
        if (!start()) stop();
    } else {
        Sensor::activate(false);
        std::lock_guard<std::mutex> lock(mRunMutex);
        stop();
        return;
    }
    Sensor::activate(true);
}

static int64_t extract(const uint8_t* p, int bytes, bool bigEndian) {
    uint64_t v = 0;
    for (int i = 0; i < bytes; i++) {
        int b = bigEndian ? i : bytes - 1 - i;
        v = (v << 8) | p[b];
    }
    return (int64_t)v;
}

std::vector<Event> IioBufferedSensor::readEvents() {
    std::vector<Event> events;
    if (mFd < 0) return events;
    applyRate();
    uint8_t buf[64 * 32];
    int per = std::min<int>(sizeof(buf) / mScanBytes, 64);
    ssize_t n;
    while ((n = read(mFd, buf, per * mScanBytes)) >= mScanBytes) {
        const uint8_t* s = buf + (n / mScanBytes - 1) * mScanBytes;  // latest scan
        float in[3];
        for (int a = 0; a < 3; a++) {
            const Channel& c = mAxis[a];
            uint64_t v = (uint64_t)extract(s + c.offset, c.bytes, c.bigEndian) >> c.shift;
            int64_t sv;
            if (c.realBits < 64) {
                uint64_t mask = (1ULL << c.realBits) - 1;
                v &= mask;
                sv = (c.isSigned && (v >> (c.realBits - 1))) ? (int64_t)(v | ~mask) : (int64_t)v;
            } else {
                sv = (int64_t)v;
            }
            in[a] = sv * mScale * mUnit;
        }
        for (int i = 0; i < 3; i++)
            mLast[i] = mMatrix[i * 3] * in[0] + mMatrix[i * 3 + 1] * in[1] +
                       mMatrix[i * 3 + 2] * in[2];
        mHave = true;
        if (n < per * mScanBytes) break;
    }
    if (!mHave) return events;  // nothing measured yet
    Event ev;
    ev.sensorHandle = mSensorInfo.sensorHandle;
    ev.sensorType = mSensorInfo.type;
    ev.timestamp = ::android::elapsedRealtimeNano();
    EventPayload::Vec3 v = {
            .x = mLast[0],
            .y = mLast[1],
            .z = mLast[2],
            .status = SensorStatus::ACCURACY_HIGH,
    };
    ev.payload.set<EventPayload::Tag::vec3>(v);
    events.push_back(ev);
    return events;
}

AxonAccelSensor::AxonAccelSensor(int32_t sensorHandle, ISensorsEventCallback* callback)
    : IioBufferedSensor(sensorHandle, callback, "qcom-smgr-accel", "accel",
                        SensorType::ACCELEROMETER, "BMI160 Accelerometer", "Bosch",
                        16 * 9.80665f, 1.0f, 5000) {}

AxonGyroSensor::AxonGyroSensor(int32_t sensorHandle, ISensorsEventCallback* callback)
    : IioBufferedSensor(sensorHandle, callback, "qcom-smgr-gyro", "anglvel", SensorType::GYROSCOPE,
                        "BMI160 Gyroscope", "Bosch", 2000.0f * M_PI / 180.0f, 1.0f, 5000) {}

AxonMagSensor::AxonMagSensor(int32_t sensorHandle, ISensorsEventCallback* callback)
    : IioBufferedSensor(sensorHandle, callback, "qcom-smgr-mag", "magn",
                        SensorType::MAGNETIC_FIELD, "AK09915 Magnetometer", "AKM", 4912.0f,
                        100.0f /* gauss -> uT */, 20000) {}

IioLightSensor::IioLightSensor(int32_t sensorHandle, ISensorsEventCallback* callback)
    : OnChangeSensor(callback) {
    mSensorInfo.sensorHandle = sensorHandle;
    mSensorInfo.name = "RPR0521 Light";
    mSensorInfo.vendor = "ROHM";
    mSensorInfo.version = 1;
    mSensorInfo.type = SensorType::LIGHT;
    mSensorInfo.typeAsString = "";
    mSensorInfo.maxRange = 43000.0f;
    mSensorInfo.resolution = 1.0f;
    mSensorInfo.power = 0.1f;
    mSensorInfo.minDelayUs = 100 * 1000;
    mSensorInfo.maxDelayUs = kMaxDelayUs;
    mSensorInfo.fifoReservedEventCount = 0;
    mSensorInfo.fifoMaxEventCount = 0;
    mSensorInfo.requiredPermission = "";
    mSensorInfo.flags = static_cast<uint32_t>(SensorInfo::SENSOR_FLAG_BITS_ON_CHANGE_MODE);
}

void IioLightSensor::readEventPayload(EventPayload& payload) {
    if (!mDev.valid()) {
        mDev = IioDevice::find("qcom-smgr-prox-light");
        if (mDev.valid())
            mScale = strtof(mDev.readAttr("in_illuminance_scale").c_str(), nullptr);
    }
    float lux = 0;
    if (mDev.valid()) lux = atoll(mDev.readAttr("in_illuminance_raw").c_str()) * mScale;
    payload.set<EventPayload::Tag::scalar>(lux);
}

IioProximitySensor::IioProximitySensor(int32_t sensorHandle, ISensorsEventCallback* callback)
    : OnChangeSensor(callback),
      // raw counts at or above this level mean "near" (Nura: about 5 with
      // nothing near; 100 is a first guess until measured)
      mNear(GetIntProperty("ro.vendor.sensors.proximity.near_level", 100)) {
    mSensorInfo.sensorHandle = sensorHandle;
    mSensorInfo.name = "RPR0521 Proximity";
    mSensorInfo.vendor = "ROHM";
    mSensorInfo.version = 1;
    mSensorInfo.type = SensorType::PROXIMITY;
    mSensorInfo.typeAsString = "";
    mSensorInfo.maxRange = 5.0f;
    mSensorInfo.resolution = 5.0f;
    mSensorInfo.power = 0.1f;
    mSensorInfo.minDelayUs = 100 * 1000;
    mSensorInfo.maxDelayUs = kMaxDelayUs;
    mSensorInfo.fifoReservedEventCount = 0;
    mSensorInfo.fifoMaxEventCount = 0;
    mSensorInfo.requiredPermission = "";
    mSensorInfo.flags = static_cast<uint32_t>(SensorInfo::SENSOR_FLAG_BITS_ON_CHANGE_MODE |
                                              SensorInfo::SENSOR_FLAG_BITS_WAKE_UP);
}

void IioProximitySensor::readEventPayload(EventPayload& payload) {
    if (!mDev.valid()) mDev = IioDevice::find("qcom-smgr-prox-light");
    float cm = mSensorInfo.maxRange;
    if (mDev.valid() && atoi(mDev.readAttr("in_proximity_raw").c_str()) >= mNear) cm = 0;
    payload.set<EventPayload::Tag::scalar>(cm);
}

}  // namespace sensors
}  // namespace hardware
}  // namespace android
}  // namespace aidl
