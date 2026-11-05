# Axon 7 (A2017G): LineageOS 18.1 (Android 11) flashing plan

No LineageOS 19.1, 20, 21 or 22 build exists for axon7 (checked 2026-11-05).
The newest is **LineageOS 18.1 UNOFFICIAL 2026-11-01** by Ricky Cheung
(GitHub `blueyfish` / `rcky844`, site "tipzbuilds").

Do not touch the phone while the other workstream is using it. Every command
below is for the user to run later.

## Files (in lineageos/downloads/)

| File | Source | Checksum |
|---|---|---|
| los18.1-20261101/lineage-18.1-20261101-UNOFFICIAL-axon7.zip (758,215,168 B) | https://sourceforge.net/projects/tipzbuilds/files/ROMs/ZTE%20Axon%207/LineageOS%2018.1/20261101/ | MD5 e0cd911012f448cd323659de95073afa (SourceForge) |
| los18.1-20261101/recovery.img (Lineage Recovery, 20,111,360 B) | same folder | MD5 2a14b2a9d54892a03035914a007bb09f |
| los18.1-20261101/boot.img (11,898,880 B; the zip contains the same boot) | same folder | MD5 4a4c627abbe97d0e2b9ca894f5cdd121 |
| crdroid7.39-20261102/crDroidAndroid-11.0-20261102-axon7-v7.39.zip (847,588,575 B), optional alternative | https://sourceforge.net/projects/tipzbuilds/files/ROMs/ZTE%20Axon%207/crDroid/ | MD5 26424d910bc1abd18e50419d9ff14284 |
| gapps/MindTheGapps-11.0.0-arm64-20230922_081122.zip (194,494,611 B) | https://github.com/MindTheGapps/11.0.0-arm64/releases | size from the GitHub release |
| TWRP 3.7.0_9-0 (download it yourself in a browser; dl.twrp.me blocks direct downloads) | https://dl.twrp.me/ailsa_ii/twrp-3.7.0_9-0-ailsa_ii.img.html | SHA256 d74410d0f82808901123609bad04d20362a30280dca03cac5e5c68b38380473b |

`sha256sum -c` / `md5sum -c` lists are in `downloads/CHECKSUMS.*`.

## What the ROM zip does (from its updater-script)

1. It asserts that `ro.product.device` or `ro.build.product` is `ailsa_ii` or `axon7`. TWRP for this phone reports `ailsa_ii`, so this passes.
2. It runs `assert(axon7.verify_trustzone("TZ.BF.4.0.1-00353") == "1")`, which reads `QC_IMAGE_VERSION_STRING=` from the `tz` partition. This is the Oreo-era bootstack, the same one required since official LineageOS 15.1 (the device tree commit "axon7: Update to B12", 2018-04-24). The phone already runs a LineageOS 17.1 build, so it almost certainly has this firmware already.
3. It writes block images to `by-name/system` (needs at least 1,409,025 4K blocks = 5,771,366,400 B) and `by-name/vendor` (needs at least 98,307 blocks = 402.7 MB; the 512 MiB vendor partition fits). It then writes `boot.img` to `by-name/boot`.
4. It **does not touch** the bootloader, aboot, tz, modem, persist, EFS or recovery. The ROM flash itself cannot hard-brick the phone. Restoring a TWRP backup undoes it.
5. It carries a spoofed stock fingerprint `ZTE/P996A03_O/msm8996:8.0.0/OPR1.170623.032/520`. SDK 30. The security patch shows 2024-02-05.

crDroid 7.39 has identical asserts (same TZ string, same system+vendor+boot layout).

## Pre-flight checks (read-only; run in TWRP > Advanced > Terminal, or `adb shell` in recovery)

```sh
# 1. TrustZone version: must print TZ.BF.4.0.1-00353
cat /dev/block/bootdevice/by-name/tz | tr -c '[:print:]' '\n' | grep QC_IMAGE_VERSION_STRING
# 2. Partition sizes (512-byte sectors): system >= 11272200, vendor >= 786456
for p in system vendor boot recovery; do b=$(readlink -f /dev/block/bootdevice/by-name/$p); echo "$p $b $(cat /sys/class/block/${b##*/}/size)"; done
# 3. Model / bootloader strings for the record
getprop ro.product.device; getprop ro.bootloader; getprop gsm.version.baseband
```
If check 1 prints anything other than `TZ.BF.4.0.1-00353`, **stop** and report back. Do not flash firmware zips blindly (see "Firmware" below).

## Steps

0. **Back up first.** In TWRP, back up Boot, System, Vendor, Data and **EFS** (modemst1/modemst2). Copy the backup off the phone. Also save the EFS-related partitions raw (`dd if=/dev/block/bootdevice/by-name/{modemst1,modemst2,fsg,fsc,persist} of=/sdcard/...`) and pull them to the PC. A lost EFS means a lost IMEI and cannot be recreated. Copy photos and files off internal storage, because step 3 erases it.
1. **Update recovery to TWRP 3.7.0_9-0** (old TWRP 3.3.0 would probably work for the zip, since it uses its own update-binary, but 3.7 handles Android 11 data/encryption better). In TWRP 3.3.0 go to Install > Install Image > `twrp-3.7.0_9-0-ailsa_ii.img` > **Recovery**. Or from fastboot: `fastboot flash recovery twrp-3.7.0_9-0-ailsa_ii.img`. Reboot to recovery and confirm it shows 3.7.0.
   - Alternative: the tipz `recovery.img` (Lineage Recovery for 18.1). Use it only if you don't want TWRP; it can't make backups.
2. Copy the ROM zip and the GApps zip to the phone (`adb push` in recovery, or MTP/an SD card).
3. **Clean wipe.** You are moving from someone else's 17.1 eng build, which is signed with different keys. Wipe > Advanced Wipe: Dalvik/ART cache, Cache, System, **Vendor**, Data. Then Wipe > **Format Data** (type `yes`) to remove the old encryption/metadata. This erases internal storage.
4. Install `lineage-18.1-20261101-UNOFFICIAL-axon7.zip`.
5. (Optional) Install `MindTheGapps-11.0.0-arm64-20230922_081122.zip` right away, **before the first boot**. Adding GApps after the first boot causes crashes.
6. (Optional) Magisk: flash it after the first successful boot.
7. Reboot to system. The first boot takes 5 to 10 minutes.
8. Check that calls, mobile data, Wi-Fi, BT, camera, fingerprint, audio, NFC and SD card work.

## Known issues (from the maintainer's changelog, tipzbuilds axon7.json)
- 18.1-20261101: "Improve overall performance (RCU_NOCB, HMP C-state aware, drop input boost)". 18.1-20261031: "Updated to latest Android 11; fixed fingerprint".
- 18.0-20261029: "WebView is not bundled; install Google's version manually". It may still apply. With GApps, install "Android System WebView" from Play; without GApps, install it from APKMirror or use Bromite/Vanadium WebView.
- 17.1-20261026 listed "Radio does not work (needs upgrading the stack)". 17.1-20261027 fixed the RIL crash. Radio isn't mentioned for 18.1, so test calls and data straight away.
- These are brand-new builds (days old) from one maintainer, with no XDA feedback yet. XDA thread: "[ROM][9.0/10.0/11.0][UNOFFICIAL] LineageOS for ZTE Axon 7 (A2017)" by rcky844. XDA blocked automated reads, so I couldn't read it.

## Firmware (only if the TZ check fails)
- The required bootstack gives `TZ.BF.4.0.1-00353` ("O bootloader" / Oreo universal bootstack + the A2017G Oreo modem, as used by LineageOS 15.1 to 18.1 for axon7). It is distributed only on XDA (official LineageOS 15.1 thread, DrakenFX and raystef66 threads) and AndroidFileHost. I did **not** download or verify any firmware zip.
- **This is the irreversible / brick-capable step.** A wrong or mismatched bootstack (aboot/xbl/tz/rpm/hyp/cmnlib) can leave the phone without a working bootloader. Flash only a zip clearly labelled for A2017G/universal Oreo, and read its updater-script first. Never flash a stock full-OTA or a bootstack that re-locks the bootloader.
- **EDL rescue:** Qualcomm 9008 mode is in the boot ROM and survives a bad bootloader. Power off, hold Vol+ and Vol- together, and plug in USB (or run `adb reboot edl` / `fastboot oem edl` while it still boots). The device shows up as `05c6:9008`. Restore with an A2017G full EDL package (Oreo B10/B12) and its `prog_ufs_firehose_8996_ddr.elf`, using QFIL/MiFlash on Windows, or `edl` (bkerler) on Linux. **Back up EFS before any firmware work**, because EDL full packages can wipe EFS and with it the IMEI.

## Roll-back
Restore the TWRP backup (Boot, System, Vendor, Data) from step 0. The bootloader and modem were never changed, so the old 17.1 build boots again.
