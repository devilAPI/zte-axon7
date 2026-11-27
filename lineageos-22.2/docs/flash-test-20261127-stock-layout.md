# Flash test 2026-11-27: stock-layout zip on the second Axon 7

Phone: second Axon 7 in TWRP 3.3.1-0, ZTE stock partition table (no vendor partition).
Run 1 (zip 20261126) was aborted before writing, see "Run 1". Run 2 (zip 20261127, rebuilt) is below.

## Zip (run 2)

lineage-22.2-20261127-UNOFFICIAL-axon7.zip, 1973847708 bytes (< 2 GiB),
sha256 d6aca4d2c0ec1f69c7688e7085541b8c59cf3170501d1987d8a849a0e4a1bea6
(verified on the phone after the adb push). Both layouts rebuilt from the same tree
(AXON7_LAYOUTS=both, no AXON7_REUSE_VENDOR), device patches 0001 (A2017 asserts), 0058, 0059 applied
during the build only, device tree restored afterwards, original soong_build restored.
Build host needs GOMEMLIMIT=20GiB GOGC=40 through a temporary soong_build wrapper (Soong OOM otherwise).

## Results

| Check | Result |
|---|---|
| updater-script asserts ailsa_ii, axon7, A2017G, ZTE_A2017G, A2017U, ZTE_A2017U, A2017, ZTE_A2017 | PASS (also visible in the install: assert passed on the phone) |
| install/bin/axon7-layout.sh has the `$((a >= b))` 64-bit compares | PASS |
| verify-stock-image.py (stock system.img vs vendor-layout vendor.img) | PASS: LABELS IDENTICAL (1882 entries, capabilities equal, no missing files) |
| Backups of boot and system (adb exec-out dd) | PASS: sha256 on the PC equals the phone's own sha256sum for both |
| axon7-layout.sh on the phone prints "Layout: stock" | PASS when run as `sh script`; FAIL when exec'd (see bug 2) |
| `twrp install` of the first rebuilt zip | FAIL: "file_getprop: failed to read /tmp/axon7-layout.prop", nothing written (bug 2) |
| `twrp install` of the re-signed zip (shebang fixed) | PASS: "Layout: stock", "Installing for the stock layout (no vendor partition): vendor goes into system.", system patched, boot-nv.img written, "script succeeded" |
| First boot | first attempt (with adb keys pre-seeded in /data/misc) FAIL, see bug 3; second attempt (clean /data) boots far enough that the phone enumerates as MTP (18d1:4ee1) and stays so for 5+ minutes |
| /vendor -> /system/vendor, Wi-Fi, audio HAL, surfaceflinger, avc, tombstones, security patch, 15 min uptime | NOT RUN: the release zip has no adb (no developer keys, adb off), so nothing can be queried; the phone is reachable only after a manual reboot into TWRP (power + volume up) |

## Bugs found

1. TWRP 3.3.1 busybox `[ -ge ]` is 32-bit (fixed in 6234eb7, verified in the zip).
2. ci/axon7-layout.sh had `#!/bin/sh`. TWRP has no /bin/sh (only /sbin/sh), so edify `run_program`
   could not exec it ("not found"), no layout.prop was written and the install aborted before
   writing. PC tests and manual runs used `sh script`, so they passed. Fixed to `#!/sbin/sh`.
   The shipped zip was re-combined and re-signed from the already built parts with the fixed script
   (combine-zip.py), +1 byte.
3. `twrp format data` does not exist in TWRP 3.3.1 and `twrp wipe data` only formatted /cache;
   userdata was held by a stale dm-crypt mapping (dm-0) so mke2fs refused. `make_ext4fs` on
   the raw block device worked (ext4, then TWRP mounted it).
   Pre-seeding /data/misc from TWRP makes the first boot fail: init cannot set the FBE encryption policy
   on a non-empty /data/misc, vold fails (reboot_on_failure) and init reboots into recovery. Never
   create /data/misc or /data/property from TWRP on a freshly formatted /data.
4. The release zip has no adb. To test it, either flash a developer build, add a test-only init rc to
   /system/vendor/etc/init from TWRP after the install, or enable USB debugging on the screen.

## Run 1 (zip 20261126, aborted)

The old zip asserted only ailsa_ii/axon7 (vendor-layout set reused from an older build) and the layout
script's 32-bit compare rejected the 6 GiB system partition. Nothing was written.

## Runtime checks (2026-11-27, USB debugging enabled by hand)

| Check | Result |
|---|---|
| Uptime without reboot | 2 h 39 min (stable) |
| sys.boot_completed | 1 |
| Version / security patch | 22.2-20261127-UNOFFICIAL-axon7 / 2026-11-01 |
| /vendor | symlink to /system/vendor |
| SELinux | Enforcing, 0 avc denials (logcat all buffers + dmesg) |
| Wi-Fi | enabled, scan finds networks |
| Audio / camera / composer / sensors / Wi-Fi HALs | running |
| Tombstones / crash buffer | 0 / 0 |
| Service deaths | only idmap (lazy service, normal) |

Verdict: PASS. Zip sha256 d6aca4d2c0ec1f69c7688e7085541b8c59cf3170501d1987d8a849a0e4a1bea6.
