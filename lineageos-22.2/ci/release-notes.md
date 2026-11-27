**LineageOS 22.2 (Android 15) for the ZTE Axon 7 (A2017G)**: an **unofficial LineageOS 22.2 release**, flashable in TWRP. This is not the multi-boot setup: it replaces the Android on the phone.

### Requirements (read first)

- **A2017G** (tested on 4 GB / 64 GB). **A2017U** (US): one user reports 22.2-20261109 booting; cellular is untested (see below). **A2017** (China): untested.
- Unlocked bootloader, **TWRP 3.3.0-0** (`twrp-3.3.0-0-ailsa_ii.img` from https://dl.twrp.me/ailsa_ii/; 3.3.1-0 was also tested with this zip). TWRP 3.7.0_9-0 has been reported to restart by itself on this phone; 3.2.x builds are untested.
- The **Oreo "universal" bootstack** (TrustZone `TZ.BF.4.0.1-00353`), the same as LineageOS 15.1–18.1 needed. The installer checks it and stops if it is missing. If LineageOS 18.1 or crDroid 7.x installs on your phone, you have it.
- **Either partition layout.** The zip carries two image sets and the installer picks one **before writing anything**: with the community vendor partition (512 MiB after system, as for LineageOS 16–18.1) it installs system + vendor; with ZTE's original layout (no vendor partition) it puts the vendor files **inside the system image** and does not repartition. If neither fits (no usable system/boot partition, system smaller than 5.5 GiB) it stops with an error and writes nothing. Stock-layout phones keep the option to flash official ZTE firmware later; no PARTY/sgdisk step is needed.
- Any failure while flashing can brick the phone. Back up first.

**A2017U (US) owners:** the hardware and codename (`ailsa_ii`/`axon7`) are the same, but five things differ:

- **Unlocking:** stock A2017U B35 has **no fastboot endpoint**; `adb reboot bootloader` does not expose one. An **EDL** flash (phone off, hold Volume Up + Volume Down, plug in USB) of the **B15-NEW `aboot` + `fbop`** restores `fastboot oem unlock` (B29 alone was not enough for the reporting user). The package overwrites recovery: **flash TWRP again** and re-check the TrustZone line above.
- **Modem:** use an **A2017U** modem package, never the A2017G one (the Oreo bootstack is universal, the modem is model-specific).
- **`/data` must be ext4:** TWRP 3.7.0_9-0 can format userdata as **f2fs**; this ROM then fails with `invalid magic`, apexd aborts and the phone loops. Check Data after Format Data (step 3) and change it to EXT4 if needed. `mke2fs -t ext4` also worked for the reporter.
- **Cellular is UNTESTED on A2017U.** The reporter says the U variant uses a different modem path and has not verified calls, SMS or data. Do not assume they work.
- **PARTY is no longer downloadable** (AFH `fid=1322778262903995063` has no mirrors). The equivalent is TWRP's own `sgdisk`: delete partition 13, recreate it 512 MiB shorter, and create partition 28 `vendor` in the freed space, using the phone's real 4096-byte-sector numbers. `tools/axon7-make-vendor.sh` (in the repository) prints a read-only plan and writes only with `--apply --yes`.

Run `tools/axon7-preflight.sh --rom los22` in TWRP before flashing; it is read-only and stops on f2fs or the wrong TrustZone. A missing vendor partition is only a warning: this zip installs without one. More: `docs/variant-a2017u.md`.

**Coming from stock ZTE firmware?** Check in TWRP → Advanced → Terminal (read-only): `cat /dev/block/bootdevice/by-name/tz | tr -c '[:print:]' '\n' | grep QC_IMAGE_VERSION_STRING` must contain `TZ.BF.4.0.1-00353`, (a vendor partition is **not** needed: without one the installer uses the stock layout; the stock-layout path was tested on 2026-11-27 on an A2017G with ZTE's original layout and TWRP 3.3.1-0: installed, booted, enforcing with no SELinux denials, Wi-Fi/audio/camera services up, stable for hours). A good first test of firmware and partitions is LineageOS 18.1: if calls, data and the camera work there, the firmware is fine for this ROM.

### Known issues

- **SIM card not detected** (one user report, A2017G). Our phone was only tested without a SIM: the modem and the radio services start, but SIM detection, calls and mobile data are untested. Not for daily use yet if you need the SIM.
- **Camera app shows a black screen** (one user report; both cameras work on our phone).
- **Boot loop on the second start** after a working first start (one user report, under investigation).
- The phone sometimes wakes up or locks by itself.

### Install (clean)

Installing **erases internal storage**: copy your photos and files to a computer first.

1. TWRP 3.3.0-0: back up Boot, System, Vendor, Data and EFS, and copy the backup to a computer.
2. Wipe → Advanced Wipe → tick only **Data** → Repair or Change File System: if it says **F2FS**, Change File System → **EXT4** (this ROM mounts /data as ext4 only).
3. Wipe → **Format Data** (type `yes`). **Always**, whichever ROM you come from (stock, LineageOS, crDroid, encrypted or not); only an update from an earlier 22.2 build skips it. Android 15 uses file-based encryption and cannot use an old data partition; Advanced Wipe → Data alone keeps internal storage and is not enough. **Then check Data again** (Advanced Wipe → Data → Repair or Change File System): TWRP 3.7.0_9-0 can leave it as **F2FS** here; change it to **EXT4** if so. Reboot → Recovery.
4. Wipe → Advanced Wipe: **Dalvik, Cache, System, Vendor**.
5. Copy this zip to the phone and install it; it must finish without an error. Optionally a GApps package for Android 15 / arm64 right after (if the first start fails, try once without GApps).
6. Reboot → System. The first start takes a few minutes.

Boot loop? Check steps 2 and 3 first. Then, in TWRP right after the loop, `adb pull /sys/fs/pstore/` (or `cat /sys/fs/pstore/console-ramoops* > /external_sd/los-ramoops.txt` to a microSD card) and post it in the XDA thread with TWRP's `/tmp/recovery.log`, your TWRP version and the ROM you came from.

It starts but something does not work (SIM, camera)? Before rebooting, enable USB debugging (Settings → About phone → tap Build number 7 times; System → Developer options) and post `adb logcat -b all -d`, `adb shell dmesg` and `adb shell getprop`.

`sha256sum -c` the zip against the `.sha256` file before flashing.

### State

SELinux is enforcing. 
See the XDA thread for what works and what does not. The kernel (GPLv2) is at https://github.com/devilAPI/android_kernel_zte_msm8996/tree/axon7 and the patches are in this repository (`lineageos-22.2/`).

Not affiliated with ZTE or LineageOS. Flash at your own risk.
