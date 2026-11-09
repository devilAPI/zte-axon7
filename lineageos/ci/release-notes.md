**LineageOS 22.2 (Android 15) for the ZTE Axon 7 (A2017G)**: an **unofficial LineageOS 22.2 release**, flashable in TWRP. This is not the multi-boot setup: it replaces the Android on the phone.

### Requirements (read first)

- **A2017G** only (tested on 4 GB / 64 GB).
- Unlocked bootloader, **TWRP 3.3.0 or newer** (3.7.0_9-0 recommended).
- The **Oreo "universal" bootstack** (TrustZone `TZ.BF.4.0.1-00353`), the same as LineageOS 15.1–18.1 needed. The installer checks it and stops if it is missing.
- **The community vendor partition** (512 MiB after system), as for LineageOS 16–18.1. If you came from one of those, you have it. If not, create it with Oki's **PARTY** tool (TWRP zip, https://xdaforums.com/t/tool-treble-party-v0-5-vendor-partition-manager-2018-08-31.3831517/) first. The original ZTE layout without a vendor partition is **not** supported.
- With the vendor partition, official ZTE firmware can't be flashed until it is removed again (PARTY tool). Any failure while flashing or repartitioning can brick the phone.

### Install (clean)

1. TWRP: back up Boot, System, Vendor, Data and EFS, and copy the backup to a computer.
2. Wipe → Advanced: **Dalvik, Cache, System, Vendor, Data**. Coming from LineageOS 18.1 or older (footer encryption), also **Format Data** (type `yes`): Android 15 uses file-based encryption.
3. Install this zip (optionally a GApps package for Android 15 / arm64 afterwards).
4. Reboot → System. The first start takes a few minutes.

`sha256sum -c` the zip against the `.sha256` file before flashing.

### State

SELinux is enforcing. 
See the XDA thread for what works and what does not. The kernel (GPLv2) is at https://github.com/devilAPI/android_kernel_zte_msm8996/tree/axon7 and the patches are in this repository (`lineageos/`).

Not affiliated with ZTE or LineageOS. Flash at your own risk.
