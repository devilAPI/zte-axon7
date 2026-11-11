# LineageOS 24 product for the ZTE Axon 7 on mainline Linux (codename axon7m,
# so it never collides with the 4.4-kernel "axon7" tree of LineageOS 22.2).
# Bring-up: debuggable userdebug, set before LineageOS's common.mk (patched in
# lineageos-24-mainline/aosp/vendor/lineage). Without it init is built without
# ALLOW_PERMISSIVE_SELINUX: androidboot.selinux=permissive was ignored and, in
# enforcing mode, ueventd could not set ro.cold_boot_done, so init waited
# forever (M1a run 4, 2026-11-11). adb authentication stays on.
LINEAGE_DEBUGGABLE_USERDEBUG := true

$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit_only.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base_telephony.mk)
# AXON7_MINI (default true): LineageOS's mini phone app set for bring-up
# (smaller out/ on the build host); AXON7_MINI=false for the full set
AXON7_MINI ?= true
ifeq ($(AXON7_MINI),true)
$(call inherit-product, vendor/lineage/config/common_mini_phone.mk)
else
$(call inherit-product, vendor/lineage/config/common_full_phone.mk)
endif
$(call inherit-product, device/zte/axon7m/device.mk)

PRODUCT_NAME := lineage_axon7m
PRODUCT_DEVICE := axon7m
PRODUCT_BRAND := ZTE
PRODUCT_MODEL := A2017G
PRODUCT_MANUFACTURER := ZTE
PRODUCT_GMS_CLIENTID_BASE := android-zte

