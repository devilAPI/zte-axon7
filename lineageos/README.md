# LineageOS on the ZTE Axon 7

Status (2026-11-05): **no LineageOS 19.1 or newer exists for the Axon 7**,
neither builds nor sources. The newest is an unofficial **LineageOS 18.1
(Android 11)** by blueyfish / rcky844 (tipzbuilds), 2026-11-01.

Our port (2026-11-06): **LineageOS 22.2 (Android 15) builds** on the build
server: `lineage-22.2-20261106-UNOFFICIAL-axon7.zip` (992 MB) with the 4.4
kernel port ([KERNEL-4.4-PORT.md](KERNEL-4.4-PORT.md)) and the device tree
series in `port-22.2/` (0001-0020). **Not tested on a phone, not
published.** The zip is a plain LineageOS installer: it writes `boot` and
uses `userdata` for /data, which would replace the iOS/postmarketOS boot
menu and the iOS partition. For the triple boot it still has to boot from
`los_boot` through the shim and use `los_data` / `los_metadata`.

| File | Contents |
| --- | --- |
| [FLASHING-PLAN.md](FLASHING-PLAN.md) | installing LineageOS 18.1 (or crDroid 7.39) on an A2017G: files, checksums, what the installer checks, backups, EDL rescue |
| [BUILD-PLAN-LOS22.md](BUILD-PLAN-LOS22.md) | what porting LineageOS 22.2 (Android 15) takes: a 4.4 kernel port (as gemini / LG msm8996 got), device tree forward-port, blob shims, and a build setup for an 8-thread / 31 GB / 400 GB machine |
| `build/local_manifests/axon7.xml` | repo local manifest for the build |
| [port-22.2/](port-22.2/) | the device tree forward-port to 22.2 (patch series, not built yet) |

ROM zips, recovery images and vendor blobs are not in this repository.
