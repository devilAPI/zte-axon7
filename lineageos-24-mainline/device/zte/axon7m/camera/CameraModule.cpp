/*
 * camera.axon7m: camera HAL module (CAMERA_MODULE_API 2.4) with one back
 * camera that has a flash unit and can only be used as a torch.
 *
 * The Quick Settings flashlight and every other torch user go through the
 * camera service (CameraManager.setTorchMode), which needs a camera device
 * with ANDROID_FLASH_INFO_AVAILABLE. Mainline drives the S5K2T8 and OV8856
 * sensors through CAMSS, but nothing turns their Bayer frames into YUV yet,
 * so opening the camera fails with -ENODEV (camera apps report that the
 * camera cannot be opened) while setTorchMode() switches the PMI8994 flash
 * LED (/sys/class/leds/white:torch) on and off.
 *
 * The static metadata describes the rear camera as a LEGACY device with a
 * few YUV/JPEG sizes, enough for the camera service to accept it.
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#define LOG_TAG "camera.axon7m"

#include <android-base/file.h>
#include <hardware/camera3.h>
#include <hardware/camera_common.h>
#include <hardware/hardware.h>
#include <log/log.h>
#include <system/camera_metadata.h>
#include <system/graphics-base.h>

#include <cerrno>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

namespace {

const char kTorch[] = "/sys/class/leds/white:torch/";

std::mutex gLock;
const camera_module_callbacks_t* gCallbacks = nullptr;
camera_metadata_t* gStatic = nullptr;
bool gTorchOn = false;

template <typename T>
void add(camera_metadata_t* m, uint32_t tag, const std::vector<T>& v) {
    if (add_camera_metadata_entry(m, tag, v.data(), v.size()))
        ALOGE("metadata tag 0x%x not added", tag);
}

camera_metadata_t* buildStatic() {
    camera_metadata_t* m = allocate_camera_metadata(96, 4096);
    const int32_t W = 5952, H = 3348;  // S5K2T8 full size
    add<uint8_t>(m, ANDROID_INFO_SUPPORTED_HARDWARE_LEVEL,
                 {ANDROID_INFO_SUPPORTED_HARDWARE_LEVEL_LEGACY});
    add<uint8_t>(m, ANDROID_REQUEST_AVAILABLE_CAPABILITIES,
                 {ANDROID_REQUEST_AVAILABLE_CAPABILITIES_BACKWARD_COMPATIBLE});
    add<uint8_t>(m, ANDROID_LENS_FACING, {ANDROID_LENS_FACING_BACK});
    add<int32_t>(m, ANDROID_SENSOR_ORIENTATION, {90});
    add<uint8_t>(m, ANDROID_FLASH_INFO_AVAILABLE, {ANDROID_FLASH_INFO_AVAILABLE_TRUE});
    add<int32_t>(m, ANDROID_SENSOR_INFO_ACTIVE_ARRAY_SIZE, {0, 0, W, H});
    add<int32_t>(m, ANDROID_SENSOR_INFO_PRE_CORRECTION_ACTIVE_ARRAY_SIZE, {0, 0, W, H});
    add<int32_t>(m, ANDROID_SENSOR_INFO_PIXEL_ARRAY_SIZE, {W, H});
    add<float>(m, ANDROID_SENSOR_INFO_PHYSICAL_SIZE, {6.67f, 3.75f});
    add<uint8_t>(m, ANDROID_SENSOR_INFO_TIMESTAMP_SOURCE,
                 {ANDROID_SENSOR_INFO_TIMESTAMP_SOURCE_UNKNOWN});
    add<float>(m, ANDROID_LENS_INFO_AVAILABLE_FOCAL_LENGTHS, {4.4f});
    add<float>(m, ANDROID_LENS_INFO_AVAILABLE_APERTURES, {1.8f});
    add<float>(m, ANDROID_LENS_INFO_MINIMUM_FOCUS_DISTANCE, {0.0f});
    add<uint8_t>(m, ANDROID_LENS_INFO_FOCUS_DISTANCE_CALIBRATION,
                 {ANDROID_LENS_INFO_FOCUS_DISTANCE_CALIBRATION_UNCALIBRATED});

    const int32_t sizes[][2] = {{1920, 1080}, {1280, 720}, {640, 480}};
    const int32_t fmts[] = {HAL_PIXEL_FORMAT_IMPLEMENTATION_DEFINED, HAL_PIXEL_FORMAT_YCBCR_420_888,
                            HAL_PIXEL_FORMAT_BLOB};
    std::vector<int32_t> cfg;
    std::vector<int64_t> dur, stall;
    for (int32_t f : fmts)
        for (auto& s : sizes) {
            cfg.insert(cfg.end(), {f, s[0], s[1],
                                   ANDROID_SCALER_AVAILABLE_STREAM_CONFIGURATIONS_OUTPUT});
            dur.insert(dur.end(), {f, s[0], s[1], 33333333});
            stall.insert(stall.end(), {f, s[0], s[1], f == HAL_PIXEL_FORMAT_BLOB ? 33333333 : 0});
        }
    add(m, ANDROID_SCALER_AVAILABLE_STREAM_CONFIGURATIONS, cfg);
    add(m, ANDROID_SCALER_AVAILABLE_MIN_FRAME_DURATIONS, dur);
    add(m, ANDROID_SCALER_AVAILABLE_STALL_DURATIONS, stall);
    add<float>(m, ANDROID_SCALER_AVAILABLE_MAX_DIGITAL_ZOOM, {1.0f});
    add<uint8_t>(m, ANDROID_SCALER_CROPPING_TYPE, {ANDROID_SCALER_CROPPING_TYPE_CENTER_ONLY});
    add<int32_t>(m, ANDROID_JPEG_MAX_SIZE, {1920 * 1080 * 3 / 2});
    add<int32_t>(m, ANDROID_JPEG_AVAILABLE_THUMBNAIL_SIZES, {0, 0, 160, 120});
    add<int64_t>(m, ANDROID_SENSOR_INFO_MAX_FRAME_DURATION, {66666666});
    add<int64_t>(m, ANDROID_SENSOR_INFO_EXPOSURE_TIME_RANGE, {100000, 66666666});
    add<int32_t>(m, ANDROID_SENSOR_INFO_SENSITIVITY_RANGE, {100, 1600});
    add<uint8_t>(m, ANDROID_SENSOR_INFO_COLOR_FILTER_ARRANGEMENT,
                 {ANDROID_SENSOR_INFO_COLOR_FILTER_ARRANGEMENT_GRBG});
    add<int32_t>(m, ANDROID_SENSOR_INFO_WHITE_LEVEL, {1023});

    add<int32_t>(m, ANDROID_REQUEST_PARTIAL_RESULT_COUNT, {1});
    add<uint8_t>(m, ANDROID_REQUEST_PIPELINE_MAX_DEPTH, {4});
    add<int32_t>(m, ANDROID_REQUEST_MAX_NUM_OUTPUT_STREAMS, {0, 2, 1});
    add<int32_t>(m, ANDROID_REQUEST_MAX_NUM_INPUT_STREAMS, {0});
    add<int32_t>(m, ANDROID_SYNC_MAX_LATENCY, {ANDROID_SYNC_MAX_LATENCY_UNKNOWN});

    add<int32_t>(m, ANDROID_CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES, {15, 30, 30, 30});
    add<uint8_t>(m, ANDROID_CONTROL_AVAILABLE_MODES, {ANDROID_CONTROL_MODE_AUTO});
    add<uint8_t>(m, ANDROID_CONTROL_AE_AVAILABLE_MODES,
                 {ANDROID_CONTROL_AE_MODE_ON, ANDROID_CONTROL_AE_MODE_ON_AUTO_FLASH,
                  ANDROID_CONTROL_AE_MODE_ON_ALWAYS_FLASH});
    add<uint8_t>(m, ANDROID_CONTROL_AE_AVAILABLE_ANTIBANDING_MODES,
                 {ANDROID_CONTROL_AE_ANTIBANDING_MODE_AUTO});
    add<int32_t>(m, ANDROID_CONTROL_AE_COMPENSATION_RANGE, {0, 0});
    add<camera_metadata_rational_t>(m, ANDROID_CONTROL_AE_COMPENSATION_STEP, {{1, 1}});
    add<uint8_t>(m, ANDROID_CONTROL_AE_LOCK_AVAILABLE, {ANDROID_CONTROL_AE_LOCK_AVAILABLE_FALSE});
    add<uint8_t>(m, ANDROID_CONTROL_AF_AVAILABLE_MODES, {ANDROID_CONTROL_AF_MODE_OFF});
    add<uint8_t>(m, ANDROID_CONTROL_AWB_AVAILABLE_MODES, {ANDROID_CONTROL_AWB_MODE_AUTO});
    add<uint8_t>(m, ANDROID_CONTROL_AWB_LOCK_AVAILABLE,
                 {ANDROID_CONTROL_AWB_LOCK_AVAILABLE_FALSE});
    add<uint8_t>(m, ANDROID_CONTROL_AVAILABLE_EFFECTS, {ANDROID_CONTROL_EFFECT_MODE_OFF});
    add<uint8_t>(m, ANDROID_CONTROL_AVAILABLE_SCENE_MODES, {ANDROID_CONTROL_SCENE_MODE_DISABLED});
    add<uint8_t>(m, ANDROID_CONTROL_AVAILABLE_VIDEO_STABILIZATION_MODES,
                 {ANDROID_CONTROL_VIDEO_STABILIZATION_MODE_OFF});
    add<int32_t>(m, ANDROID_CONTROL_MAX_REGIONS, {0, 0, 0});
    add<uint8_t>(m, ANDROID_STATISTICS_INFO_AVAILABLE_FACE_DETECT_MODES,
                 {ANDROID_STATISTICS_FACE_DETECT_MODE_OFF});
    add<int32_t>(m, ANDROID_STATISTICS_INFO_MAX_FACE_COUNT, {0});
    add<uint8_t>(m, ANDROID_EDGE_AVAILABLE_EDGE_MODES, {ANDROID_EDGE_MODE_OFF});
    add<uint8_t>(m, ANDROID_NOISE_REDUCTION_AVAILABLE_NOISE_REDUCTION_MODES,
                 {ANDROID_NOISE_REDUCTION_MODE_OFF});
    add<uint8_t>(m, ANDROID_COLOR_CORRECTION_AVAILABLE_ABERRATION_MODES,
                 {ANDROID_COLOR_CORRECTION_ABERRATION_MODE_OFF});
    add<uint8_t>(m, ANDROID_HOT_PIXEL_AVAILABLE_HOT_PIXEL_MODES, {ANDROID_HOT_PIXEL_MODE_OFF});
    add<uint8_t>(m, ANDROID_SHADING_AVAILABLE_MODES, {ANDROID_SHADING_MODE_OFF});
    add<uint8_t>(m, ANDROID_TONEMAP_AVAILABLE_TONE_MAP_MODES, {ANDROID_TONEMAP_MODE_FAST});
    add<int32_t>(m, ANDROID_TONEMAP_MAX_CURVE_POINTS, {64});
    add<uint8_t>(m, ANDROID_LENS_INFO_AVAILABLE_OPTICAL_STABILIZATION,
                 {ANDROID_LENS_OPTICAL_STABILIZATION_MODE_OFF});

    add<int32_t>(m, ANDROID_REQUEST_AVAILABLE_REQUEST_KEYS,
                 {ANDROID_CONTROL_AE_MODE, ANDROID_CONTROL_AF_MODE, ANDROID_CONTROL_AWB_MODE,
                  ANDROID_CONTROL_MODE, ANDROID_CONTROL_CAPTURE_INTENT, ANDROID_FLASH_MODE,
                  ANDROID_JPEG_ORIENTATION, ANDROID_JPEG_QUALITY, ANDROID_SCALER_CROP_REGION,
                  ANDROID_CONTROL_AE_TARGET_FPS_RANGE, ANDROID_CONTROL_AE_ANTIBANDING_MODE,
                  ANDROID_CONTROL_AE_PRECAPTURE_TRIGGER, ANDROID_CONTROL_AF_TRIGGER});
    add<int32_t>(m, ANDROID_REQUEST_AVAILABLE_RESULT_KEYS,
                 {ANDROID_CONTROL_AE_MODE, ANDROID_CONTROL_AF_MODE, ANDROID_CONTROL_AWB_MODE,
                  ANDROID_CONTROL_AE_STATE, ANDROID_CONTROL_AF_STATE, ANDROID_CONTROL_AWB_STATE,
                  ANDROID_FLASH_MODE, ANDROID_FLASH_STATE, ANDROID_SENSOR_TIMESTAMP,
                  ANDROID_SCALER_CROP_REGION, ANDROID_JPEG_ORIENTATION});
    std::vector<int32_t> keys;
    for (size_t i = 0; i < get_camera_metadata_entry_count(m); i++) {
        camera_metadata_ro_entry_t e;
        if (!get_camera_metadata_ro_entry(m, i, &e)) keys.push_back(e.tag);
    }
    keys.push_back(ANDROID_REQUEST_AVAILABLE_CHARACTERISTICS_KEYS);
    add(m, ANDROID_REQUEST_AVAILABLE_CHARACTERISTICS_KEYS, keys);
    return m;
}

int torchMax() {
    std::string s;
    if (!android::base::ReadFileToString(std::string(kTorch) + "max_brightness", &s)) return -1;
    return atoi(s.c_str());
}

int getNumberOfCameras() {
    return torchMax() > 0 ? 1 : 0;
}

int getCameraInfo(int id, struct camera_info* info) {
    if (id != 0 || !info) return -EINVAL;
    std::lock_guard l(gLock);
    if (!gStatic) gStatic = buildStatic();
    memset(info, 0, sizeof(*info));
    info->facing = CAMERA_FACING_BACK;
    info->orientation = 90;
    info->device_version = CAMERA_DEVICE_API_VERSION_3_5;
    info->static_camera_characteristics = gStatic;
    info->resource_cost = 100;
    info->conflicting_devices = nullptr;
    info->conflicting_devices_length = 0;
    return 0;
}

int setCallbacks(const camera_module_callbacks_t* callbacks) {
    std::lock_guard l(gLock);
    gCallbacks = callbacks;
    return 0;
}

int setTorchMode(const char* cameraId, bool enabled) {
    if (!cameraId || strcmp(cameraId, "0")) return -EINVAL;
    int max = torchMax();
    if (max <= 0) return -ENOSYS;
    const camera_module_callbacks_t* cb;
    {
        std::lock_guard l(gLock);
        // full torch level: the LED driver's max_brightness is the torch
        // current limit from the device tree
        if (!android::base::WriteStringToFile(std::to_string(enabled ? max : 0),
                                              std::string(kTorch) + "brightness")) {
            ALOGE("torch %s: %s", enabled ? "on" : "off", strerror(errno));
            return -EIO;
        }
        gTorchOn = enabled;
        cb = gCallbacks;
    }
    ALOGI("torch %s", enabled ? "on" : "off");
    if (cb && cb->torch_mode_status_change)
        cb->torch_mode_status_change(cb, "0",
                                     enabled ? TORCH_MODE_STATUS_AVAILABLE_ON
                                             : TORCH_MODE_STATUS_AVAILABLE_OFF);
    return 0;
}

int init() {
    return 0;
}

int openDevice(const hw_module_t*, const char* id, hw_device_t**) {
    ALOGW("camera %s: no image pipeline on mainline yet, torch only", id ? id : "?");
    return -ENODEV;
}

hw_module_methods_t gMethods = {.open = openDevice};

}  // namespace

extern "C" {
__attribute__((visibility("default"))) camera_module_t HAL_MODULE_INFO_SYM = {
        .common =
                {
                        .tag = HARDWARE_MODULE_TAG,
                        .module_api_version = CAMERA_MODULE_API_VERSION_2_4,
                        .hal_api_version = HARDWARE_HAL_API_VERSION,
                        .id = CAMERA_HARDWARE_MODULE_ID,
                        .name = "Axon 7 mainline camera (torch only)",
                        .author = "axon7m",
                        .methods = &gMethods,
                        .dso = nullptr,
                        .reserved = {},
                },
        .get_number_of_cameras = getNumberOfCameras,
        .get_camera_info = getCameraInfo,
        .set_callbacks = setCallbacks,
        .get_vendor_tag_ops = nullptr,
        .open_legacy = nullptr,
        .set_torch_mode = setTorchMode,
        .init = init,
        .get_physical_camera_info = nullptr,
        .is_stream_combination_supported = nullptr,
        .notify_device_state_change = nullptr,
        .reserved = {},
};
}
