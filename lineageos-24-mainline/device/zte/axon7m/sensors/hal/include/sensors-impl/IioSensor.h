/*
 * Sensors of the ZTE Axon 7 on mainline Linux: the kernel's qcom-smgr IIO
 * drivers (Sensor Manager on the SLPI) behind the AIDL sensors HAL.
 *
 * - qcom-smgr-accel, qcom-smgr-gyro, qcom-smgr-mag: x/y/z through the IIO
 *   buffer (/dev/iio:deviceN) with the device's own trigger
 *   "<name>-dev<N>"; values are raw * in_<chan>_scale (Q16).
 * - qcom-smgr-prox-light: in_illuminance_raw / in_proximity_raw, polled.
 *
 * Axes: Android = M * IIO, M from ro.vendor.sensors.<chan>.matrix
 * ("m11,m12,...,m33"), default x = -y, y = -x, z = -z (ZTE's
 * sensor_def_qcomdev.conf, checked for the accelerometer on Nura).
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#pragma once

#include <array>
#include <vector>
#include <string>

#include "sensors-impl/Sensor.h"

namespace aidl {
namespace android {
namespace hardware {
namespace sensors {

struct IioDevice {
    std::string dir;  // /sys/bus/iio/devices/iio:deviceN
    int index = -1;

    static IioDevice find(const std::string& name);
    bool valid() const { return index >= 0; }
    std::string readAttr(const std::string& attr) const;
    bool writeAttr(const std::string& attr, const std::string& value) const;
};

class IioBufferedSensor : public Sensor {
  public:
    // chan: IIO channel type ("accel", "anglvel", "magn"); unit converts the
    // IIO unit to Android's (magnetometer: gauss -> uT = 100)
    IioBufferedSensor(int32_t sensorHandle, ISensorsEventCallback* callback, const char* iioName,
                      const char* chan, SensorType type, const char* name, const char* vendor,
                      float maxRange, float unit, int32_t minDelayUs);
    void activate(bool enable) override;

  protected:
    std::vector<Event> readEvents() override;
    void readEventPayload(EventPayload&) override {}

  private:
    struct Channel {
        int index = -1;
        int offset = 0;
        int bytes = 0;
        int realBits = 0;
        int shift = 0;
        bool isSigned = true;
        bool bigEndian = false;
    };
    bool start();
    void stop();
    bool parseScan();
    void applyRate();

    IioDevice mDev;
    std::string mIioName;
    std::string mChan;
    float mScale = 0;
    float mUnit;
    std::array<float, 9> mMatrix;
    int mFd = -1;
    Channel mAxis[3];
    int mScanBytes = 0;
    int64_t mAppliedPeriodNs = 0;
    bool mHave = false;
    float mLast[3] = {0, 0, 0};
};

class IioLightSensor : public OnChangeSensor {
  public:
    IioLightSensor(int32_t sensorHandle, ISensorsEventCallback* callback);

  protected:
    void readEventPayload(EventPayload& payload) override;

  private:
    IioDevice mDev;
    float mScale = 0;
};

class IioProximitySensor : public OnChangeSensor {
  public:
    IioProximitySensor(int32_t sensorHandle, ISensorsEventCallback* callback);

  protected:
    void readEventPayload(EventPayload& payload) override;

  private:
    IioDevice mDev;
    int mNear;
};

class AxonAccelSensor : public IioBufferedSensor {
  public:
    AxonAccelSensor(int32_t sensorHandle, ISensorsEventCallback* callback);
};

class AxonGyroSensor : public IioBufferedSensor {
  public:
    AxonGyroSensor(int32_t sensorHandle, ISensorsEventCallback* callback);
};

class AxonMagSensor : public IioBufferedSensor {
  public:
    AxonMagSensor(int32_t sensorHandle, ISensorsEventCallback* callback);
};

}  // namespace sensors
}  // namespace hardware
}  // namespace android
}  // namespace aidl
