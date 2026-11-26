# LineageOS on the ZTE Axon 7

Kernel: [`kernel-4.4/`](kernel-4.4) is a submodule of
[devilAPI/android_kernel_zte_msm8996](https://github.com/devilAPI/android_kernel_zte_msm8996/tree/axon7)
(branch `axon7`, Linux 4.4.302 with the Axon 7 series from
`kernel-4.4-patches/` applied). Check it out with
`git submodule update --init lineageos-22.2/kernel-4.4`.

Status (2026-11-05): **no LineageOS 19.1 or newer exists for the Axon 7**,
neither builds nor sources. The newest is an unofficial **LineageOS 18.1
(Android 11)** by blueyfish / rcky844 (tipzbuilds), 2026-11-01.

Our port (2026-11-07): **LineageOS 22.2 (Android 15) boots to the setup
wizard** in the triple boot (shim menu entry, `los_boot`, /data on
`los_data`, file-based encryption), with the 4.4 kernel port
([KERNEL-4.4-PORT.md](KERNEL-4.4-PORT.md)) and the device tree series in
`port-22.2/` (0001-0046, plus three patches to the Android tree in
`port-22.2/aosp/` and kernel patches 0008-0020). Developer builds, nothing
published yet. Confirmed on the phone (2026-11-08): display, touch, USB/adb,
backlight, Wi-Fi, Bluetooth, NFC, 42 sensors, GPS service, flashlight,
fingerprint driver and daemon, both cameras detected (HAL3), the sound card
(AK4961 + AK4490, audio HAL routes and the speaker amplifier switch on), the
modem with `rild` on the Android 15 radio AIDL services for both SIM slots,
telephony starting cleanly (dual SIM). Open: the rear camera reports an empty
stream configuration (0x0, the camera app crashes; the front camera's is
complete), audible sound and fingerprint enrolment untested,
screen colours on one half after waking, calls/data with a SIM (untested).

**A2017U (US):** the device tree asserts `ailsa_ii`/`axon7`, which the U
also reports, and a user reports 22.2-20261109 booting on an A2017U 4/64.
Three U-specific traps are documented in
[../docs/variant-a2017u.md](../docs/variant-a2017u.md): stock B35 has no
fastboot (restore it with the B15-NEW EDL `aboot`+`fbop`, then reflash TWRP),
TWRP 3.7 can format `/data` as f2fs while this ROM needs ext4, and PARTY's
download is dead (`tools/axon7-make-vendor.sh` replaces it). Cellular is
**untested** on A2017U. The read-only `tools/axon7-preflight.sh --rom los22`
checks these before flashing.

Old vendor blobs on Android 15, and what makes them run (2026-11-08):

| Blob | Problem | Fix |
| --- | --- | --- |
| rild (IRadio 1.0-1.3 only) | Android 15 needs radio AIDL / IRadio 1.4+ | `rild_axon7`: cuttlefish `libril-modem-lib` on top of the Qualcomm RIL (0033) |
| libril-qc-qmi-1 | Android 8 sized `Parcel` on its stack (stack corruption) | imports renamed to `PaRcel`, `libril_parcel_shim` (0043) |
| netmgrd, cnd, ATFWD, IMS daemons, gnss, RIL hooks | `gBnConstructorMap` gone from libhidlbase | `aosp/system_libhidl` patch |
| pm-service | RefBase on the stack aborts | `aosp/system_core` patch |
| rild (libsettings), Widevine | `libprotobuf-cpp-*-v28` | AOSP vndk v28 prebuilts, soname `-v28` (0037) |
| camera, fingerprint | `libstdc++.so`, `libimg_utils`, `libandroid.so`, `checkCallingPermission` | `libstdc++_vendor`, frameworks/av patch, dropped NEEDED, `libbinder_perm_shim` |
| camera HAL | cameras exposed as HAL1 | `persist.vendor.camera.HAL3.enabled=1` (0045) |
| ims_rtp_daemon | `libmedia.so` | NEEDED dropped (unused) |
(`lineage-22.2-*-UNOFFICIAL-axon7.zip`) is not for the triple boot: it
writes `boot` and would replace the boot menu. Test boots run unattended
with `ios/tools/axon7-los-test.sh`. Developer builds (`AXON7_ADB_KEYS`)
have adb for that one host and write each boot's log to `los_metadata`;
unattended test boots also set `AXON7_TEST=1`.

User reports on the release zip (2026-11-14, one A2017G user, details in
`../XDA-POST-LINEAGEOS.md`): it installed (so that phone had
`TZ.BF.4.0.1-00353` and a vendor partition: `verify_trustzone` asserts, and
`block_image_update` does not create a missing by-name node) and booted to
the home screen, but **no SIM was detected**, the **camera app showed a black
screen**, and the **second start boot-looped**. None of the three was seen on
our phone, which differs in three ways: no SIM was ever inserted
(`rild_axon7`, 0033/0043/0046, never served a SIM), the release variant
(/data on `userdata`, microSD voldmanaged) was never booted (devtest keeps
/data on `los_data`), and the firmware/camera module is a different unit.
To check on the next build (needs the build server):

- `userdata` label: 0027 found that ueventd labels by-name nodes by the
  platform path only (`/dev/block/bootdevice/...` patterns never match;
  fsck/tune2fs on `los_data` were denied). Check that the release image
  labels userdata: `grep -n 'by-name/userdata\|by-name/cache'` in
  `$OUT/vendor/etc/selinux/vendor_file_contexts` and
  `$OUT/system/etc/selinux/plat_file_contexts`. If only the bootdevice path
  is there, add to `sepolicy/vendor/file_contexts`
  `/dev/block/platform/soc/624000\.ufshc/by-name/userdata u:object_r:userdata_block_device:s0`
  (and `cache` with `cache_block_device`).
- SIM: with a SIM in slot 1, `adb logcat -b radio` for `GET_SIM_STATUS` /
  `getIccCardStatus` replies from `rild_axon7`, and `dumpsys telephony.registry`.
- Second start: with a SIM inserted, a `com.android.phone` crash loop would
  make RescueParty reboot (looks like a boot loop); `adb logcat -b crash`.

## Monthly security updates

[`ci/monthly-security-update.sh`](ci/monthly-security-update.sh) is the one-shot
script for the monthly LineageOS 22.2 security update on the build server. It
takes `/srv/aosp/build.lock`, checks that all 57 device-tree and 38 kernel
patches apply to their bases, saves the local commits, runs
`repo sync -c -j4`, restores the device/kernel/vendor branches, re-applies the
five AOSP patches, rebuilds the standalone TWRP zip with `m -j4`, and writes a
summary with the before/after security patch levels, manifest revisions and
SHA-256 hashes to `/srv/aosp/axon7-monthly-22.2/monthly-<stamp>.summary`.
Copy `ci/` and the `port-22.2/` + `kernel-4.4-patches/` directories from this
repository to `/srv/aosp/axon7-monthly-22.2/` first (the script header has the
commands). A flash test of the new zip still needs a person and a spare phone.

| File | Contents |
| --- | --- |
| [FLASHING-PLAN.md](FLASHING-PLAN.md) | installing LineageOS 18.1 (or crDroid 7.39) on an A2017G: files, checksums, what the installer checks, backups, EDL rescue |
| [BUILD-PLAN-LOS22.md](BUILD-PLAN-LOS22.md) | what porting LineageOS 22.2 (Android 15) takes: a 4.4 kernel port (as gemini / LG msm8996 got), device tree forward-port, blob shims, and a build setup for an 8-thread / 31 GB / 400 GB machine |
| `build/local_manifests/axon7.xml` | repo local manifest for the build |
| [port-22.2/](port-22.2/) | the device tree forward-port to 22.2 (patch series, not built yet) |
| [ci/monthly-security-update.sh](ci/monthly-security-update.sh) | one script for the monthly upstream security-patch update (below) |

## Monthly security-patch updates

`ci/monthly-security-update.sh` runs on the build server as user `build`;
copy it together with `port-22.2/` and `kernel-4.4-patches/` into one scratch
directory (the script documents the exact commands). It waits for
`/srv/aosp/build.lock`, records the old `ro.build.version.security_patch`,
old zip and sha256, proves that all 57 device and 38 kernel patches apply to
their bases, saves the three forked project heads, syncs `lineage-22.2`
(`repo sync`, `-j4`), restores the forks, re-applies the five AOSP patches,
rebuilds the standalone zip (`AXON7_STANDALONE=1`, `-j4`), and writes a
summary with before/after patch levels and hashes. The vendor patch string
stays at the level of the 2018 Oreo blobs (`2018-12-01`); only the platform
patch level follows upstream. No phone is touched: flashing the new zip is
a human step.

2026-11-26 run (recorded before the rebuild): the tree in `/srv/aosp/lineage-22.2`
still had manifest `10ba61c` and platform patch `2026-10-01`; upstream
`lineage-22.2` was at `353894c` ("manifest: Track forks for 2026-11 ASB").
The port patches were checked in throwaway repos: 57/57 device patches apply
to `b125362` and 38/38 kernel patches to `535079d` (server logs
`verify-r3/{device,kernel}.log`). The rebuild was queued behind other builds
on `/srv/aosp/build.lock`; its result is in `monthly-run-r3.log` and the
`monthly-*.summary` file in that scratch directory.

ROM zips, recovery images and vendor blobs are not in this repository.
