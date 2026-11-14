# Modem bring-up (LineageOS 24)

- `rmtfs/`, `qrtr/`: from AOSP's `device/linaro/dragonboard` (`shared/utils/`),
  BSD-3-Clause (see their LICENSE files). rmtfs serves the modem's EFS from
  the `modemst1/2`, `fsg`, `fsc` partitions and starts the modem remoteproc
  (`-s`). This device runs it **read-only** (`-r`): the modem's writes are
  discarded, the partitions are never written (PLAN.md partition rules).
  libqrtr and `qrtr-lookup` (diagnostics) come along; the name service is in
  the kernel (no `qrtr-ns`).
- `modem-online/`: switches the modem to operating mode online over QMI DMS,
  the job of Nura's `axon7-modem` (which uses qmicli).
