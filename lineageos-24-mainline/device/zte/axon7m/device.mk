#
# ZTE Axon 7 on mainline Linux: product packages and files (M0/M1 scope).
#
DEVICE_PATH := device/zte/axon7m

PRODUCT_SHIPPING_API_LEVEL := 34
PRODUCT_FULL_TREBLE_OVERRIDE := true
PRODUCT_USE_DYNAMIC_PARTITIONS := true
PRODUCT_BUILD_SUPER_PARTITION := true

PRODUCT_SOONG_NAMESPACES += $(DEVICE_PATH)

# The kernel is 7.3, newer than any <kernel> entry of the framework
# compatibility matrices: don't check kernel version/configs at build/OTA time.
PRODUCT_OTA_ENFORCE_VINTF_KERNEL_REQUIREMENTS := false

# Shared memory: no ashmem in mainline, use memfd (libcutils ashmem-dev.cpp)
PRODUCT_SYSTEM_PROPERTIES += sys.use_memfd=true

# Dalvik heap for 4 GB RAM: without it every Java process got the 16 MB
# default heap, and system_server and SystemUI died with OutOfMemoryError
# (M1a run 13)
$(call inherit-product, frameworks/native/build/phone-xhdpi-4096-dalvik-heap.mk)

# Bluetooth (QCA6174 over UART, no rampatch yet): the stack's Qualcomm vendor
# LE commands (LE_ADV_FILTER 0xfd57) get "unknown opcode" and the stack
# aborts in a loop (M1a run 13); plain Bluetooth LE without them
PRODUCT_VENDOR_PROPERTIES += bluetooth.core.le.vendor_capabilities.enabled=false

# Display: 1440x2560 at about 534 ppi
PRODUCT_AAPT_CONFIG := normal
PRODUCT_AAPT_PREF_CONFIG := 560dpi
PRODUCT_VENDOR_PROPERTIES += ro.sf.lcd_density=560

# Codec2: use the AIDL software store. With the HIDL default (no
# hwservicemanager here) media.swcodec registered an empty store and
# MediaCodecList had only AAC: Vorbis ringtones/alarms failed ("Failed to
# create audio/vorbis decoder"), no sound. As cuttlefish.
PRODUCT_VENDOR_PROPERTIES += media.c2.hal.selection?=aidl

# APSS watchdog daemon (init.axon7m.rc)
PRODUCT_PACKAGES += watchdogd

# Modem bring-up (qcom/README.md): rmtfs (read-only), QRTR tools, online switch
PRODUCT_PACKAGES += rmtfs libqrtr qrtr-lookup axon7m-modem-online

# Graphics: drm_hwcomposer on the msm DRM device and minigbm gralloc, then
#   AXON7_GPU=swiftshader (bring-up fallback): SwiftShader Vulkan + ANGLE GLES
#     on the CPU, works without the GPU;
#   AXON7_GPU=mesa (default since M1a run 19): Mesa freedreno on the Adreno 530 (GLES only: turnip has no
#     a5xx), prebuilts from scripts/mesa-build.sh in device/zte/axon7m-mesa.
AXON7_GPU ?= mesa
PRODUCT_PACKAGES += \
    com.android.hardware.graphics.composer.drm_hwcomposer \
    android.hardware.graphics.allocator-service.minigbm \
    mapper.minigbm
$(call soong_config_set,minigbm,platform,msm)
PRODUCT_VENDOR_PROPERTIES += \
    ro.hardware.gralloc=minigbm \
    ro.opengles.version=196609 \
    debug.hwui.renderer=skiagl \
    vendor.minigbm.debug=nocompression
# nocompression (linear buffers only), for both GPU choices: minigbm's msm
# backend gives render targets UBWC (Qualcomm compressed) layout.
# - SwiftShader: msm_bo_map() refuses to map UBWC, SurfaceFlinger aborted
#   ("Failed to create a valid texture", M1a run 8).
# - Mesa: freedreno renders UBWC, but mainline MDP5 (MSM8996) scans planes
#   out as linear only, so the panel showed garbage (M1a run 16).
# GLES 3.1 (196609); no Android Extension Pack claim until Mesa's a5xx support
# is checked on the phone
ifeq ($(AXON7_GPU),mesa)
PRODUCT_SOONG_NAMESPACES += device/zte/axon7m-mesa
PRODUCT_PACKAGES += \
    libEGL_mesa.axon7m \
    libGLESv2_mesa.axon7m \
    libgallium_dri.axon7m
PRODUCT_VENDOR_PROPERTIES += \
    ro.hardware.egl=mesa \
    debug.renderengine.backend=skiagl
# skiagl: SurfaceFlinger's default threaded Skia RenderEngine on freedreno
# composed black (first boot) or striped garbage (after a restart) whenever
# the GPU composed (client composition, screencap); the plain one is
# correct (M1a run 18h, checked by dumping the scanned-out DRM planes).
else
PRODUCT_PACKAGES += \
    libEGL_angle libGLESv1_CM_angle libGLESv2_angle \
    vulkan.pastel
PRODUCT_VENDOR_PROPERTIES += \
    ro.hardware.egl=angle \
    ro.hardware.vulkan=pastel
PRODUCT_REQUIRES_INSECURE_EXECMEM_FOR_SWIFTSHADER := true
endif

# Init, fstab, ueventd
PRODUCT_COPY_FILES += \
    $(DEVICE_PATH)/init/fstab.axon7m:$(TARGET_COPY_OUT_RAMDISK)/fstab.axon7m \
    $(DEVICE_PATH)/init/fstab.axon7m:$(TARGET_COPY_OUT_VENDOR)/etc/fstab.axon7m \
    $(DEVICE_PATH)/init/init.axon7m.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/hw/init.axon7m.rc \
    $(DEVICE_PATH)/init/init.axon7m.usb.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/hw/init.axon7m.usb.rc \
    $(DEVICE_PATH)/init/init.recovery.axon7m.rc:$(TARGET_COPY_OUT_RECOVERY)/root/init.recovery.axon7m.rc \
    $(DEVICE_PATH)/init/ueventd.axon7m.rc:$(TARGET_COPY_OUT_VENDOR)/etc/ueventd.rc \
    $(DEVICE_PATH)/bin/axon7m-modules.sh:$(TARGET_COPY_OUT_VENDOR)/bin/axon7m-modules.sh \
    $(DEVICE_PATH)/bin/axon7m-bootguard.sh:$(TARGET_COPY_OUT_VENDOR)/bin/axon7m-bootguard.sh \
    $(DEVICE_PATH)/bin/axon7m-bdaddr.sh:$(TARGET_COPY_OUT_VENDOR)/bin/axon7m-bdaddr.sh \
    $(DEVICE_PATH)/bin/axon7m-audio-routes.sh:$(TARGET_COPY_OUT_VENDOR)/bin/axon7m-audio-routes.sh \
    $(DEVICE_PATH)/bin/axon7m-sns-reg.sh:$(TARGET_COPY_OUT_VENDOR)/bin/axon7m-sns-reg.sh \
    $(DEVICE_PATH)/bin/axon7m-slpi-kick.sh:$(TARGET_COPY_OUT_VENDOR)/bin/axon7m-slpi-kick.sh
# q6asm takes period sizes in steps of 480 frames only (capture periods up to
# 4096 bytes): with aosp/hardware/interfaces 0001 the AIDL HAL rounds its PCM
# buffers to 4 periods of 480-frame steps (85 ms at 48 kHz -> 3840 frames,
# periods of 960). Without it: "cannot set hw params" (M1a run 22h).
PRODUCT_VENDOR_PROPERTIES += ro.vendor.audio.tinyalsa.period_step_frames=480
# mixer routes per device (hardware/interfaces patch 0002); wired devices
# play on MultiMedia2 and record on MultiMedia1 like the built-in ones
PRODUCT_VENDOR_PROPERTIES += \
    ro.vendor.audio.tinyalsa.routes=/vendor/etc/audio_routes.conf \
    ro.vendor.audio.tinyalsa.default_out_address=CARD_0_DEV_1 \
    ro.vendor.audio.tinyalsa.default_in_address=CARD_0_DEV_0
PRODUCT_PACKAGES += FrameworksResAxon7m
# tinymix for the mixer routes (vendor variant of external/tinyalsa)
PRODUCT_PACKAGES += tinymix.vendor tinycap.vendor
# AXON7_SPEAKER_MUTE=1: speaker switches stay off (unattended test boots in
# the owner's quiet hours; routes and the mic are still set)
AXON7_SPEAKER_MUTE ?= 0
ifeq ($(AXON7_SPEAKER_MUTE),1)
PRODUCT_VENDOR_PROPERTIES += ro.vendor.axon7m.speaker_mute=1
PRODUCT_COPY_FILES += $(DEVICE_PATH)/audio/audio_routes_muted.conf:$(TARGET_COPY_OUT_VENDOR)/etc/audio_routes.conf
else
PRODUCT_COPY_FILES += $(DEVICE_PATH)/audio/audio_routes.conf:$(TARGET_COPY_OUT_VENDOR)/etc/audio_routes.conf
endif

# Keep the system awake: suspend is broken on msm8996 mainline (PLAN.md)
PRODUCT_VENDOR_PROPERTIES += sys.autosuspend.disabled=true

# HALs that need no hardware work
PRODUCT_PACKAGES += \
    android.hardware.health-service.example \
    android.hardware.power-service.example \
    com.android.hardware.thermal \
    android.hardware.bluetooth-service.default \
    bdaddr.axon7m \
    android.hardware.vibrator-service.axon7m \
    android.hardware.wifi-service \
    hostapd \
    wpa_supplicant

PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.wifi.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.wifi.xml \
    $(DEVICE_PATH)/wifi/wpa_supplicant.conf:$(TARGET_COPY_OUT_VENDOR)/etc/wifi/wpa_supplicant.conf \
    $(DEVICE_PATH)/wifi/wpa_supplicant_overlay.conf:$(TARGET_COPY_OUT_VENDOR)/etc/wifi/wpa_supplicant_overlay.conf \
    frameworks/native/data/etc/android.hardware.bluetooth.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.bluetooth.xml \
    frameworks/native/data/etc/android.hardware.bluetooth_le.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.bluetooth_le.xml \
    frameworks/native/data/etc/android.hardware.touchscreen.multitouch.jazzhand.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.touchscreen.multitouch.jazzhand.xml \
    frameworks/native/data/etc/android.hardware.usb.host.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.usb.host.xml

# Telephony is milestone M7: Wi-Fi-only until then
PRODUCT_VENDOR_PROPERTIES += ro.radio.noril=yes

# Developer builds: AXON7_ADB_KEYS=FILE (adb public key of the developer host,
# as in the LineageOS 22.2 axon7 tree) puts the key into system and recovery
# and starts adbd from the first boot. adb authentication stays on
# (ro.adb.secure=1).
ifneq ($(AXON7_ADB_KEYS),)
PRODUCT_ADB_KEYS := $(AXON7_ADB_KEYS)
PRODUCT_SYSTEM_DEFAULT_PROPERTIES += persist.sys.usb.config=adb
# adbd as root from the start (ro.debuggable=1 via LINEAGE_DEBUGGABLE_USERDEBUG):
# LineageOS gates `adb root` behind a Developer options switch kept in /data,
# which unattended test boots cannot flip (M1a run 16).
PRODUCT_SYSTEM_DEFAULT_PROPERTIES += service.adb.root=1
endif

# KeyMint: keystore2 is a critical service and aborts without a TEE KeyMint
# (M1a run 7: init rebooted after 4 crashes). ZTE's keymaster runs in QSEE
# (milestone M8 at the earliest); for bring-up AOSP's software KeyMint, which
# is not secure (keys live in normal-world memory).
PRODUCT_PACKAGES += \
    android.hardware.security.keymint-service \
    android.hardware.hardware_keystore.xml

# Firmware (M2): /vendor/firmware from vendor/zte/axon7m-firmware in the
# Android tree on the build server (scripts/firmware-from-nura.sh: the
# phone's ZTE/Qualcomm images + linux-firmware files; proprietary, never in
# git). The kernel looks there (firmware_class.path in BoardConfig.mk).
# AXON7_FIRMWARE=1 (los24-build.sh default since build 15: LineageOS reached the
# setup wizard without firmware first; AXON7_FIRMWARE=0 builds without).
AXON7_FIRMWARE ?= 0
AXON7M_FW_DIR := vendor/zte/axon7m-firmware
ifeq ($(AXON7_FIRMWARE),1)
PRODUCT_COPY_FILES += $(foreach f,$(shell cd $(AXON7M_FW_DIR) 2>/dev/null && find . -type f | sed 's|^\./||' | sort),\
    $(AXON7M_FW_DIR)/$(f):$(TARGET_COPY_OUT_VENDOR)/firmware/$(f))
endif

# Audio: audioserver crashes without any audio HAL, and system_server then
# blocks on AudioSystem until its watchdog kills it (M1a run 9). For bring-up
# AOSP's example AIDL audio HAL + effects (APEX); the audio policy comes from
# the HAL. No real output yet: the sound card needs the ADSP (milestone M3).
PRODUCT_PACKAGES += com.android.hardware.audio
# the effects HAL exits without its config, and its onrestart restarts
# audioserver every time (M1a run 10)
PRODUCT_COPY_FILES += \
    hardware/interfaces/audio/aidl/default/audio_effects_config.xml:$(TARGET_COPY_OUT_VENDOR)/etc/audio_effects_config.xml
# the example HAL creates its modules (IModule/default, r_submix) from the
# audio policy configuration; without it audioserver waited forever for
# IModule/default and system_server's watchdog fired (M1a run 11)
PRODUCT_COPY_FILES += \
    $(DEVICE_PATH)/audio/audio_policy_configuration.xml:$(TARGET_COPY_OUT_VENDOR)/etc/audio_policy_configuration.xml \
    $(DEVICE_PATH)/audio/primary_audio_policy_configuration.xml:$(TARGET_COPY_OUT_VENDOR)/etc/primary_audio_policy_configuration.xml \
    frameworks/av/services/audiopolicy/config/r_submix_audio_policy_configuration.xml:$(TARGET_COPY_OUT_VENDOR)/etc/r_submix_audio_policy_configuration.xml \
    frameworks/av/services/audiopolicy/config/bluetooth_with_le_audio_policy_configuration_7_0.xml:$(TARGET_COPY_OUT_VENDOR)/etc/bluetooth_with_le_audio_policy_configuration_7_0.xml \
    frameworks/av/services/audiopolicy/config/audio_policy_volumes.xml:$(TARGET_COPY_OUT_VENDOR)/etc/audio_policy_volumes.xml \
    frameworks/av/services/audiopolicy/config/default_volume_tables.xml:$(TARGET_COPY_OUT_VENDOR)/etc/default_volume_tables.xml

# Sensors (SLPI Sensor Manager through the kernel's qcom-smgr IIO drivers):
# sns-reg registry server, AIDL sensors HAL on IIO (sensors/)
PRODUCT_PACKAGES += \
    android.hardware.sensors-service.axon7m \
    sns-reg \
    sns-reg-generator
PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.sensor.accelerometer.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.sensor.accelerometer.xml \
    frameworks/native/data/etc/android.hardware.sensor.gyroscope.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.sensor.gyroscope.xml \
    frameworks/native/data/etc/android.hardware.sensor.compass.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.sensor.compass.xml \
    frameworks/native/data/etc/android.hardware.sensor.light.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.sensor.light.xml \
    frameworks/native/data/etc/android.hardware.sensor.proximity.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.sensor.proximity.xml
