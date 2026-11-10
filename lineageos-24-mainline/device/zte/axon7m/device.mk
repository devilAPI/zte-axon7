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

# Display: 1440x2560 at about 534 ppi
PRODUCT_AAPT_CONFIG := normal
PRODUCT_AAPT_PREF_CONFIG := 560dpi
PRODUCT_VENDOR_PROPERTIES += ro.sf.lcd_density=560

# Graphics: drm_hwcomposer on the msm DRM device and minigbm gralloc, then
#   AXON7_GPU=swiftshader (default, bring-up): SwiftShader Vulkan + ANGLE GLES
#     on the CPU, works without the GPU;
#   AXON7_GPU=mesa: Mesa freedreno on the Adreno 530 (GLES only: turnip has no
#     a5xx), prebuilts from scripts/mesa-build.sh in device/zte/axon7m-mesa.
AXON7_GPU ?= swiftshader
PRODUCT_PACKAGES += \
    com.android.hardware.graphics.composer.drm_hwcomposer \
    android.hardware.graphics.allocator-service.minigbm \
    mapper.minigbm
$(call soong_config_set,minigbm,platform,msm)
PRODUCT_VENDOR_PROPERTIES += \
    ro.hardware.gralloc=minigbm \
    ro.opengles.version=196609 \
    debug.hwui.renderer=skiagl
# GLES 3.1 (196609); no Android Extension Pack claim until Mesa's a5xx support
# is checked on the phone
ifeq ($(AXON7_GPU),mesa)
PRODUCT_SOONG_NAMESPACES += device/zte/axon7m-mesa
PRODUCT_PACKAGES += \
    libEGL_mesa.axon7m \
    libGLESv2_mesa.axon7m \
    libgallium_dri.axon7m
PRODUCT_VENDOR_PROPERTIES += ro.hardware.egl=mesa
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
    $(DEVICE_PATH)/bin/axon7m-bdaddr.sh:$(TARGET_COPY_OUT_VENDOR)/bin/axon7m-bdaddr.sh

# Keep the system awake: suspend is broken on msm8996 mainline (PLAN.md)
PRODUCT_VENDOR_PROPERTIES += sys.autosuspend.disabled=true

# HALs that need no hardware work
PRODUCT_PACKAGES += \
    android.hardware.health-service.example \
    android.hardware.power-service.example \
    com.android.hardware.thermal \
    android.hardware.bluetooth-service.default \
    bdaddr.axon7m \
    android.hardware.wifi-service \
    hostapd \
    wpa_supplicant

PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.wifi.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.wifi.xml \
    frameworks/native/data/etc/android.hardware.bluetooth.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.bluetooth.xml \
    frameworks/native/data/etc/android.hardware.bluetooth_le.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.bluetooth_le.xml \
    frameworks/native/data/etc/android.hardware.touchscreen.multitouch.jazzhand.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.touchscreen.multitouch.jazzhand.xml \
    frameworks/native/data/etc/android.hardware.usb.host.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.usb.host.xml

# Telephony is milestone M7: Wi-Fi-only until then
PRODUCT_VENDOR_PROPERTIES += ro.radio.noril=yes

# Developer builds: AXON7_ADB_KEYS=FILE (adb public key of the developer host,
# as in the LineageOS 22.2 axon7 tree) puts the key into system and recovery
# and starts adbd from the first boot. adb authentication stays on
# (ro.adb.secure=1; LineageOS userdebug builds are not debuggable either).
ifneq ($(AXON7_ADB_KEYS),)
PRODUCT_ADB_KEYS := $(AXON7_ADB_KEYS)
PRODUCT_SYSTEM_DEFAULT_PROPERTIES += persist.sys.usb.config=adb
endif
