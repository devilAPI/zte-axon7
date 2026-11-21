# Fingerprint on mainline: feasibility (ZTE Axon 7)
# docs/fingerprint-feasibility.md

Date: 2026-11-21

## 1 Summary

Verdict: Fingerprint is not possible on mainline Linux 7.3.1 for the ZTE Axon 7 (A2017G, msm8996) with current knowledge.

Confidence: medium. No experiment has been run yet; section 6 lists the ones that decide it.

Reason: The stock fingerprint flow depends on a TrustZone (TZ) application and proprietary blobs that are loaded via `/dev/qseecom`. Mainline’s `qcom_scm` driver exposes only `app_get_id` and `app_send` and restricts access to a small allowlist of Snapdragon laptops. There is no mechanism in mainline to load the Goodix TZ app or its blobs, and the SPI bus is owned by the SSC/TZ subsystem.

## 2 Hardware

- Sensor: Goodix fingerprint sensor (DT compatible: "goodix,fingerprint").
- SPI bus: The sensor is connected via an SSC (Snapdragon Sensor Core, the sensor DSP that mainline runs as the SLPI remoteproc) port. The DT node `qcom,qbt1000` defines:
  - `qcom,spi-port-id = <2>`
  - `qcom,spi-port-slave-index = <0>`
  - `qcom,tz-subsys-id = <1>`
  - `qcom,ssc-subsys-id = <5>`
- GPIOs (from DT):
  - Power: `goodix,gpio_pwr = <&tlmm 85 0>`
  - Reset: `goodix,gpio_reset = <&tlmm 39 0>`
  - ID: `goodix,gpio_id = <&tlmm 21 0>`
  - IRQ: `goodix,gpio_irq = <&tlmm 123 0>`
- Clock: `spi-max-frequency = <4800000>` in DT.

## 3 How stock works

- Kernel driver: `gf_spi` (platform driver).
  - Responsibilities: power, reset, IRQ, clock enable.
  - Does not read/write biometric data.
- Data path:
  - Image data and commands go through the TrustZone application.
  - The TZ app is invoked via `/dev/qseecom` using QSEECOM commands.
- User space:
  - Proprietary blobs: `gx_fpd`, HAL (`fingerprint.msm8996.so`), and supporting libs.
  - The HAL loads the TZ app through `/dev/qseecom`.
  - Binder policy (`hal_fingerprint_default.te`) allows the HAL to talk to the TZ app and access the TEE device.

## 4 What mainline offers

- Driver: `qcom_scm` with QSEECOM support.
- Exposed functions:
  - `qcom_scm_qseecom_app_get_id(name)`
  - `qcom_scm_qseecom_app_send(id, req, rsp)`
- Limitations:
  - No app loading from Linux. Apps must be preloaded by the bootloader/firmware.
  - Access is gated by an allowlist of known devices (currently Snapdragon laptops).
  - No `/dev/qseecom` node exposed in mainline for general use.
  - The driver logs “untested machine, skipping” for devices not in the allowlist.

## 5 Options with effort and risk

A) Port a QSEECOM app-loading interface to mainline for msm8996 TZ and run the stock Goodix TZ app + blobs on LineageOS 24.
   - Effort: High. Requires:
     - Extending or bypassing the allowlist in `qcom_scm_qseecom_allowlist`.
     - Implementing or exposing an app-loading path (e.g., via a custom QSEECOM command or bootloader hook).
   - Risk:
     - TrustZone security model may prevent arbitrary app loading from Linux.
     - Proprietary blobs may not run cleanly on mainline userspace.

B) Take the SPI bus away from TZ/SSC.
   - Effort: High.
   - Risk: Very high. The DT and SSC configuration indicate the port is protected by TZ. Removing it likely breaks other secure subsystems and may be blocked by hardware design.

C) Nothing / document as not possible.
   - Effort: Low.
   - Risk: Low.
   - Outcome: Fingerprint remains unavailable on mainline; users who need it use LineageOS 22.2 (4.4 kernel).

## 6 Smallest experiments that decide each option

1. Verify QSEECOM interface presence:
   - Build a test kernel module that calls `QSEECOM_TZ_CMD_INFO_VERSION` via `qcom_scm_qseecom_get_version`.
   - Temporarily add `"zte,axon7"` to `qcom_scm_qseecom_allowlist`.
   - Log the returned version.
   - Decision: If version is returned, the interface exists and can be used.

2. Check app-loading capability:
   - Attempt `qcom_scm_qseecom_app_get_id` with the known Goodix TZ app name.
   - Decision: If it returns a valid app ID, the app is already loaded or loadable via QSEECOM.

3. Confirm SPI controller responsiveness:
   - From Linux, probe the SSC SPI port (port-id 2, slave-index 0) using a minimal SPI driver or `spidev`.
   - Decision: If the controller responds, the bus is accessible; if not, TZ/SSC is actively gating it.
   - Warning: the SPI port belongs to the SLPI/SSC; never stop or restart the SLPI remoteproc (it freezes the SoC on mainline). Read-only probing only.

4. Evaluate allowlist bypass:
   - Temporarily extend the allowlist and boot mainline.
   - Check if `qcom_scm_qseecom_init` proceeds past “untested machine, skipping”.
   - Decision: If it proceeds, the driver is ready for QSEECOM operations on this device.

If experiments 1 and 4 succeed but 2 fails, the path is: implement app loading (Option A). If 3 fails, Option B is likely impossible. If 1 fails, QSEECOM is not usable on this device in mainline.
