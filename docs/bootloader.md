# Axon 7 bootloader (ZTE LK / aboot) notes

Observed on an A2017G with an unlocked bootloader and the Oreo-era
bootstack that LineageOS for the Axon 7 requires (its installers check for
TrustZone `TZ.BF.4.0.1-00353`), Secure Boot **on** (SBL1 log: "Secure Boot: On").

## What LK does with a boot image

- Android boot image header **v0**, page size 4096. Stock/LineageOS images
  use kernel 0x80008000, ramdisk 0x81000000, second 0x80f00000, tags
  0x80000100 (base 0x80000000).
- The kernel is an arm64 `Image.gz` with **one appended DTB**; LK picks the
  DTB by `qcom,msm-id = <246 0x30001>` / `qcom,board-id = <100 0>` and
  patches it (memory, cmdline, splash).
- An unlocked device is not verified ("Device is unlocked! Skipping
  verification...").
- LK decompresses the kernel to **0x80080000** and passes the DTB at
  **0x82400000** in x0, at **EL1** with the MMU and caches off (measured
  with the probe shim). So kernel image + anything appended must stay
  below about 35 MiB.
- The APSS watchdog is left **disabled** (Pixel's LK leaves it running).
- LK leaves the display on with a continuous splash, see [display.md](display.md).

## No `fastboot boot`

This aboot contains the string "fastboot boot command is not available.",
and `adb reboot bootloader` (IMEM restart reason 0x77665500) simply boots
Android again. To test a kernel without flashing anything permanent, write
it to the `boot` partition from TWRP and reboot:

```sh
adb push test-boot.img /tmp/
adb shell dd if=/tmp/test-boot.img of=/dev/block/bootdevice/by-name/boot
adb reboot
```

Keep a copy of the working boot image to restore it the same way.

## Getting back into TWRP automatically

Write `0x77665502` to the IMEM restart reason (physical 0x066bf65c) before
resetting (PSCI SYSTEM_RESET, function 0x84000009); the next boot lands in
recovery. Our shims do this, so a test that ends in a reset returns to TWRP
on its own, where the pstore zones can be read.

## Warning screens

LK draws the boot warnings itself (they are code in the signed aboot, not
images in the `splash` partition, which only holds `boot_logo.bmp` and two
charging logos):

| Screen | Cause | Can it be removed? |
| --- | --- | --- |
| Orange: "Your device software can't be checked for corruption. Please lock the bootloader" | bootloader unlocked | No. aboot is signed and Secure Boot is on; a modified aboot would not boot (EDL recovery needed) |
| Red: "The dm-verity is not started in enforcing mode and may not work properly" | dm-verity state "eio" (`androidboot.veritymode=eio`) | Yes: `adb reboot "dm-verity enforcing"` once; afterwards `androidboot.veritymode=enforcing` |

## Other LK details

- Boot log: SBL1 and LK log into the ramoops console zone
  (`/sys/fs/pstore/console-ramoops` in TWRP shows "PBL, Start", "SBL1, Start", LK lines).
- Fastboot OEM commands present in this aboot: `oem device-info`,
  `oem enable-charger-screen`, `oem disable-charger-screen`,
  `oem off-mode-charge`, `oem select-display-panel`, `flashing unlock`, ...
- LK reads `boot_logo.bmp` from the `splash` partition.
