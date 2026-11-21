**LineageOS 24 (Android 17) on mainline Linux 7.3.1 for the ZTE Axon 7 (A2017G)**: an **alpha / developer preview**, flashable in TWRP as a **stand-alone ROM** (stock partition layout, no multi-boot). Not for daily use: no calls, no mobile data, no camera, no deep sleep.

> **Alpha. Back up first.** Make a TWRP backup (Boot, System, Data, EFS, Modem) and copy it to a computer before installing. Any failure while flashing can brick the phone.

### Requirements (read first)

- **A2017G** only (tested on 4 GB / 64 GB).
- Unlocked bootloader, **TWRP 3.3.0-0 or newer** (3.3.0-0 is the tested version; older builds are refused by the installer).
- **The stock partition layout**: the zip writes `boot`, `system` and `userdata` and needs a `cache` partition. No multi-boot setup, no `los_*` partitions, no `axon7-tripleboot-gpt`, no PARTY/vendor repartitioning. Installing over our developer multi-boot setup replaces the boot menu in `boot`.
- An old Android ROM in `system` containing the GPU's signed `a530_zap` firmware (stock Oreo/Nougat keeps it in `system/etc/firmware`; LineageOS 16–22.2 in `vendor/firmware`). The installer copies it to `cache` before overwriting `system` and stops with a clear error if it cannot find it.

### What the zip changes

- Writes `super.img` into the GPT partition `system` and the boot image (kernel + mainline Axon 7 DTB + ramdisk) into `boot`. ZTE's bootloader boots this image directly; there is **no boot menu or shim**.
- Copies `a530_zap.mdt` and `a530_zap.bNN` from the old ROM into `/cache/firmware` first. The stock layout has no `vendor` partition; the ROM mounts `cache` read-only at `/mnt/vendor/fw_vendor` for its firmware symlinks.
- Erases `userdata` (and `metadata` if present). Android sets up file-based encryption at the first start. Format Data in TWRP first to get rid of old encryption.
- Does **not** touch `misc`, the boot menu, iOS, Nura, `persist`, the modem/EFS partitions (`modemst1/2`, `fsg`, `fsc`) or the bootloader.

No proprietary firmware is in the zip. The ROM loads the modem, DSP, GPU and Wi-Fi board firmware straight from the phone's own partitions, read-only, at every start.

### Install

1. Charge to at least 50 %. In TWRP 3.3.0-0: **Backup** (Boot, System, Data, EFS, Modem) and copy the backup to a computer.
2. Wipe → **Format Data** (type `yes`) → Reboot → Recovery. Optionally wipe Dalvik / ART Cache and Cache.
3. `sha256sum -c` the zip against the `.sha256` file.
4. Copy the zip to the phone and install it in TWRP; it must finish without an error (about 7 minutes). `adb sideload` works too.
5. Reboot normally (no boot menu, no key combination). The first start takes a few minutes, then the setup wizard appears. Do not interrupt it.

The standalone boot image is header v0 with a gzip-compressed mainline `Image` and the board DTB appended, like Nura's boot.img. Its cmdline carries `androidboot.hardware=axon7m`, `androidboot.boot_devices=soc@0/624000.ufshc`, `androidboot.super_partition=system`, the display and clock options; first-stage init mounts logical `system`/`vendor` and by-name `userdata`, with no `los_*` names.

**Multi-boot is only for the developer builds:** the owner builds the old flavour with `AXON7_MULTIBOOT=1` (image and `ci/make-zip.sh`; zip name ends in `-MULTIBOOT.zip`), which writes `los_boot`, wipes `los_metadata`/`los_data` and boots through the shim. It is not published in the releases.

### State

Tested on the phone: boots to the setup wizard and home screen; display 1440x2560 with brightness slider; touchscreen and the three touch keys; Wi-Fi scans and connects; Bluetooth turns on; speaker playback and microphone recording; accelerometer, gyroscope, magnetometer, light and proximity sensors; battery level and charging; temperature sensors; hardware watchdog; plain reboot returns to LineageOS; modem firmware boots and goes online, GNSS service starts; software codecs (Codec2). A 20-minute stress soak ran without crashes, reboots or kernel warnings.

Built, not tested yet: headphone playback (jack detection is wired up), vibrator, GPS fix.

Not working: calls, SMS, mobile data (no radio HAL yet; SIM not detected so far), camera, fingerprint (TrustZone-owned), NFC, suspend/deep sleep (short battery life), encryption.

Scrolling is usable but not perfectly smooth (about 13 % janky frames in a scroll benchmark).

Userdebug build, SELinux **permissive** (policy in progress). Graphics: Mesa freedreno (Adreno 530, GLES 3.1), drm_hwcomposer, minigbm.

### Problems

Enable USB debugging (Settings → About phone → tap Build number 7 times; System → Developer options) and send `adb logcat -b all -d` and `adb shell dmesg`. After a crash or restart, go to TWRP right away (Power + Volume Up about 10 s) and send `adb pull /sys/fs/pstore/`. Say which build (date) you run.

### Source

Kernel (GPLv2): Linux 7.3.1 with the Axon 7 patches at https://github.com/devilAPI/linux/tree/zte-axon7, plus the Android kernel patches, Mesa patches and device tree on the `lineageos-24-mainline` branch of https://github.com/devilAPI/zte-axon7 (folder `lineageos-24-mainline/`).

Not affiliated with ZTE or LineageOS. Flash at your own risk.
