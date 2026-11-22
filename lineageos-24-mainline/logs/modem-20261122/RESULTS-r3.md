# Modem EFS A/B isolation, 2026-11-22 (round 3)

Main phone `7e15695a`, LineageOS 24 build 51, `adb root`, battery 99 %.
Only `remoteproc0` (`2080000.remoteproc`, MODEM) was stopped/started; ADSP and
SLPI were never touched. The real `modemst1/2`, `fsg` and `fsc` partitions were
only read (copied into `/data/vendor/axon7m-efs`); no EFS write and no
boot-partition write happened. No sound or vibration.

`efs-shadow-ab.sh`, results in `results-20261122-1954/`:

| rmtfs mode | rounds | fatal errors (SFR Init) | modem state |
|---|---|---|---|
| `-o /dev/block/by-name -P -r -s` (image's read-only shadow) | 3 x 75 s | 0 / 0 / 0 | running |
| `-o /data/vendor/axon7m-efs -s` (writable shadow) | 3 x 75 s | 0 / 0 / 0 | running |
| `-o /data/vendor/axon7m-efs -r` (read-only shadow) | 3 x 75 s | 0 / 0 / 0 | running |

At the end the image's own rmtfs was restored and verified:
`2620 /vendor/bin/rmtfs -o /dev/block/by-name -P -r -s`, modem `running`.

**Interpretation:** this A/B does *not* isolate `-P`, `-r` or `-s`: a warmed-up
modem restarted by hand does not reproduce the boot-time loop in any mode,
including the exact configuration that produced 10 crashes in the
2026-11-21 probe (`probe-rmtfs-ro/`, fatals every 41-42 s, DMS only after
371 s). The writable-shadow probe there had 0 fatals in 3 x 70 s. The loop is
therefore a boot-time race, not a generic restart failure; the EFS shadow fix
still has to be verified over consecutive real boots of an image that contains
it. Raw dmesg of these rounds is deliberately not committed (Wi-Fi scan logs
can contain network names); only the counts above are kept.

Baseline on the same build before any image change: `svc bluetooth enable`
-> `State: ON` in 3 s, 0 `QCA reset after the address change`, 0
`Opcode 0x0c03 failed`, 0 modem fatals; Bluetooth was disabled again and
`svc power stayon false` run. Phone left in LineageOS with adb.
