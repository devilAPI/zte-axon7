**LineageOS 22.2 (Android 15) for the ZTE Axon 7 (A2017G)**: an **unofficial LineageOS 22.2 release**, flashable in TWRP. This is not the multi-boot setup: it replaces the Android on the phone.

### Requirements (read first)

- **A2017G** only (tested on 4 GB / 64 GB).
- Unlocked bootloader, **TWRP 3.3.0-0** (`twrp-3.3.0-0-ailsa_ii.img` from https://dl.twrp.me/ailsa_ii/; the version this zip was tested with). TWRP 3.7.0_9-0 has been reported to restart by itself on this phone; 3.2.x builds are untested.
- The **Oreo "universal" bootstack** (TrustZone `TZ.BF.4.0.1-00353`), the same as LineageOS 15.1–18.1 needed. The installer checks it and stops if it is missing. If LineageOS 18.1 or crDroid 7.x installs on your phone, you have it.
- **The community vendor partition** (512 MiB after system), as for LineageOS 16–18.1. If you came from one of those, you have it. If not, create it with Oki's **PARTY** tool (TWRP zip, https://xdaforums.com/t/tool-treble-party-v0-5-vendor-partition-manager-2018-08-31.3831517/) first. The original ZTE layout without a vendor partition is **not** supported.
- With the vendor partition, official ZTE firmware can't be flashed until it is removed again (PARTY tool). Any failure while flashing or repartitioning can brick the phone.

**Coming from stock ZTE firmware?** Check in TWRP → Advanced → Terminal (read-only): `cat /dev/block/bootdevice/by-name/tz | tr -c '[:print:]' '\n' | grep QC_IMAGE_VERSION_STRING` must contain `TZ.BF.4.0.1-00353`, and `ls -l /dev/block/bootdevice/by-name/vendor` must show a block device (otherwise create the vendor partition with PARTY first; without it the install stops with an error after system has been written). A good first test of firmware and partitions is LineageOS 18.1: if calls, data and the camera work there, the firmware is fine for this ROM.

### Known issues

- **SIM card not detected** (one user report, A2017G). Our phone was only tested without a SIM: the modem and the radio services start, but SIM detection, calls and mobile data are untested. Not for daily use yet if you need the SIM.
- **Camera app shows a black screen** (one user report; both cameras work on our phone).
- **Boot loop on the second start** after a working first start (one user report, under investigation).
- The phone sometimes wakes up or locks by itself.

### Install (clean)

Installing **erases internal storage**: copy your photos and files to a computer first.

1. TWRP 3.3.0-0: back up Boot, System, Vendor, Data and EFS, and copy the backup to a computer.
2. Wipe → Advanced Wipe → tick only **Data** → Repair or Change File System: if it says **F2FS**, Change File System → **EXT4** (this ROM mounts /data as ext4 only).
3. Wipe → **Format Data** (type `yes`). **Always**, whichever ROM you come from (stock, LineageOS, crDroid, encrypted or not); only an update from an earlier 22.2 build skips it. Android 15 uses file-based encryption and cannot use an old data partition; Advanced Wipe → Data alone keeps internal storage and is not enough. Then Reboot → Recovery.
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
