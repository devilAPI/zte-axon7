# LineageOS 24 product for the ZTE Axon 7 on mainline Linux (codename axon7m,
# so it never collides with the 4.4-kernel "axon7" tree of LineageOS 22.2).
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit_only.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base_telephony.mk)
$(call inherit-product, vendor/lineage/config/common_full_phone.mk)
$(call inherit-product, device/zte/axon7m/device.mk)

PRODUCT_NAME := lineage_axon7m
PRODUCT_DEVICE := axon7m
PRODUCT_BRAND := ZTE
PRODUCT_MODEL := A2017G
PRODUCT_MANUFACTURER := ZTE
PRODUCT_GMS_CLIENTID_BASE := android-zte
