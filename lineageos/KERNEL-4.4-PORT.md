# Axon 7 on the 4.4 msm8996 kernel: port status

Developer notes for the 4.4 kernel port (milestone 1: the kernel builds with
an Axon 7 device tree and config fragment and is wired into the LineageOS
22.2 tree). **Boots LineageOS 22.2 to the setup wizard (2026-11-07)** through
the shim's LineageOS entry. What it took on the phone:

- ramoops at 0xbfc00000, 4 MiB, with TWRP's and mainline's layout (0006):
  the old 0x92900000 was read by nothing, failed boots left no log.
- smbcharger `fastchg-current-comp = 1200` (0007): ZTE's 900 is from the
  PMI8994 table; the probe failed and the kernel hung at 2.5 s.
- shim (ios `shim/android.c`): bootargs as one string (the kernel saw only
  the DTB's own part, no `androidboot.*`, no panel) and without LK's
  `kpti=1` (the kernel stopped before its first console line).
- device tree 0026-0029: fstab in the boot ramdisk, `los_data` block labels,
  the dsp context mount, battery sysfs labels for the 4.4 paths, a configfs
  USB gadget (4.4 has no `android_usb`).

- Base: `LineageOS/android_kernel_xiaomi_msm8996` `lineage-22.2`
  (4.4.302, HEAD `535079d2fa36`)
- Work tree: `compiler:/srv/port/kernel_axon7-4.4`, branch `axon7`
- In the LineageOS tree: `kernel/zte/msm8996`, local branch `axon7`
  (fetched from the work tree; not pushed anywhere)
- Reference: ZTE/LineageOS 3.18 kernel, `compiler:/srv/port/kernel_zte_msm8996-3.18`

## Commits (branch `axon7`)

A copy of the series is in `kernel-4.4-patches/` (`git am` on LineageOS/android_kernel_xiaomi_msm8996 lineage-22.2 at 535079d2fa36).

| Commit | Subject |
|---|---|
| `73201443d4ae` | ARM: dts: msm8996: Add ZTE Axon 7 (ailsa_ii) device tree |
| `7c32ea97b013` | arm64: configs: Add ZTE Axon 7 config fragment |
| `73752555d840` | input: misc: Add AH1898 hall sensor driver |
| `70af175ef6b9` | usb: typec: Add Pericom PI5USB302 Type-C controller driver |
| `1a02e596d48d` | usb: typec: Add TI HD3SS3220 Type-C controller driver |

Author is the server's git identity for user `build` (`axon7-build <axon7-build@localhost>`).

## What was ported

### Device tree (`arch/arm/boot/dts/qcom/`, `arch/arm64/boot/dts/qcom` is a symlink)

| File | From (3.18) | Content |
|---|---|---|
| `msm8996-v3-pmi8996-zte-axon7.dts` | `zte-msm8996-v3-pmi8996-ailsa_ii.dts` | top level: ids, hall sensor, charger tweaks |
| `msm8996-zte-axon7.dtsi` | ZTE's edited `msm8996-mtp.dtsi` | 4.4 CAF `msm8996-mtp.dtsi` with ZTE's edits applied in place |
| `msm8996-zte-axon7-common.dtsi` | ZTE edits to `msm8996.dtsi`, `-pinctrl`, `msm-pmi8994`, `msm-pm8994`, `-regulator`, `-camera`, `-blsp`, `-pm` | the same changes as overrides; shared dtsi untouched |
| `msm8996-zte-axon7-touch.dtsi` | `touch-key-backlight-ailsa_ii.dtsi` | Synaptics touch + 0D keys, NDT force sensor, vkeys, volume keys |
| `msm8996-zte-axon7-typec.dtsi` | `zte-usb-type-c.dtsi` | HD3SS3220 @0x47 / PI5USB302 @0x0d on BLSP2 QUP1, their GPIO/MPP setup |
| `msm8996-camera-sensor-zte-axon7.dtsi` | `zte-camera-sensor-mtp.dtsi` | 3 cameras, actuators, OIS, ZTE EEPROMs, flash |
| `dsi-panel-zte-samsung-s6e3ha3-5p5-wqhd-dualmipi-cmd.dtsi` | same name | S6E3HA3 dual DSI command panel, verbatim |
| `batterydata-zte-p996a01-3250mah.dtsi` | `zte_p996a01_3250mah.dtsi` | FG battery profile |

Board ids, identical to the 3.18 DTB so ZTE's LK picks it:
`qcom,msm-id = <246 0x30001>`, `qcom,pmic-id = <0x20009 0x2000a 0x0 0x0>`,
`qcom,board-id = <100 0>`.

Things that changed with the 4.4 bindings (check these first if something fails):

- **Panel 3 V rail**: ZTE's 3.18 mdss driver toggled gpio 40 itself
  (`zte,lcd-3v-vsp-enable-gpio`). In 4.4 it is a `regulator-fixed`
  (`lcd_vsp_vreg`, `regulator-boot-on` for the splash) used as the panel
  `vdd` supply of both DSI controllers, entry order vddio then vdd, 5 ms after
  enable and 2 ms after disable (ZTE's delays).
- **Backlight**: DCS (`bl_ctrl_dcs`, 0..255), PMI8994 WLED disabled (as in 3.18).
- **Haptics**: 4.4 `qcom,qpnp-haptics` node (driver `leds-qpnp-haptics`,
  `CONFIG_LEDS_QPNP_HAPTICS`) with ZTE's values (buffer mode, sine, 2668 mV,
  4255 us). The old `CONFIG_QPNP_HAPTIC` driver is disabled; it does not match
  the 4.4 node. ZTE's `clocks = <... clk_cxo_lpm_clk>` was dropped (unused).
- **Touch**: ZTE used its own `synaptics_dsx_zte` driver; the in-tree 4.4
  `synaptics_dsx` (2.6, Xiaomi) reads the same properties
  (`synaptics,pwr-reg-name`, `bus-reg-name`, `irq-flags`, `cap-button-codes`...),
  so the node is unchanged. Keys are 0D buttons (158 BACK, 102 HOME,
  187 APP_SWITCH), matching `device/zte/axon7/keylayout/synaptics_dsx.kl`.
- **Volume keys**: PM8994 GPIO 2 sends KEY_VOLUMEDOWN, GPIO 3 KEY_VOLUMEUP
  (labels in ZTE's DTS are swapped, codes are what 3.18 used).
- **fstab/vbmeta** removed from the DT (first stage mount from the ramdisk
  fstab, as `device/zte/axon7/init/fstab.qcom` expects).
- **HDMI** disabled and `cont_splash_mem_hdmi` deleted (ZTE had sized it 0).
- **pstore/ramoops** at 0x92900000 (the region ZTE already reserved).
- USB3 bus votes: ZTE's second path (master 87) adapted from 3 to the 2 use
  cases of 4.4. Guess, see below.
- WCD9335 (`sound-9335`, `tasha_codec`, `wcd9xxx-irq`) disabled: the board has
  an **AKM AK4961** on slimbus (ZTE removed tasha in 3.18), plus AK4490 DAC,
  AK8157 and ISL98608. Their nodes are in the DT but have no driver yet.

Not taken over on purpose: ZTE's pinctrl hacks that move CoreSight/TDM/TSIF
pin groups to the dummy gpio 131 (those groups are only used on request),
`msm8996-vendor.dtsi` (ZTE vlog/imem/pm-debug), `zte-hall` (its config was
off in LineageOS 3.18), the 3.18 CAF values that 4.4 changed (wipower,
pon debounce, bitbang i2c states).

The structural comparison was done by decompiling both DTBs and diffing node
by node (scripts in the session scratchpad: `dtdiff.py`, `dtcomp.sh` on the
server in `/srv/port/dtref/`). Remaining differences to the 3.18 DTB are the
items listed above and 3.18 to 4.4 CAF changes.

### Config fragment `arch/arm64/configs/vendor/zte/axon7.config`

On top of `vendor/xiaomi/mi8996_defconfig` (as in `BoardConfig.mk`):

- `CONFIG_MACH_ZTE_AXON7=y` (new, `drivers/platform/zte/Kconfig`): the dts
  Makefile then builds only `msm8996-v3-pmi8996-zte-axon7.dtb`.
- `CONFIG_BUILD_ARM64_APPENDED_DTB_IMAGE_NAMES="qcom/msm8996-v3-pmi8996-zte-axon7"`:
  only this DTB is appended to `Image.gz-dtb`, even if stale DTBs are in `out/`.
- Off (Xiaomi-only): `TSPDRV`, `TYPEC_TI_TUSB320`, `LEDS_LP5562`, `NFC_PN548`,
  `SERIAL_NUM`, `HALL_SWITCH`, `TOUCHSCREEN_SYNAPTICS_DSX_FORCE`, `QPNP_HAPTIC`.
- On: `TOUCHSCREEN_SYNAPTICS_DSX{,_I2C,_CORE,_RMI_DEV}` (no FW_UPDATE on purpose,
  to avoid flashing touch firmware), `LEDS_QPNP_HAPTICS`,
  `SENSORS_HALL_AH1898`, `USB_TYPEC`, `USB_PI5USB302`, `USB_HD3SS3220`.
- Still enabled from the base and selected by `SND_SOC_MSM8996` (cannot be
  turned off without editing Kconfig): TFA98xx, TAS2555, OPA1622, LM48560,
  WCD9335. They match no Axon 7 DT node and stay idle.
- Wi-Fi: QCA6174 over PCIe via `CNSS` + `QCA_CLD_WLAN`, same as gemini, from the base.
  SMB1351 parallel charger: in-tree `qcom,smb1351-charger`, node as in 3.18.

### Drivers ported (small, self-contained)

| Driver | 4.4 path | 3.18 path | Notes |
|---|---|---|---|
| AH1898 hall sensor | `drivers/input/misc/ah1898.c` | same | SW_LID only (ZTE keycodes and Synaptics smart-cover hook dropped), cleaned up |
| PI5USB302 Type-C | `drivers/usb/typec/pi5usb302.c` | `drivers/usb/typec/pi5usb302.c` | the chip on this unit; bug fixes, matches `pericom,pi5usb302` |
| HD3SS3220 Type-C | `drivers/usb/typec/hd3ss3220.c` | same | other board variant; same fixes; the smbcharger hook `interfere_id_irq_from_usb()` is a logging stub |

## Building the kernel alone

On `compiler`, as user `build`, with the LineageOS prebuilts (same variables
as LineageOS `kernel.mk`; script `/srv/port/kbuild.sh`, `-s SRC -o OUT -j N`):

```sh
cd /srv/port
./kbuild.sh vendor/xiaomi/mi8996_defconfig vendor/zte/axon7.config
./kbuild.sh Image.gz-dtb
./kbuild.sh dtbs
```

Defaults: source `/srv/port/kernel_axon7-4.4`, output `/srv/port/kout`, `-j6`,
`CCACHE_DIR=/srv/aosp/.ccache` (`~build/.cache/ccache` is a stray empty file,
so the ccache default dir does not work for user `build`).

Result of the last build (2026-11-06, clang r536225, `LLVM=1 LLVM_IAS=1`):

- `/srv/port/kout/arch/arm64/boot/Image.gz-dtb`: 12,031,557 bytes
  (`Image.gz` plus exactly one appended DTB of 393,639 bytes)
- `/srv/port/kout/arch/arm64/boot/dts/qcom/msm8996-v3-pmi8996-zte-axon7.dtb`
  (the only DTB built)
- No errors. No warnings from the new files (the remaining compiler warnings
  are in existing code: tfa98xx, qcacld, camera_v2, bfq).
- Appended DTB checked with `fdtdump` (built from `scripts/dtc`, in
  `/srv/port/dtref/fdtdump`): `qcom,msm-id = <0xf6 0x30001>`,
  `qcom,pmic-id = <0x20009 0x10013 0x0 0x0>`, `qcom,board-id = <0x64 0x0>`,
  identical to the 3.18 ailsa_ii DTB. (`msm-pmi8996.dtsi` sets the second
  pmic-id word to PMI8996, `0x10013`, in both kernels.)

Stale DTBs in a reused `out/.../KERNEL_OBJ` (the warm-up build left CAF
DTBs there) are not appended, because of `..._APPENDED_DTB_IMAGE_NAMES`.

In the LineageOS tree: `m bootimage` (kernel source `kernel/zte/msm8996`,
branch `axon7`). A `repo sync` resets that project to the manifest revision;
re-run `git checkout axon7` there afterwards (or add the branch to the local
manifest once it is pushed somewhere).

## Missing drivers

Porting notes (2026-11-08): the AK4961 needed the 4.4 ASoC API (no codec
register cache, `snd_soc_dapm_to_codec`, `snd_soc_card_jack_new`) and ZTE's
`msm_is_in_voice_call()` in `msm-pcm-routing-v2`; the machine driver replaces
`msm8996.c`. `zte_eeprom` needed an empty GPIO table for nodes without `gpios`
(the probe oopsed in `kernel_init` and the boot hung). The AK4961 control
port is SPI on BLSP2 QUP3: gpio 50 had been nullified in the Xiaomi pin table
(restored, 0016); the AK49xx irq domain is made at probe, since
`IRQCHIP_DECLARE` does not run below the TLMM platform driver (0018); the
card's Compress9 link uses MultiMedia16, which is a PCM front end on 4.4
(0020).

Sizes are from the 3.18 tree. "Needed for" says what stays broken without it.

| Prio | Driver | 3.18 path | Size | What it is / needed for |
|---|---|---|---|---|
| ported (0014-0020): card registers | AK4961 codec + AK49xx MFD core | `sound/soc/codecs/ak4961*.c`, `drivers/mfd/ak49xx-{core,irq,slimslave,core-resource}.c`, `drivers/irqchip/irq-msm.c` | ~8.1k + 3.5k lines (240 KB + 90 KB) | the main audio codec on slimbus (there is **no WCD9335**): speaker, earpiece, mics, headset |
| ported (0014, 0020): card registers | AK4961 machine driver | `sound/soc/msm/msm8996-ak496x.c` | 3.5k lines | sound card `msm8996-ak4961-snd-card`; must be rebased onto the 4.4 `msm8996.c`/q6 APIs |
| ported (0019) | AK4490 DAC, AK8157 PLL, ISL98608 | `sound/soc/codecs/ak4490/` | 2.1k lines | Hi-Fi headphone path |
| ported (0008, 0010): /dev/goodix_fp, gx_fpd runs | Goodix GF3118M fingerprint | `drivers/input/fingerprint/goodix/` | ~1k lines | fingerprint (TEE based; node `goodix,fingerprint`) |
| ported (0009, 0012): OTP/calibration read by the camera daemon | ZTE camera EEPROM | `drivers/media/platform/msm/camera_v2/sensor/eeprom/zte_eeprom.c` | 1.8k lines | OTP/calibration of the 3 sensors (`zte,eeprom-*`) |
| ported (0021, 0022): rear sensor probes, testing | ZTE camera UAPI (`msm_cam_sensor.h`, `msm_camsensor_sdk.h`) and the handlers that use it | `include/uapi/media/`, `camera_v2/sensor/{msm_sensor,actuator,ois,flash}` | headers + ~400 lines | ZTE's camera blobs use ZTE's 3.18 ioctl layout (CFG_POWER_RESET, actuator/OIS register access, `VIDIOC_MSM_FLASH_HW_ID`); with the stock 4.4 layout the rear camera reports no picture sizes |
| ported (0023) | power key debounce | `msm-pm8994.dtsi` (ZTE: `qcom,pon-dbc-delay = <15625>`, `qcom,kpdpwr-sw-debounce`) | DT | the LineageOS dtsi asks for software debouncing that this PON driver lacks, leaving 62 us: phantom power key presses |
| 2 | ZTE camera IO helpers | `.../camera_v2/sensor/zte_io/` | 21 KB | OIS/actuator helpers used by ZTE's camera stack |
| ported (0013): NFC on | PN5xx NFC | `drivers/nfc/pn5xx_i2c.c` | 772 lines | NFC; the HAL opens `/dev/pn5xx`. Alternative: in-tree `nq-nci` or Xiaomi `pn548` with a binding change plus HAL config |
| 2 | ZTE smbcharger/FG/PON changes | `drivers/power/qpnp-smbcharger.c`, `qpnp-fg.c`, `qpnp-power-on.c` (C457 "Import ZTE A2017G Oreo release changes") | patch set | ZTE charging policy, `vchg`, `design_capacity`, `interfere_id_irq_from_usb()` for HD3SS3220 |
| 3 | ZTE misc | `drivers/power/zte_misc.c` | 650 lines | hw version (imem `hw_ver_id`), battery id helpers; built unconditionally in 3.18 |
| 3 | NDT force sensor | `drivers/input/touchscreen/ndt_stress.c` | 2.3k lines | "pressure" sensor on the touch bus, probably not fitted on all boards |
| 3 | ZTE virtual keys | `drivers/input/touchscreen/gen_vkeys_zte.c` | 243 lines | only needed if the keys are 2D virtual keys; they are 0D buttons |
| 3 | ZTE Synaptics driver | `drivers/input/touchscreen/synaptics_dsx_zte/` | 12.7k lines | not needed if the in-tree `synaptics_dsx` works; has ZTE extras (smart cover, gestures) |
| 4 | zte-hall, zte_pm_debug, vlog | `drivers/power/zte-hall.c`, vendor dtsi | small | not enabled in LineageOS 3.18 either |

The touch-key backlight: the 3.18 file `touch-key-backlight-ailsa_ii.dtsi`
has no backlight node (only touch, vkeys, volume keys), so nothing to port.

## What to test first on the phone

1. Boot it through the shim's LineageOS entry, not `fastboot boot` (ZTE's LK
   has no `fastboot boot`): convert with `ios/tools/axon7-androidimg.py
   convert` (raw Image + DTB section, the shim cannot gunzip) and write it to
   `los_boot` (LUN 0, writable from postmarketOS). If it does not come up,
   reboot to TWRP and read `/sys/fs/pstore/console-ramoops*` (pstore at
   0xbfc00000, the same as TWRP and postmarketOS). Note: the shim picks the DTB by msm-id/board-id
   (0xf6/0x30001, 0x64/0) and copies /memory and bootargs as described in
   `ios/shim/android.c`.
2. Display: splash should stay on (cont-splash). Check `dmesg | grep -i mdss`,
   that `lcd_vsp_3v` is enabled and the panel `zteSAM_S6E3HA3...` is found;
   brightness changes (DCS).
3. UFS/storage and first stage mount (`androidboot.boot_devices=soc/624000.ufshc`).
4. Touch (`synaptics_dsx` probe, 0D keys), volume keys, power key.
5. USB: adb, charging (smbcharger + SMB1351, FG with the 3250 mAh profile),
   `dmesg | grep pi5usb302`, `/sys/class/type-c/chip/`, OTG.
6. Wi-Fi (cnss/qcacld, firmware path), Bluetooth (QCA6174 BT_EN on PM8994 GPIO 19).
7. Modem/ADSP/SLPI firmware loading (reserved memory map is identical to 3.18).
8. Vibrator (`/sys/class/leds/vibrator`), LEDs, hall sensor (`ah1898` input, SW_LID).
9. Sensors, camera, audio come after the missing drivers.

## Unsure / guessed

- Panel power: gpio 40 as `regulator-fixed` with `regulator-boot-on`; the
  3 V value is a label only. If the panel blanks at boot, check this first.
- `vdd-supply` on both DSI controllers (3.18 had the gpio on DSI0 only).
- USB3 second bus path (master 87) adapted to two use cases.
- Haptics property mapping to the new driver (`lra-high-z`, `auto-res-mode`).
- `hall_sensor` got the ZTE `zte_hall_gpio_active` pin state as `default`
  (3.18 left the pin at its reset state).
- MPM wakeup map: only GIC 137 had to be added (129 is already in 4.4).
