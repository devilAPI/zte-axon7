# ZTE Axon 7 (A2017G) hardware reference

Everything here was read from a real A2017G (64 GB / 4 GB RAM, codename
`ailsa_ii` / `axon7`): the downstream device tree of the TWRP 3.3.0-0 kernel
(Linux 3.18), register dumps taken by our own boot shim, and boot tests.
Items marked *unverified* come from the downstream device tree only and
have not been confirmed on hardware yet.

## SoC and memory

| Item | Value |
| --- | --- |
| SoC | Qualcomm MSM8996 v3 (Snapdragon 820), DT model "MSM 8996 v3 + PMI8996 MTP", `qcom,msm-id = <246 0x30001>`, `qcom,board-id = <100 0>` |
| CPU | 4 x Kryo (MIDR 0x511f2112): cluster 0 MPIDR 0x0/0x1 up to 1.59 GHz, cluster 1 MPIDR 0x100/0x101 up to 2.15 GHz. **ARMv8.0: no LSE atomics, no PAN** |
| Timer | CNTFRQ 19.2 MHz |
| GIC | GICv3, distributor 0x09bc0000, redistributors 0x09c00000 (stride **0x40000**), ITS 0x09be0000 |
| RAM | 4 GB in two banks: `<0x80000000 2 GiB>` and `<0x1_00000000 0x7e4c0000>` |
| GPU | Adreno 530 (`kgsl-3d0@b00000`), SMMU `kgsl@b40000` |
| Storage | UFS 2.0, host `ufshc@624000`; microSD on SDHC2 |
| PMICs | PM8994 (SID 0/1) + PMI8996 (SID 2/3), SPMI arbiter v2 at 0x0400f000 |

### Reserved memory (downstream)

| Region | Base | Size |
| --- | --- | --- |
| dfps_data_mem | 0x83400000 | 0x1000 |
| cont_splash_mem (boot framebuffer) | 0x83401000 | 0x23ff000 |
| removed_regions | 0x85800000 | 0x3000000 |
| modem_region | 0x88800000 | 0x6200000 |
| peripheral_region | 0x8ea00000 | 0x2b00000 |
| cont_splash_mem_hdmi | 0xb1c00000 | 0x23ff000 |
| pstore_mem (ramoops) | 0xbfc00000 | 0x400000 |
| qseecom / secure / adsp | dynamic pools below 4 GB | 0x1400000 / 0x5c00000 / 0x400000 |

The whole upper bank (0x1_00000000, 0x7e4c0000 bytes) is free of
carve-outs, which is why the iOS port gives XNU exactly that bank.

### pstore / ramoops

4 MiB at 0xbfc00000, no ECC, laid out by the 3.18 ramoops driver as:

| Zone | Address | Size | TWRP file |
| --- | --- | --- | --- |
| dump records | 0xbfc00000 | 32 x 32 KiB | `dmesg-ramoops-N` |
| console | 0xbfd00000 | 1 MiB | `console-ramoops` |
| ftrace | 0xbfe00000 | 1 MiB | `ftrace-ramoops` |
| pmsg | 0xbff00000 | 1 MiB | `pmsg-ramoops-0` |

**The ZTE bootloader writes its own SBL1 + LK boot log into the console
zone** on some boots, so for your own early logs use the pmsg zone (or dump
record 0). The zones survive a PSCI warm reset and also the forced reset from
holding Power + Volume Up. Each zone starts with the 12-byte
`persistent_ram_buffer` header: `"DBGC"` (0x43474244), start, size.

## Partitions (UFS LUNs sda..sdf)

| Name | Device | Size | Notes |
| --- | --- | --- | --- |
| userdata | sda9 | ~52.4 GiB | |
| cache | sda2 | 800 MiB | |
| misc | sda3 | 1 MiB | |
| xbl / xblbak | sdb1 / sdc1 | 4 MiB | do not touch |
| aboot | sde11 | 1 MiB | ZTE LK, signed (Secure Boot on) |
| boot | sde12 | 64 MiB | |
| system | sde13 | 5.5 GiB | |
| recovery | sde14 | 64 MiB | TWRP |
| splash | sde24 | 32.6 MiB | `boot_logo.bmp`, `chargelogo.bmp`, `chargelogo2.bmp` (text index at offset 0) |
| vendor | sde28 | 512 MiB | added for Treble ROMs |
| modem | sde7 | 95 MiB | FAT, NON-HLOS firmware (`image/`) |
| persist | sdf5 | 32 MiB | calibration, keep a backup |
| modemst1/2, fsg, fsc | sdf1/sdf2, sde4, sdf3 | | EFS (IMEI), keep a backup |
| tz, hyp, rpm, pmic, cmnlib*, keymaster, devcfg, ... | sde* / sda* | | do not touch |

## Boot chain

See [bootloader.md](bootloader.md). In short: PBL -> XBL/SBL1 -> ZTE LK
(aboot) -> Android boot image (v0 header, page 4096, Image.gz with one
appended DTB). **There is no `fastboot boot`**, so test images go into the
`boot` partition from TWRP.

## Display

| Item | Value |
| --- | --- |
| Panel | Samsung 5.5" WQHD AMOLED, `mdss_dsi_zte_samsung_5p5_wqhd_dualmipi_cmd` (S6E3HA3 family) |
| Resolution | 1440 x 2560, about 534 ppi, 68 x 122 mm active area (approx.) |
| Interface | **two DSI links (split display), command mode**: DSI0 0x994000, DSI1 0x996000, PLLs 0x994400 / 0x996400 |
| MDP | MDSS 1.7 (HW version 0x10070002) at 0x900000, source split and ping-pong split capable |
| Brightness | DCS 0x51 (bootloader logs "backlight type:2 BL_DCS", "broadcast=1") |

The bootloader leaves a continuous splash running: one 1440x2560 RGB888
buffer at 0x83401000 (stride 4320 bytes), scanned by **VIG0 (left 720
columns) and VIG1 (right 720 columns, SRC_XY x = 720)** through **two CTL
paths**: CTL0 -> LM0 -> PP0 -> INTF1/DSI0 and CTL1 -> LM1 -> PP1 ->
INTF2/DSI1, with MDP split display enabled. Writing START on CTL0 alone
sends a frame to both halves; ping-pong done bits are MDP INTR_STATUS bit 8
(PP0) and 9 (PP1). Full register dump and the details are in
[display.md](display.md).

## Input

| Device | Bus / pins | Notes |
| --- | --- | --- |
| Touchscreen | Synaptics DSX (RMI4, F12) at I2C 0x20 on **BLSP2 QUP6** (0x75ba000, `blsp_i2c12`, SDA/SCL TLMM 87/88, function 3) | reset TLMM 89 (active low), attention/IRQ TLMM 125 (active low, TLMM summary IRQ = GIC SPI 208); supplies PM8994 L14 1.8 V (`vdd_ana`) and L22 3.3 V (`vcc_i2c`); GCC: BLSP2 AHB vote 0x352004 bit 15, QUP6 I2C CBCR 0x330008, RCGR 0x330020 |
| Capacitive keys | on the touch IC (`cap-button-codes` = KEY_BACK, KEY_HOME, KEY_MENU) | RMI4 F1A, *unverified* |
| Volume up / down | **PM8994 GPIO 2 / GPIO 3**, active low | read RT_STS (+0x10, bit 0) of SPMI peripheral 0xc1 / 0xc2 |
| Power | PM8994 PON KPDPWR | PON RT_STS 0x810 bit 0 |
| Hall sensor | TLMM 124 | polarity *unverified* |
| Pressure sensor | "ndt" at I2C 0x50 on BLSP2 QUP6, reset TLMM 121, power TLMM 69, IRQ TLMM 122 | no mainline driver |
| Fingerprint | Goodix GF3118 on BLSP SPI5, owned by TrustZone (TLMM 81-84 reserved) | |

## Connectivity

| Device | Details |
| --- | --- |
| Wi-Fi | Qualcomm QCA6174 on **PCIe RC0** (`pcie@600000`): PERST TLMM 35, WAKE TLMM 37, bootstrap TLMM 46, `wlan_en` PM8994 GPIO 8, `rome_vreg` PM8994 GPIO 9; rails PM8994 S3 1.3 V (core), S4 1.8 V (I/O), L30 1.8 V (xtal), L18 (antenna switch, pin control) |
| Wi-Fi firmware | modem partition `image/`: `qwlan30.bin`, `otp30.bin`, `utf30.bin`, `bdwlan30.bin` and board files `.b01`-`.b0e`, `.b11`, `.b15`, `.b18`, `.b1c` |
| Bluetooth | QCA6174 over BLSP1 UART2; enable PM8994 GPIO 19 |
| NFC | NXP NCI at I2C 0x28 on BLSP2 QUP2 (0x75b6000), enable TLMM 12, firmware TLMM 96, IRQ TLMM 9 |
| USB | USB 3.0 Type-C, TI HD3SS3220 CC controller at I2C 0x47 on BLSP2 QUP1 (0x75b5000) |
| Modem | MSM8996 internal MSS; firmware in the modem partition |

## Power

| Device | Details |
| --- | --- |
| PMICs | PM8994 + PMI8996 |
| Charger | PMI8996 internal + **external Summit/Qualcomm SMB1351** at I2C 0x1d on BLSP2 QUP1 |
| Fuel gauge | PMI8996 FG |
| Battery | 3250 mAh |

## Audio

| Device | Bus | Notes |
| --- | --- | --- |
| Codec | WCD9335 (SLIMbus) | |
| Hi-Fi DAC | AKM AK4490 at I2C 0x10 on BLSP1 QUP3 (0x7577000) | |
| Hi-Fi clock / mux | AKM AK8157 at I2C 0x11 on BLSP1 QUP6 (0x757a000) | |
| Hi-Fi supply | Intersil ISL98608 at I2C 0x29 on BLSP1 QUP3 | |

## Clocks and voltages (measured / from the live device tree)

GPU (Adreno 530) corners from the GFX CPR controller (`cpr3-ctrl@838000`),
one table on this phone (no speed-bin variants):

| Corner | GPU clock | Ceiling | | Corner | GPU clock | Ceiling |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | off | 400 mV | | 5 | 401.8 MHz | 825 mV |
| 2 | 133 MHz | 670 mV | | 6 | 510 MHz | 905 mV |
| 3 | 214 MHz | 670 mV | | 7 | 560 MHz | 960 mV |
| 4 | 315 MHz | 745 mV | | 8 | 624 MHz | 1015 mV |

(floor 520 mV for corners 2-8; GFX rail = PMI8996 S2.)

Bootloader leaves CPU at 1228 MHz (both clusters) and DDR at 1016 MHz
(BIMC 508 MHz); DDR runs at 1804 MHz via an RPM vote. The panel refreshes
through MDP command-mode kickoffs (one CTL0 START sends both DSI halves).

## Wi-Fi details

- QCA6174 rev 3.2 (chip id 0x340aff), firmware from the modem partition:
  `qwlan30.bin` reports **HTT 3.28** (the Pixel 1's firmware: HTT 3.50).
- OTP board id 0, so `bdwlan30.bin` is the board file in use (the `.b01`-`.b1c`
  variants are for other board ids).
- PCIe RC0 legacy INTA = GIC SPI 244 (INTID 276); MSI on SPI 405.
- Tx path: auth/assoc (management frames) and EAPOL 2/4 complete; EAPOL 4/4
  on the data path gets no tx completion with this firmware (open issue in
  the iOS port).

## HFS+ on this phone (iOS root)

If Linux writes to an iOS HFS+ image (loop mount), two things matter before
XNU mounts it again:
- Linux `fsck.hfsplus` does **not** replay the journal; replay it first
  (`ios/tools/hfs-journal-replay.py`) when iOS was force-reset.
- Linux `hfsplus` can grow a B-tree (the catalog) by an odd number of 4 KiB
  blocks with 8 KiB nodes. XNU refuses such a B-tree on a journaled volume
  (`BTOpenPath returned (5)`, root not mounted) once it has stamped the volume
  `HFSJ`; `ios/tools/hfs-btree-fix.py --fix` trims it.

## GPU firmware

From `/vendor/firmware`: `a530_pm4.fw`, `a530_pfp.fw`, `a530_zap.mdt` +
`.b00`-`.b02` (the zap shader is signed for this device's TrustZone, use
these, not another phone's), `a530v3_gpmu.fw2`, `a530v3_seq.fw2`.

## Recovery and reboot modes

| How | Effect |
| --- | --- |
| IMEM restart reason 0x066bf65c = 0x77665502 | next boot goes to recovery (TWRP) |
| IMEM restart reason 0x77665500 | `reboot bootloader`, but this LK boots Android instead of fastboot |
| `adb reboot "dm-verity enforcing"` | clears the dm-verity "eio" state and its red warning screen |
| Power + Volume Up held ~10 s | forced reset into recovery; pstore survives |
| Vol+ and Vol- held while plugging USB, phone off | Qualcomm EDL (9008), boot ROM emergency download |
| APSS watchdog | 0x09830000 (`EN` +0x08, `BARK` +0x10, `BITE` +0x14, 32768 Hz ticks); LK leaves it **disabled** |
