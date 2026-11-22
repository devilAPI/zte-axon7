# Installing build 52 with the EFS shadow (2026-11-22)

Main phone `7e15695a`, build 52 (`ios/research/los24-build-52`, boot sha256
`902ccf84...`, super sha256 `5e91d7c5...`, both verified after fetch).
The first attempt only reached TWRP and aborted while verifying the boot copy
because TWRP has no `sha1sum`; no partition was written. The helper now reads
the partition back and hashes it on the PC.

Successful install (`install-52-20261122-2102/`):

* `los_boot` was **read only**, saved to the HDD and verified twice:
  sha1 `ed5bed8f1f3c935f0e34b9dd51969cdfc2d1472c`, 100663296 bytes.
  No boot image or boot menu was written; only `super.img` went to the
  `system` partition (`/dev/block/sde13`), as 157 MiB delta against build 51,
  with every data extent read back and checked.
* After reboot, `sys.boot_completed=1` in 78 s, battery 98 %.
* `pgrep -a rmtfs`: `621 /vendor/bin/rmtfs -o /data/vendor/axon7m-efs -s`.
  The four EFS shadow files exist (`modem_fs1/2`, `modem_fsg`, `modem_fsc`,
  660, root:root). The real EFS partitions were not written.
* `remoteproc0` = `2080000.remoteproc` (MODEM), state `running`;
  0 `fatal error received` and 0 `SFR Init` lines in dmesg at that point.
* Phone left in LineageOS with adb, `svc power stayon false`.

Next: 15 consecutive real boots with Bluetooth on/off cycles
(`bt-cycles-r3.log`).
