# LineageOS on the ZTE Axon 7

Status (2026-11-05): **no LineageOS 19.1 or newer exists for the Axon 7**,
neither builds nor sources. The newest is an unofficial **LineageOS 18.1
(Android 11)** by blueyfish / rcky844 (tipzbuilds), 2026-11-01.

Our port (2026-11-07): **LineageOS 22.2 (Android 15) boots to the setup
wizard** in the triple boot (shim menu entry, `los_boot`, /data on
`los_data`, file-based encryption), with the 4.4 kernel port
([KERNEL-4.4-PORT.md](KERNEL-4.4-PORT.md)) and the device tree series in
`port-22.2/` (0001-0029). Display, USB/adb and the boot itself work;
nothing else is tested yet, nothing is published. The plain zip
(`lineage-22.2-*-UNOFFICIAL-axon7.zip`) is not for the triple boot: it
writes `boot` and would replace the boot menu. Test boots run unattended
with `ios/tools/axon7-los-test.sh` (test builds: `AXON7_ADB_KEYS`).

| File | Contents |
| --- | --- |
| [FLASHING-PLAN.md](FLASHING-PLAN.md) | installing LineageOS 18.1 (or crDroid 7.39) on an A2017G: files, checksums, what the installer checks, backups, EDL rescue |
| [BUILD-PLAN-LOS22.md](BUILD-PLAN-LOS22.md) | what porting LineageOS 22.2 (Android 15) takes: a 4.4 kernel port (as gemini / LG msm8996 got), device tree forward-port, blob shims, and a build setup for an 8-thread / 31 GB / 400 GB machine |
| `build/local_manifests/axon7.xml` | repo local manifest for the build |
| [port-22.2/](port-22.2/) | the device tree forward-port to 22.2 (patch series, not built yet) |

ROM zips, recovery images and vendor blobs are not in this repository.
