# Patches to the LineageOS 22.2 tree (outside the device tree)

Apply with `git am` in the named project of a `lineage-22.2` checkout.

| Patch | Project | Why |
| --- | --- | --- |
| `system_libhidl-0001-old-constructor-maps.patch` | `system/libhidl` | HIDL code built before Android 10 (the Qualcomm RIL hooks, IMS, gnss, atcmdfwd blobs) registers its Bn/Bs constructors in `gBnConstructorMap`/`gBsConstructorMap`, which Android 13 removed: export them again and fall back to them, as Android 12 did. Without it the blobs abort in `getOrCreateCachedBinder`. |
| `system_core-0001-libutils-vendor-refbase-stack.patch` | `system/core` | `pm-service` (Android 8 blob, powers the modem) keeps a RefBase object on `main()`'s stack; the vendor variant of libutils warns instead of aborting. |
| `frameworks_av-0001-img_utils-vendor-available.patch` | `frameworks/av` | `camera.msm8996.so` links `libimg_utils` (DNG). |
