# Modem restart loop: first probe round (2026-11-21)

Investigation on the MAIN phone (`7e15695a`, LineageOS 24, `adb root`), using
**only modem remoteproc0 stop/start** (never ADSP/SLPI). All logs here are from
that day; no EFS/modemst partitions were written.

## What the modem reports

Every fatal error in the captured dmesg files is the same:

```
qcom-q6v5-mss 2080000.remoteproc: fatal error received: SFR Init: wdog or kernel error suspected.
remoteproc remoteproc0: crash detected ... type fatal error
```

The interval from `remote processor ... is now up` to the fatal is 41-42 s,
i.e. a watchdog timeout in the MPSS boot/init phase, not a host-side QMI
failure. `probe-rmtfs-ro/online/online-1-dmesg.txt` has 10 such crashes in
~400 s; the DMS service only appeared at 371 s after the manual modem start.

## What was changed between probes

The image starts `/vendor/bin/rmtfs -o /dev/block/by-name -P -r -s`. In this
tree's `qcom/rmtfs/storage.c`, `-r` keeps EFS writes in a **per-caller RAM
shadow** and `storage_sync()` is a no-op. A modem restart changes the QRTR
node/caller, so rmtfs reopens the EFS files and all writes made by the previous
MPSS instance are lost. A modem that expects an EFS update to survive its own
restart would then repeat the same init failure.

| probe | rmtfs | modem start | result |
|---|---|---|---|
| `probe-rmtfs-ro/offline`, `online` | image's `-r -s` | by rmtfs (`-s`) | 0-10 fatals per 77-414 s window |
| `probe-rmtfs-shadow` | `-o /data/vendor/axon7m-efs -v` (writable copies of the four EFS images in `/data`, no `-r`, no `-s`) | by hand | **0 fatals in 3 x 70 s** |

The shadow probe is only a hint so far: it also dropped `-P` and `-s` and
started the modem by hand, so the next step must isolate the variables.

## Tools left here

* `tools/qmi-failure.c` - SSCTL `GET_FAILURE_REASON` (service 43, instance
  family 0x12xx, cmd 0x22) reader; built as a static aarch64 binary (not
  committed). Not run successfully yet: the first adb invocation hung waiting
  for the shared phone lock.
* `tools/tqftpserv/` - Linaro's BSD-3-Clause tqftpserv source, copied for
  adding a request-path log; the built binary is not committed.
* The `modem-*.sh` scripts are the probe scripts used on the phone.

Nura reference logs: `ios/research/phone2/kernel-r27/mss-crash*.txt` and
`modem-bisect.txt` (0-2 crashes per boot on Nura, i.e. no 9-minute loop).
