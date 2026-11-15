/*
 * Lights AIDL HAL for the ZTE Axon 7 on mainline Linux.
 *
 * The notification LED is the PMI8994 LPG's tri-colour LED, a multicolour LED
 * class device in mainline (/sys/class/leds/rgb:status, multi_index
 * "blue green red", brightness 0..511). Battery, notification and attention
 * lights share it; the most important one that is on wins (attention, then
 * notifications, then battery). Mainline has no hardware blink pattern for it
 * here (no timer/pattern trigger), so TIMED flashing runs on a thread.
 *
 * The display backlight is not a light here: drm_hwcomposer sets it through
 * the panel's backlight device (SurfaceFlinger display brightness).
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#define LOG_TAG "lights.axon7m"

#include <aidl/android/hardware/light/BnLights.h>
#include <android-base/file.h>
#include <android-base/logging.h>
#include <android-base/strings.h>
#include <android/binder_manager.h>
#include <android/binder_process.h>

#include <algorithm>
#include <cstdlib>
#include <chrono>
#include <condition_variable>
#include <mutex>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

namespace aidl::android::hardware::light {

static const std::string kLed = "/sys/class/leds/rgb:status/";

class RgbLed {
  public:
    RgbLed() {
        std::string s;
        if (::android::base::ReadFileToString(kLed + "max_brightness", &s))
            mMaxBrightness = std::max(1, atoi(s.c_str()));
        if (::android::base::ReadFileToString(kLed + "multi_index", &s)) {
            mIndex = ::android::base::Split(::android::base::Trim(s), " ");
        }
        mOk = mIndex.size() == 3;
        if (!mOk) LOG(ERROR) << "no multicolour LED at " << kLed;
    }
    bool ok() const { return mOk; }

    // colour 0xRRGGBB (alpha ignored), 0 = off
    void set(uint32_t color) {
        if (!mOk || color == mLast) return;
        mLast = color;
        int r = (color >> 16) & 0xff, g = (color >> 8) & 0xff, b = color & 0xff;
        std::ostringstream os;
        for (size_t i = 0; i < mIndex.size(); i++) {
            int v = mIndex[i] == "red" ? r : mIndex[i] == "green" ? g : mIndex[i] == "blue" ? b : 0;
            os << (i ? " " : "") << v * mMaxBrightness / 255;
        }
        if (!::android::base::WriteStringToFile(os.str(), kLed + "multi_intensity"))
            PLOG(ERROR) << "multi_intensity";
        if (!::android::base::WriteStringToFile(std::to_string(color ? mMaxBrightness : 0),
                                                 kLed + "brightness"))
            PLOG(ERROR) << "brightness";
    }

  private:
    bool mOk = false;
    int mMaxBrightness = 255;
    std::vector<std::string> mIndex;
    uint32_t mLast = 0xffffffff;
};

class Lights : public BnLights {
  public:
    Lights() {
        // ids are indexes into mStates; the order is the priority (last wins)
        const LightType types[] = {LightType::BATTERY, LightType::NOTIFICATIONS,
                                   LightType::ATTENTION};
        for (int i = 0; i < 3; i++) {
            HwLight l;
            l.id = i;
            l.ordinal = 0;
            l.type = types[i];
            mLights.push_back(l);
        }
        mStates.resize(mLights.size());
        if (mLed.ok()) mThread = std::thread(&Lights::loop, this);
    }

    ndk::ScopedAStatus setLightState(int32_t id, const HwLightState& state) override {
        if (id < 0 || id >= static_cast<int32_t>(mStates.size()))
            return ndk::ScopedAStatus::fromExceptionCode(EX_UNSUPPORTED_OPERATION);
        {
            std::lock_guard lock(mMutex);
            mStates[id] = state;
            mChanged = true;
        }
        mCond.notify_all();
        return ndk::ScopedAStatus::ok();
    }

    ndk::ScopedAStatus getLights(std::vector<HwLight>* lights) override {
        *lights = mLights;
        return ndk::ScopedAStatus::ok();
    }

  private:
    // the state that shows: the highest-priority light with a colour
    HwLightState currentLocked() {
        for (int i = mStates.size() - 1; i >= 0; i--)
            if (mStates[i].color & 0xffffff) return mStates[i];
        return HwLightState{};
    }

    void loop() {
        std::unique_lock lock(mMutex);
        bool on = true;
        for (;;) {
            mChanged = false;
            HwLightState s = currentLocked();
            uint32_t color = s.color & 0xffffff;
            // alpha scales the colour (the framework passes 0xff for full)
            uint32_t a = (static_cast<uint32_t>(s.color) >> 24) & 0xff;
            if (a && a != 0xff) {
                uint32_t r = ((color >> 16) & 0xff) * a / 255, g = ((color >> 8) & 0xff) * a / 255,
                         b = (color & 0xff) * a / 255;
                color = (r << 16) | (g << 8) | b;
            }
            bool blink = color && s.flashMode != FlashMode::NONE && s.flashOnMs > 0 &&
                         s.flashOffMs > 0;
            if (!blink) {
                on = true;
                mLed.set(color);
                mCond.wait(lock, [this] { return mChanged; });
                continue;
            }
            mLed.set(on ? color : 0);
            auto ms = std::chrono::milliseconds(on ? s.flashOnMs : s.flashOffMs);
            if (!mCond.wait_for(lock, ms, [this] { return mChanged; })) on = !on;
            else on = true;
        }
    }

    RgbLed mLed;
    std::vector<HwLight> mLights;
    std::vector<HwLightState> mStates;
    std::mutex mMutex;
    std::condition_variable mCond;
    bool mChanged = false;
    std::thread mThread;
};

}  // namespace aidl::android::hardware::light

int main() {
    ABinderProcess_setThreadPoolMaxThreadCount(0);
    auto lights = ndk::SharedRefBase::make<aidl::android::hardware::light::Lights>();
    const std::string name =
            std::string(aidl::android::hardware::light::Lights::descriptor) + "/default";
    CHECK_EQ(AServiceManager_addService(lights->asBinder().get(), name.c_str()), STATUS_OK);
    ABinderProcess_joinThreadPool();
    return EXIT_FAILURE;
}
