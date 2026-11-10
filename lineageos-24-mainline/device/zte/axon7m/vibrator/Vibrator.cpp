/*
 * Vibrator AIDL HAL for the ZTE Axon 7 on mainline Linux: the PMI8996 haptics
 * driver (kernel patch 0012, input device "spmi_haptics") is a force-feedback
 * input device with FF_RUMBLE, memless. on()/off() play and stop one rumble
 * effect, setAmplitude() scales its strength, perform() maps the basic
 * effects to short pulses. Everything else (compose, PWLE, always-on) is
 * unsupported. Structure after AOSP's example service
 * (hardware/interfaces/vibrator/aidl/default, Apache-2.0).
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#define LOG_TAG "vibrator.axon7m"

#include <aidl/android/hardware/vibrator/BnVibrator.h>
#include <android-base/logging.h>
#include <android/binder_manager.h>
#include <android/binder_process.h>

#include <dirent.h>
#include <fcntl.h>
#include <linux/input.h>
#include <sys/ioctl.h>
#include <unistd.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>
#include <mutex>
#include <string>
#include <thread>

namespace aidl::android::hardware::vibrator {

static constexpr char kFfName[] = "spmi_haptics";

static int openFfDevice() {
    DIR* d = opendir("/dev/input");
    if (!d) return -1;
    int found = -1;
    while (dirent* e = readdir(d)) {
        if (strncmp(e->d_name, "event", 5)) continue;
        std::string p = std::string("/dev/input/") + e->d_name;
        int fd = open(p.c_str(), O_RDWR | O_CLOEXEC);
        if (fd < 0) continue;
        char name[64] = {};
        unsigned long ff[(FF_MAX + 8 * sizeof(long)) / (8 * sizeof(long))] = {};
        if (ioctl(fd, EVIOCGNAME(sizeof(name) - 1), name) >= 0 && !strcmp(name, kFfName) &&
            ioctl(fd, EVIOCGBIT(EV_FF, sizeof(ff)), ff) >= 0 &&
            (ff[FF_RUMBLE / (8 * sizeof(long))] >> (FF_RUMBLE % (8 * sizeof(long)))) & 1) {
            LOG(INFO) << "force feedback device " << p;
            found = fd;
            break;
        }
        close(fd);
    }
    closedir(d);
    return found;
}

class FfVibrator : public BnVibrator {
  public:
    FfVibrator() : mFd(openFfDevice()) {
        if (mFd < 0) LOG(ERROR) << "no " << kFfName << " force feedback device";
    }

    ndk::ScopedAStatus getCapabilities(int32_t* ret) override {
        *ret = IVibrator::CAP_ON_CALLBACK | IVibrator::CAP_PERFORM_CALLBACK |
               IVibrator::CAP_AMPLITUDE_CONTROL;
        return ndk::ScopedAStatus::ok();
    }

    ndk::ScopedAStatus off() override {
        std::lock_guard lock(mMutex);
        stopLocked();
        return ndk::ScopedAStatus::ok();
    }

    ndk::ScopedAStatus on(int32_t timeoutMs,
                          const std::shared_ptr<IVibratorCallback>& callback) override {
        if (timeoutMs <= 0) return ndk::ScopedAStatus::ok();
        std::lock_guard lock(mMutex);
        if (!playLocked(timeoutMs)) return failed();
        complete(timeoutMs, callback);
        return ndk::ScopedAStatus::ok();
    }

    ndk::ScopedAStatus perform(Effect effect, EffectStrength strength,
                               const std::shared_ptr<IVibratorCallback>& callback,
                               int32_t* ret) override {
        int32_t ms;
        switch (effect) {
            case Effect::TICK: ms = 10; break;
            case Effect::TEXTURE_TICK: ms = 8; break;
            case Effect::CLICK: ms = 20; break;
            case Effect::HEAVY_CLICK: ms = 30; break;
            case Effect::DOUBLE_CLICK: ms = 60; break;
            default: return unsupported();
        }
        float a = strength == EffectStrength::LIGHT ? 0.4f
                  : strength == EffectStrength::MEDIUM ? 0.7f : 1.0f;
        std::lock_guard lock(mMutex);
        float saved = mAmplitude;
        mAmplitude = a;
        bool ok = playLocked(ms);
        mAmplitude = saved;
        if (!ok) return failed();
        complete(ms, callback);
        *ret = ms;
        return ndk::ScopedAStatus::ok();
    }

    ndk::ScopedAStatus getSupportedEffects(std::vector<Effect>* ret) override {
        *ret = {Effect::TICK, Effect::TEXTURE_TICK, Effect::CLICK, Effect::HEAVY_CLICK,
                Effect::DOUBLE_CLICK};
        return ndk::ScopedAStatus::ok();
    }

    ndk::ScopedAStatus setAmplitude(float amplitude) override {
        if (amplitude <= 0.0f || amplitude > 1.0f)
            return ndk::ScopedAStatus::fromExceptionCode(EX_ILLEGAL_ARGUMENT);
        std::lock_guard lock(mMutex);
        mAmplitude = amplitude;
        return ndk::ScopedAStatus::ok();
    }

    // not supported by this hardware/driver
    ndk::ScopedAStatus performVendorEffect(const VendorEffect&,
                                           const std::shared_ptr<IVibratorCallback>&) override {
        return unsupported();
    }
    ndk::ScopedAStatus setExternalControl(bool) override { return unsupported(); }
    ndk::ScopedAStatus getCompositionDelayMax(int32_t*) override { return unsupported(); }
    ndk::ScopedAStatus getCompositionSizeMax(int32_t*) override { return unsupported(); }
    ndk::ScopedAStatus getSupportedPrimitives(std::vector<CompositePrimitive>* s) override {
        s->clear();
        return ndk::ScopedAStatus::ok();
    }
    ndk::ScopedAStatus getPrimitiveDuration(CompositePrimitive, int32_t*) override {
        return unsupported();
    }
    ndk::ScopedAStatus compose(const std::vector<CompositeEffect>&,
                               const std::shared_ptr<IVibratorCallback>&) override {
        return unsupported();
    }
    ndk::ScopedAStatus getSupportedAlwaysOnEffects(std::vector<Effect>* r) override {
        r->clear();
        return ndk::ScopedAStatus::ok();
    }
    ndk::ScopedAStatus alwaysOnEnable(int32_t, Effect, EffectStrength) override {
        return unsupported();
    }
    ndk::ScopedAStatus alwaysOnDisable(int32_t) override { return unsupported(); }
    ndk::ScopedAStatus getResonantFrequency(float*) override { return unsupported(); }
    ndk::ScopedAStatus getQFactor(float*) override { return unsupported(); }
    ndk::ScopedAStatus getFrequencyResolution(float*) override { return unsupported(); }
    ndk::ScopedAStatus getFrequencyMinimum(float*) override { return unsupported(); }
    ndk::ScopedAStatus getBandwidthAmplitudeMap(std::vector<float>*) override {
        return unsupported();
    }
    ndk::ScopedAStatus getPwlePrimitiveDurationMax(int32_t*) override { return unsupported(); }
    ndk::ScopedAStatus getPwleCompositionSizeMax(int32_t*) override { return unsupported(); }
    ndk::ScopedAStatus getSupportedBraking(std::vector<Braking>* s) override {
        s->clear();
        return ndk::ScopedAStatus::ok();
    }
    ndk::ScopedAStatus composePwle(const std::vector<PrimitivePwle>&,
                                   const std::shared_ptr<IVibratorCallback>&) override {
        return unsupported();
    }
    ndk::ScopedAStatus getFrequencyToOutputAccelerationMap(
            std::vector<FrequencyAccelerationMapEntry>*) override {
        return unsupported();
    }
    ndk::ScopedAStatus getPwleV2PrimitiveDurationMaxMillis(int32_t*) override {
        return unsupported();
    }
    ndk::ScopedAStatus getPwleV2PrimitiveDurationMinMillis(int32_t*) override {
        return unsupported();
    }
    ndk::ScopedAStatus getPwleV2CompositionSizeMax(int32_t*) override { return unsupported(); }
    ndk::ScopedAStatus composePwleV2(const CompositePwleV2&,
                                     const std::shared_ptr<IVibratorCallback>&) override {
        return unsupported();
    }

  private:
    static ndk::ScopedAStatus unsupported() {
        return ndk::ScopedAStatus::fromExceptionCode(EX_UNSUPPORTED_OPERATION);
    }
    static ndk::ScopedAStatus failed() {
        return ndk::ScopedAStatus::fromExceptionCode(EX_SERVICE_SPECIFIC);
    }

    // upload (or update) one rumble effect of ms length and start it
    bool playLocked(int32_t ms) {
        if (mFd < 0) return false;
        ff_effect e = {};
        e.type = FF_RUMBLE;
        e.id = mEffectId;
        e.replay.length = static_cast<uint16_t>(std::min<int32_t>(ms, 0xffff));
        e.u.rumble.strong_magnitude = static_cast<uint16_t>(std::lround(mAmplitude * 0xffff));
        if (ioctl(mFd, EVIOCSFF, &e) < 0) {
            PLOG(ERROR) << "EVIOCSFF";
            return false;
        }
        mEffectId = e.id;
        input_event ev = {};
        ev.type = EV_FF;
        ev.code = static_cast<uint16_t>(mEffectId);
        ev.value = 1;
        if (write(mFd, &ev, sizeof(ev)) != sizeof(ev)) {
            PLOG(ERROR) << "start effect";
            return false;
        }
        mGeneration++;
        return true;
    }

    void stopLocked() {
        if (mFd < 0 || mEffectId < 0) return;
        input_event ev = {};
        ev.type = EV_FF;
        ev.code = static_cast<uint16_t>(mEffectId);
        ev.value = 0;
        if (write(mFd, &ev, sizeof(ev)) != sizeof(ev)) PLOG(ERROR) << "stop effect";
        mGeneration++;
    }

    // the callback fires when this vibration ends (unless a newer one started)
    void complete(int32_t ms, const std::shared_ptr<IVibratorCallback>& callback) {
        if (!callback) return;
        uint64_t gen = mGeneration;
        std::thread([this, ms, gen, callback] {
            std::this_thread::sleep_for(std::chrono::milliseconds(ms));
            {
                std::lock_guard lock(mMutex);
                if (gen != mGeneration) return;
            }
            if (!callback->onComplete().isOk()) LOG(ERROR) << "onComplete failed";
        }).detach();
    }

    std::mutex mMutex;
    int mFd;
    int16_t mEffectId = -1;
    float mAmplitude = 1.0f;
    uint64_t mGeneration = 0;
};

}  // namespace aidl::android::hardware::vibrator

int main() {
    ABinderProcess_setThreadPoolMaxThreadCount(0);
    auto vib = ndk::SharedRefBase::make<aidl::android::hardware::vibrator::FfVibrator>();
    const std::string name =
            std::string(aidl::android::hardware::vibrator::FfVibrator::descriptor) + "/default";
    CHECK_EQ(AServiceManager_addService(vib->asBinder().get(), name.c_str()), STATUS_OK);
    ABinderProcess_joinThreadPool();
    return EXIT_FAILURE;
}
