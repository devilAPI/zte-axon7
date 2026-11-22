# Modem + Bluetooth: 15 consecutive real boots (2026-11-22)

Main phone `7e15695a`, LineageOS 24 userdebug **build 52** (EFS-shadow image),
kernel `#31 SMP PREEMPT Fri Nov 20 01:58:00 CET 2026`. Battery 98-99 %,
USB connected, `adb root`, no sound and no vibration. Only `remoteproc0`
(`2080000.remoteproc`, MODEM) is started by rmtfs; ADSP/SLPI were not
touched. The real EFS partitions (`modemst1/2`, `fsg`, `fsc`) were only read
once by init when the `/data` shadow was created; no EFS or boot partition was
written by this test.

Run: `bt-boot-cycles-r5.sh` under `flock ~/.cache/axon7-phone-7e15695a.lock`,
raw output in `bt-cycles-r5-20261122-2120/` (`host.log`, `summary.txt`,
`cycle-N-info.txt`, `cycle-N-dmesg*.txt`, `final.txt`). The raw dmesg files are
kept on disk but **not committed**: Wi-Fi scan output can contain network
names/MACs.

## What changed in build 52

`axon7m-efs-shadow.sh` (from `9c81a2e`) copies the four EFS images to
`/data/vendor/axon7m-efs` once at `post-fs-data` (never overwriting an existing
copy); `rmtfs` now runs `-o /data/vendor/axon7m-efs -s`, serving writable
files instead of the RAM-only `-r` shadow. Previously, a modem restart changed
the QRTR caller and rmtfs dropped all EFS writes made by the previous MPSS
instance, after which MPSS repeated
`fatal error received: SFR Init: wdog or kernel error suspected` every 41-42 s
for up to ~9 min (10 crashes in one probe). A controlled A/B with manual
restarts on a warm modem (`RESULTS-r3.md`) could not reproduce the loop in any
rmtfs mode, so the verification had to use real boots.

## Evidence: 15 boots, one Bluetooth on/off cycle per boot

Each boot was checked for a new `/proc/sys/kernel/random/boot_id` and
`sys.boot_completed=1`; the script stopped on the first failure. `Fatal/SFR`
counts are `fatal error received` / `SFR Init` lines in a freshly cleared
dmesg, plus the count after enabling Bluetooth. `HCI fail` counts
`Opcode 0x0c03 failed`, `hci0: ... -110` and `QCA no reset answer`. The 15
boot IDs are distinct (15 unique values).

| Boot | boot_id | Battery | EFS files | Modem | Fatal/SFR | HCI fail | BT state |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `0d794f84…` | 99% | 4 | running | 0/0 (0 after BT) | 0 (0 after BT) | ON |
| 2 | `2babcdc4…` | 98% | 4 | running | 0/0 (0 after BT) | 0 (0 after BT) | ON |
| 3 | `e960f480…` | 98% | 4 | running | 0/0 (0 after BT) | 0 (0 after BT) | ON |
| 4 | `4de22ee3…` | 98% | 4 | running | 0/0 (0 after BT) | 0 (0 after BT) | ON |
| 5 | `0b51cc38…` | 99% | 4 | running | 0/0 (0 after BT) | 0 (0 after BT) | ON |
| 6 | `575422f1…` | 98% | 4 | running | 0/0 (0 after BT) | 0 (0 after BT) | ON |
| 7 | `5dcf503c…` | 98% | 4 | running | 0/0 (0 after BT) | 0 (0 after BT) | ON |
| 8 | `4495d82d…` | 98% | 4 | running | 0/0 (0 after BT) | 0 (0 after BT) | ON |
| 9 | `af804c5c…` | 98% | 4 | running | 0/0 (0 after BT) | 0 (0 after BT) | ON |
| 10 | `f3f4778d…` | 98% | 4 | running | 0/0 (0 after BT) | 0 (0 after BT) | ON |
| 11 | `8dc71c50…` | 98% | 4 | running | 0/0 (0 after BT) | 0 (0 after BT) | ON |
| 12 | `f244a3bc…` | 98% | 4 | running | 0/0 (0 after BT) | 0 (0 after BT) | ON |
| 13 | `ebe64654…` | 98% | 4 | running | 0/0 (0 after BT) | 0 (0 after BT) | ON |
| 14 | `ba8404c2…` | 98% | 4 | running | 0/0 (0 after BT) | 0 (0 after BT) | ON |
| 15 | `050901fd…` | 98% | 4 | running | 0/0 (0 after BT) | 0 (0 after BT) | ON |

An independent grep over all 15 saved `cycle-N-dmesg.txt` files found **0**
lines matching `crash detected|fatal error received|SFR Init|remoteproc0:
crash|qcom-q6v5-mss.*error`. The `QCA reset after the address change` path of
kernel 0021 was not needed in any of these boots (0 occurrences); kernel 0021
is kept as protection for the boot-time address-change race seen earlier.

## Final phone state

After cycle 15: `sys.boot_completed=1`, `boot_id=050901fd-…` (same as cycle
15), battery 98 %, remoteproc0 `running`, `rmtfs -o /data/vendor/axon7m-efs
-s`, `State: OFF` (the loop disables Bluetooth after each check),
`stay_on_while_plugged_in=0`, adb reachable. `los_boot` was only read; sha1
`/dev/block/sda10` = `ed5bed8f1f3c935f0e34b9dd51969cdfc2d1472c`, unchanged
from before the install (see `RESULTS-install-52.md`).
