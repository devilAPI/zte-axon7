#
# ZTE Axon 7 (A2017G, MSM8996) on mainline Linux 7.3: board configuration.
# See lineageos-24-mainline/PLAN.md in the zte-axon7 repository.
#
DEVICE_PATH := device/zte/axon7m

# Architecture: Kryo is ARMv8.0 (no LSE atomics); 64-bit only for now
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-a
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_VARIANT := kryo
TARGET_CPU_VARIANT_RUNTIME := kryo
TARGET_BOARD_PLATFORM := msm8996
TARGET_BOOTLOADER_BOARD_NAME := msm8996
TARGET_NO_BOOTLOADER := true

# Kernel: built outside the Android tree (scripts/kernel-build.sh) and staged
# as a prebuilt. Raw Image: the multi-boot shim does not decompress.
TARGET_KERNEL_DIR ?= device/zte/axon7m-kernel
TARGET_PREBUILT_KERNEL := $(TARGET_KERNEL_DIR)/Image
BOARD_PREBUILT_DTBIMAGE_DIR := $(TARGET_KERNEL_DIR)/dtb
BOARD_INCLUDE_DTB_IN_BOOTIMG := true
BOARD_KERNEL_IMAGE_NAME := Image
BOARD_BOOT_HEADER_VERSION := 2
BOARD_KERNEL_BASE := 0x80000000
BOARD_KERNEL_PAGESIZE := 4096
BOARD_KERNEL_OFFSET := 0x00008000
BOARD_RAMDISK_OFFSET := 0x01000000
BOARD_KERNEL_TAGS_OFFSET := 0x00000100
BOARD_DTB_OFFSET := 0x01f00000
BOARD_MKBOOTIMG_ARGS := --header_version $(BOARD_BOOT_HEADER_VERSION) \
    --kernel_offset $(BOARD_KERNEL_OFFSET) --ramdisk_offset $(BOARD_RAMDISK_OFFSET) \
    --tags_offset $(BOARD_KERNEL_TAGS_OFFSET) --dtb_offset $(BOARD_DTB_OFFSET)
BOARD_RAMDISK_USE_LZ4 := false

# The shim appends LK's own tokens (serial number, ...) after these.
BOARD_KERNEL_CMDLINE := androidboot.hardware=axon7m
BOARD_KERNEL_CMDLINE += androidboot.boot_devices=soc@0/624000.ufshc
# androidboot.super_partition=system is added by the build itself
# (BOARD_SUPER_PARTITION_BLOCK_DEVICES)
# bonded DSI needs DPU; keep the splash clocks until the panel driver takes over
BOARD_KERNEL_CMDLINE += msm.prefer_mdp5=0 clk_ignore_unused pd_ignore_unused
BOARD_KERNEL_CMDLINE += console=ttyMSM0,115200n8 loop.max_part=7
# bring-up: permissive SELinux, panic on oops so the test loop restarts
BOARD_KERNEL_CMDLINE += androidboot.selinux=permissive oops=panic panic=5
# bring-up: no rate limit on /dev/kmsg, so init/ueventd/apexd messages reach
# the pstore console (first M1a runs lost them: "output lines suppressed")
BOARD_KERNEL_CMDLINE += printk.devkmsg=on
# bring-up: a fatal init error (critical service crash loop) goes to recovery
# (TWRP, where the test loop collects the log) instead of a boot loop
BOARD_KERNEL_CMDLINE += androidboot.init_fatal_reboot_target=recovery

# Firmware from /vendor/firmware (device.mk, AXON7_FIRMWARE); the remoteproc
# .mbn images are ELF files, which PRODUCT_COPY_FILES refuses otherwise
BOARD_KERNEL_CMDLINE += firmware_class.path=/vendor/firmware
BUILD_BROKEN_ELF_PREBUILT_PRODUCT_COPY_FILES := true

# Kernel modules: everything goes to /vendor/lib/modules; init loads the list
# in modules.load (configs/modules.load.axon7m) after /vendor is mounted, so
# drivers that need firmware from /vendor find it.
BOARD_VENDOR_KERNEL_MODULES := $(wildcard $(TARGET_KERNEL_DIR)/modules/*.ko)
BOARD_VENDOR_KERNEL_MODULES_LOAD := $(strip $(shell cat $(DEVICE_PATH)/configs/modules.load.axon7m 2>/dev/null | grep -v '^\#'))

# Partitions: LineageOS 22.2's multi-boot slot, taken over for testing (user,
# 2026-11-10; PLAN.md section 5): boot image in los_boot (the shim's
# LineageOS entry), dynamic partitions on the GPT partition "system"
# (sde13, 5.5 GiB) as the super device (named by androidboot.super_partition,
# which the build adds), /metadata on los_metadata, /data on los_data.
# The 512 MiB "vendor" partition (sde28) is not used.
# Not A/B: one slot (los_boot), no _a/_b partitions in super. AOSP 17 turns
# AB_OTA_UPDATER on when it is left empty (build/make/core/board_config.mk),
# which named the super partitions system_a/system_b and allowed only half
# of super per slot.
AB_OTA_UPDATER := false
BOARD_FLASH_BLOCK_SIZE := 262144
BOARD_BOOTIMAGE_PARTITION_SIZE := 100663296
BOARD_RECOVERYIMAGE_PARTITION_SIZE := 100663296
BOARD_USES_METADATA_PARTITION := true
BOARD_SUPER_PARTITION_SIZE := 5905580032
BOARD_SUPER_PARTITION_BLOCK_DEVICES := system
BOARD_SUPER_PARTITION_SYSTEM_DEVICE_SIZE := $(BOARD_SUPER_PARTITION_SIZE)
BOARD_SUPER_PARTITION_METADATA_DEVICE := system
BOARD_SUPER_PARTITION_GROUPS := axon7m_dynamic_partitions
# super minus 4 MiB for the LP metadata
BOARD_AXON7M_DYNAMIC_PARTITIONS_SIZE := 5901385728
BOARD_AXON7M_DYNAMIC_PARTITIONS_PARTITION_LIST := system system_ext product vendor
BOARD_BUILD_SUPER_IMAGE_BY_DEFAULT := true

BOARD_SYSTEMIMAGE_FILE_SYSTEM_TYPE := erofs
BOARD_SYSTEM_EXTIMAGE_FILE_SYSTEM_TYPE := erofs
BOARD_PRODUCTIMAGE_FILE_SYSTEM_TYPE := erofs
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := erofs
BOARD_USERDATAIMAGE_FILE_SYSTEM_TYPE := f2fs
# userdata.img is never flashed (los_data is formatted on the phone)
BOARD_USERDATAIMAGE_PARTITION_SIZE := 10737418240
TARGET_USERIMAGES_USE_F2FS := true
TARGET_USERIMAGES_USE_EXT4 := true
TARGET_COPY_OUT_VENDOR := vendor
TARGET_COPY_OUT_SYSTEM_EXT := system_ext
TARGET_COPY_OUT_PRODUCT := product

# No verified boot: LK does not check our partitions
BOARD_AVB_ENABLE := false

# Recovery (also the M0 test image: kernel + first stage + adbd, no system)
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/init/fstab.axon7m
TARGET_RECOVERY_PIXEL_FORMAT := RGBX_8888

DEVICE_MANIFEST_FILE := $(DEVICE_PATH)/manifest.xml

# Wi-Fi: ath10k through cfg80211/nl80211. Legacy Wi-Fi HAL: the generic
# nl80211 one from goldfish (libwifi-hal-emu, wlan0/wlan1); without one the
# AIDL Wi-Fi service fails ("Can not initialize the vendor function pointer
# table", M1a run 17).
BOARD_WLAN_DEVICE := emulator
WPA_SUPPLICANT_VERSION := VER_0_8_X
BOARD_WPA_SUPPLICANT_DRIVER := NL80211
BOARD_HOSTAPD_DRIVER := NL80211

# Bluetooth: HCI user channel (AOSP default AIDL HAL)
BOARD_HAVE_BLUETOOTH := true

# SELinux
BOARD_VENDOR_SEPOLICY_DIRS += $(DEVICE_PATH)/sepolicy/vendor

# Development builds: faster, smaller out/
WITH_DEXPREOPT ?= false
