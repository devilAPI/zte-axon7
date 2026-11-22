# NFC on the Axon 7 mainline kernel (LineageOS 24)

## Two owners for one PN548

The phone has one NXP PN548 at I2C 0x28 (`blsp2_i2c2`, IRQ TLMM 9, VEN TLMM
12, firmware download TLMM 96). Mainline `nxp-nci_i2c` owns that node and
implements the kernel NFC stack (`/sys/class/nfc/nfc0`, generic netlink), which
Nura uses. Android's NFC app instead needs an NXP-style character device with
the `PN5XX_SET_PWR` ioctl and raw NCI frames over I2C.

The Nura kernel patch series therefore adds `drivers/nfc/pn5xx-raw.c`
(`CONFIG_NFC_PN5XX_CHAR`). It is compiled into both OSes' kernels but does
nothing unless the `pn5xx_raw=1` kernel parameter is given:

* **Nura:** parameter absent -> the driver does not register an `i2c_driver`;
  `nxp-nci_i2c` binds as before and `nfc0` works.
* **LineageOS 24:** `AXON7_NFC=1` adds `pn5xx_raw=1` to `BOARD_KERNEL_CMDLINE`.
  The built-in driver binds the *same* DT node before the `nxp-nci_i2c` module
  is loaded from `/vendor`, and exposes `/dev/nq-nci` (plus `/dev/pn5xx` and
  `/dev/pn54x` for older HAL configs). No second node at 0x28 and no DT
  compatible change are needed.

## Userspace files here

| File | Purpose |
| --- | --- |
| `libnfc-nci.conf` | AOSP android-17 PN548 NCI stack settings (`NFA_STORAGE=/data/nfc`) |
| `libnfc-nxp.conf` | AOSP PN548AD settings; `NXP_NFC_DEV_NODE=/dev/nq-nci`, chip `0x03`, firmware `libpn548ad_fw.so` (must come from the phone's own /vendor) |
| `manifest_nfc.xml` | AIDL `android.hardware.nfc` + `vendor.nxp.nxpnfc_aidl` HAL fragments |
| `init.axon7m.nfc.rc` | Creates `/data/nfc` for the HAL; the HAL service itself comes from AOSP's `nfc-service-nxp.rc` |
| `ueventd.axon7m.rc` (in `../init/`) | `0660 nfc nfc` for the three device aliases |

`device.mk` installs these only with `AXON7_NFC=1`, together with the `Nfc`
app, the AIDL HAL and the NFC feature XML.

## Status (2026-11-21)

* Kernel side: raw driver written and built; the generic-netlink path was
  proven on the main phone with `tools/axon7-nfc-netlink.c` (`DEV_UP`,
  `START_POLL`, `STOP_POLL`; NCI 1.1, manufacturer id 0x4). On 2026-11-22 the
  char path was proven too, without a reboot: `pn5xx-raw.ko` inserted into
  the running LOS kernel produced `/dev/nq-nci`, `/dev/pn5xx`, `/dev/pn54x`
  and answered `NCI_CORE_RESET` (`40 00 03 00 11 00`) and `NCI_CORE_INIT`
  (`40 01 19 00 03 1e ...`) through `PN5XX_SET_PWR` (log
  `nfchal-logs/nfchal-char-module-20261122T192548Z.log`). With NCI-frame-sized
  reads the retest returned exactly 6 and 28 bytes
  (`nfchal-logs/nfchal-char-module-20261122T200145Z.log`). `nfc0` was rebound
  afterwards.
* Android side: **not buildable yet**. At `android-17.0.0_r1`
  `hardware/nxp/nfc/Android.bp` only builds the SNxxx (SN1xx/SN220/SN300)
  AIDL HAL; the PN548 implementation (`pn8x/`) is no longer in the build and
  the firmware binary is proprietary. Enabling the switch in a release
  requires porting that HAL/config (or a netlink-to-AIDL NFC HAL) first.
  Nothing here is enabled in default builds; `dumpsys nfc` has not shown an
  enabled NFC service.
