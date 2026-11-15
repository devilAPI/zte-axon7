**LineageOS 24 (Android 17) on mainline Linux 7.3.1 for the ZTE Axon 7 (A2017G)**: an **alpha / developer preview**, flashable in TWRP into the LineageOS slot of the multi-boot setup. Not for daily use: no calls, no mobile data, no camera, no suspend.

> **Alpha. Back up first.** Make a TWRP backup (Boot, EFS, Modem, and anything else you want to keep) and copy it to a computer before installing. Any failure while flashing can brick the phone.

### Requirements (read first)

- **A2017G** only (tested on 4 GB / 64 GB).
- Unlocked bootloader, **TWRP 3.3.0-0** (`twrp-3.3.0-0-ailsa_ii.img` from https://dl.twrp.me/ailsa_ii/; the tested version).
- The project's **multi-boot setup** (boot menu with iOS / Nura / LineageOS), including the partition step `axon7-tripleboot-gpt`, which creates the LineageOS partitions: [DEV-MULTIBOOT.md](https://github.com/devilAPI/zte-axon7/blob/main/DEV-MULTIBOOT.md). This build does not install on its own.
- The **vendor partition** of a ROM installed before (LineageOS 16–18.1, or this project's LineageOS 22.2) must still be in place: the GPU firmware is read from it. Do not wipe Vendor in TWRP.

### What the zip changes

- Writes `super.img` into the GPT partition `system` and the kernel into `los_boot`.
- Erases `los_metadata` and `los_data`: **all LineageOS data in the multi-boot slot is lost**, and a LineageOS 22.2 installed in that slot is replaced.
- Does not touch `boot`, `misc`, iOS, Nura, `persist`, the modem/EFS partitions or the bootloader.

No proprietary firmware is in the zip. LineageOS 24 loads the modem, DSP, GPU and Wi-Fi board firmware straight from the phone's own partitions, read-only, at every start (`modem`, and `a530_zap` from `vendor`). **This is new in this release and still being tested.**

### Install

1. TWRP 3.3.0-0: back up (see above) and copy the backup to a computer.
2. `sha256sum -c` the zip against the `.sha256` file.
3. Copy the zip to the phone and install it in TWRP; it must finish without an error.
4. Reboot and choose **LineageOS** in the boot menu. The first start takes a few minutes.

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
