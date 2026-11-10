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

# Graphics, bring-up path: SwiftShader (Vulkan) + ANGLE (GLES) on the CPU,
# drm_hwcomposer on the msm DRM device, minigbm gralloc. Mesa freedreno
# replaces SwiftShader/ANGLE in milestone M1b.
PRODUCT_PACKAGES += \
    com.android.hardware.graphics.composer.drm_hwcomposer \
    android.hardware.graphics.allocator-service.minigbm \
    mapper.minigbm \
    libEGL_angle libGLESv1_CM_angle libGLESv2_angle \
    vulkan.pastel
$(call soong_config_set,minigbm,platform,msm)
PRODUCT_VENDOR_PROPERTIES += \
    ro.hardware.egl=angle \
    ro.hardware.vulkan=pastel \
    ro.hardware.gralloc=minigbm \
    ro.opengles.version=196608 \
    debug.hwui.renderer=skiagl
PRODUCT_REQUIRES_INSECURE_EXECMEM_FOR_SWIFTSHADER := true

# Init, fstab, ueventd
PRODUCT_COPY_FILES += \
    $(DEVICE_PATH)/init/fstab.axon7m:$(TARGET_COPY_OUT_RAMDISK)/fstab.axon7m \
    $(DEVICE_PATH)/init/fstab.axon7m:$(TARGET_COPY_OUT_VENDOR)/etc/fstab.axon7m \
    $(DEVICE_PATH)/init/init.axon7m.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/hw/init.axon7m.rc \
    $(DEVICE_PATH)/init/init.axon7m.usb.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/hw/init.axon7m.usb.rc \
    $(DEVICE_PATH)/init/init.recovery.axon7m.rc:$(TARGET_COPY_OUT_RECOVERY)/root/init.recovery.axon7m.rc \
    $(DEVICE_PATH)/init/ueventd.axon7m.rc:$(TARGET_COPY_OUT_VENDOR)/etc/ueventd.rc \
    $(DEVICE_PATH)/bin/axon7m-modules.sh:$(TARGET_COPY_OUT_VENDOR)/bin/axon7m-modules.sh

# Keep the system awake: suspend is broken on msm8996 mainline (PLAN.md)
PRODUCT_VENDOR_PROPERTIES += sys.autosuspend.disabled=true

# HALs that need no hardware work
PRODUCT_PACKAGES += \
    android.hardware.health-service.example \
    android.hardware.power-service.example \
    com.android.hardware.thermal \
    android.hardware.bluetooth-service.default \
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

# Developer builds
PRODUCT_SYSTEM_PROPERTIES += persist.sys.usb.config=adb
PRODUCT_VENDOR_PROPERTIES += ro.adb.secure=0
