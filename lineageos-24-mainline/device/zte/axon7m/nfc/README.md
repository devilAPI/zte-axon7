# NFC on the Axon 7 mainline kernel (LineageOS 24)

## Two owners for one PN548

The phone has one NXP PN548 at I2C 0x28 (`blsp2_i2c2`, IRQ TLMM 9, VEN TLMM
12, firmware download TLMM 96). Mainline `nxp-nci_i2c` owns that node and
implements the kernel NFC stack (`/sys/class/nfc/nfc0`, generic netlink), which
Nura uses. Android's NFC app instead needs an NXP-style character device with
the `PN5XX_SET_PWR` ioctl and raw NCI frames over I2C.

The kernel patch series therefore adds `drivers/nfc/pn5xx-raw.c`
(`CONFIG_NFC_PN5XX_CHAR`, LOS patch `0022`). It is compiled into the LOS
kernel but does nothing unless the `pn5xx_raw=1` kernel parameter is given:

* **Nura:** parameter absent -> the driver does not register an `i2c_driver`;
  `nxp-nci_i2c` binds as before and `nfc0` works.
* **LineageOS 24:** `AXON7_NFC=1` adds `pn5xx_raw=1` to `BOARD_KERNEL_CMDLINE`.
  The built-in driver binds the *same* DT node before the `nxp-nci_i2c` module
  is loaded from `/vendor`, and exposes `/dev/nq-nci` (plus `/dev/pn5xx` and
  `/dev/pn54x` for older HAL configs). No second node at 0x28 and no DT
  compatible change are needed.

## Why a own AIDL HAL (not NXP's SNxxx HAL)

Decision made 2026-11-22, evidence in `PLAN.md`:

* At `android-17.0.0_r1`, `hardware/nxp/nfc/Android.bp` builds only the
  SNxxx (SN1xx/SN220/SN300) AIDL HAL; the PN548 implementation in `pn8x/`
  is HIDL 1.x and not in the build. Its HAL downloads NXP firmware over the
  DNLD GPIO, which this PN548 does not need (it answers NCI 1.1 on its own).
* AOSP's own stack, `packages/modules/Nfc/libnfc-nci`, already implements NCI
  1.x, RF discovery and tag handling. `NfcAdaptation.cc` connects to the AIDL
  service `android.hardware.nfc.INfc/default`, sends NCI commands via
  `INfc::write()` and receives responses via `INfcClientCallback::sendData()`.
* The raw char driver is proven on the main phone (2026-11-22): NCI
  `CORE_RESET` (`40 00 03 00 11 00`) and `CORE_INIT` (28-byte response,
  status 0) over `/dev/nq-nci` with `PN5XX_SET_PWR(1)`.

So `Nfc.cpp` is a small HAL that owns only the device and the power ioctl:
`open()` powers up and starts a read thread, `write()` sends NCI frames,
`close()` powers down, `coreInitialized()`/`preDiscover()`/`powerCycle()`
send the callbacks the stack waits for. There is no firmware download, no
vendor extension and no NXP blob. `libnfc-nci.conf` supplies the stack's
settings; `libnfc-nxp.conf` is kept for reference but not installed.

## Files here

| File | Purpose |
| --- | --- |
| `Nfc.cpp`, `Android.bp` | `android.hardware.nfc-service.axon7m`, the AIDL HAL |
| `nfc-service-axon7m.rc` | starts the HAL as `vendor.nfc_hal_service` (exec label `hal_nfc_default_exec`) |
| `libnfc-nci.conf` | AOSP android-17 NCI stack settings (`NFA_STORAGE=/data/nfc`) |
| `libnfc-nxp.conf` | historical PN548AD config (not installed, NXP HIDL only) |
| `manifest_nfc.xml` | AIDL `android.hardware.nfc` V2 fragment (compiled into the HAL) |
| `init.axon7m.nfc.rc` | creates `/data/nfc`; from `device.mk` with the feature XML |
| `../init/ueventd.axon7m.rc` | `0660 nfc nfc` for the three device aliases |
| `../sepolicy/vendor/` | labels the device and HAL binary; allows HAL -> `nfc_device` |

`device.mk` installs the HAL, the NFC app, the feature XML and the config
only with `AXON7_NFC=1`; normal builds are unchanged.

## Status (2026-11-22)

* Kernel side: raw driver proven as a module in the running LOS #31 kernel
  and added to the LOS kernel patches as `0022` (not yet built into a boot
  image here).
* HAL: the Soong module builds cleanly (`m -j4
  android.hardware.nfc-service.axon7m`, exit 0, 2026-11-23). The bind-mount
  test on the main phone passed the same day: with the raw module inserted,
  NfcService connected at AIDL ver 2, opened `/dev/nq-nci`, `dumpsys nfc`
  went from `mState=off` to `mState=on` (`svc nfc enable`) with five RF
  discovery configs and an NCI `START_DISCOVERY_CMD` in the snoop, then
  back to off (`svc nfc disable`). Evidence: `logs/nfc-aidl-20261123T023645Z*/`.
  The test needs a temporary feature bind mount and a test-only VINTF
  shim because the running #31 image was built with `AXON7_NFC=0`; an
  `AXON7_NFC=1` image installs the feature and manifest itself and needs
  its own test before CI enables it. Default builds keep `AXON7_NFC=0`.
