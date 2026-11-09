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

| File | Contents |
| --- | --- |
| [FLASHING-PLAN.md](FLASHING-PLAN.md) | installing LineageOS 18.1 (or crDroid 7.39) on an A2017G: files, checksums, what the installer checks, backups, EDL rescue |
| [BUILD-PLAN-LOS22.md](BUILD-PLAN-LOS22.md) | what porting LineageOS 22.2 (Android 15) takes: a 4.4 kernel port (as gemini / LG msm8996 got), device tree forward-port, blob shims, and a build setup for an 8-thread / 31 GB / 400 GB machine |
| `build/local_manifests/axon7.xml` | repo local manifest for the build |
| [port-22.2/](port-22.2/) | the device tree forward-port to 22.2 (patch series, not built yet) |

ROM zips, recovery images and vendor blobs are not in this repository.
