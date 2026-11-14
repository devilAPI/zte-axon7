**LineageOS 22.2 (Android 15) for the ZTE Axon 7 (A2017G)**: an **unofficial LineageOS 22.2 release**, flashable in TWRP. This is not the multi-boot setup: it replaces the Android on the phone.

### Requirements (read first)

- **A2017G** only (tested on 4 GB / 64 GB).
- Unlocked bootloader, **TWRP 3.3.0-0** (`twrp-3.3.0-0-ailsa_ii.img` from https://dl.twrp.me/ailsa_ii/; the version this zip was tested with). TWRP 3.7.0_9-0 has been reported to restart by itself on this phone; 3.2.x builds are untested.
- The **Oreo "universal" bootstack** (TrustZone `TZ.BF.4.0.1-00353`), the same as LineageOS 15.1–18.1 needed. The installer checks it and stops if it is missing. If LineageOS 18.1 or crDroid 7.x installs on your phone, you have it.
- **The community vendor partition** (512 MiB after system), as for LineageOS 16–18.1. If you came from one of those, you have it. If not, create it with Oki's **PARTY** tool (TWRP zip, https://xdaforums.com/t/tool-treble-party-v0-5-vendor-partition-manager-2018-08-31.3831517/) first. The original ZTE layout without a vendor partition is **not** supported.
- With the vendor partition, official ZTE firmware can't be flashed until it is removed again (PARTY tool). Any failure while flashing or repartitioning can brick the phone.

### Install (clean)

Installing **erases internal storage**: copy your photos and files to a computer first.

1. TWRP 3.3.0-0: back up Boot, System, Vendor, Data and EFS, and copy the backup to a computer.
2. Wipe → Advanced Wipe → tick only **Data** → Repair or Change File System: if it says **F2FS**, Change File System → **EXT4** (this ROM mounts /data as ext4 only).
3. Wipe → **Format Data** (type `yes`). **Always**, whichever ROM you come from (stock, LineageOS, crDroid, encrypted or not); only an update from an earlier 22.2 build skips it. Android 15 uses file-based encryption and cannot use an old data partition; Advanced Wipe → Data alone keeps internal storage and is not enough. Then Reboot → Recovery.
4. Wipe → Advanced Wipe: **Dalvik, Cache, System, Vendor**.
5. Copy this zip to the phone and install it; it must finish without an error. Optionally a GApps package for Android 15 / arm64 right after (if the first start fails, try once without GApps).
6. Reboot → System. The first start takes a few minutes.

Boot loop? Check steps 2 and 3 first. Then, in TWRP right after the loop, `adb pull /sys/fs/pstore/` (or `cat /sys/fs/pstore/console-ramoops* > /external_sd/los-ramoops.txt` to a microSD card) and post it in the XDA thread with TWRP's `/tmp/recovery.log`, your TWRP version and the ROM you came from.

`sha256sum -c` the zip against the `.sha256` file before flashing.

### State

SELinux is enforcing. 
See the XDA thread for what works and what does not. The kernel (GPLv2) is at https://github.com/devilAPI/android_kernel_zte_msm8996/tree/axon7 and the patches are in this repository (`lineageos-22.2/`).

Not affiliated with ZTE or LineageOS. Flash at your own risk.
