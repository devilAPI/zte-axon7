# postmarketOS for the ZTE Axon 7 (mainline Linux)

Status: **packages written and the kernel builds; not booted on the phone yet.**

Device `zte-axon7`, mainline **Linux 7.3.1** (the newest stable release;
postmarketOS's own msm8996 kernel is at 6.19.5, and everything the Axon 7
needs for a first boot is already upstream). Rootfs on the **microSD card**,
kernel in the `boot` partition, so internal storage (and any other OS on
`userdata`) stays untouched.

## What's here

| Path | Contents |
| --- | --- |
| `pmaports-local/device/testing/device-zte-axon7/` | `deviceinfo`, `APKBUILD`, `modules-initfs` |
| `pmaports-local/device/testing/linux-zte-axon7/` | `APKBUILD`, kernel config, `0001-arm64-dts-qcom-add-ZTE-Axon-7.patch` (the device tree) |
| `pmaports-local/device/testing/firmware-zte-axon7/` | `APKBUILD` only. The firmware tarball is proprietary and **not in git**: build it from your own phone (below) |
| `dts/msm8996-zte-axon7.dts` | the device tree as a plain file |
| `scripts/pil-squasher.py` | joins split `.mdt` + `.bNN` firmware into `.mbn` |
| `scripts/make-test-bootimg.sh` | builds a standalone test boot image (USB networking + telnet, no storage access) |
| `test-initramfs/root/init`, `list.txt` | that test initramfs (busybox not included) |

## Device tree

Written from the phone's downstream device tree against mainline 7.3.1.
The older `msm8996-zte-axon7.dts` in the msm8996-mainline fork was partly
copied from the OnePlus 3 (wrong volume keys, parts the Axon 7 doesn't have)
and wasn't used.

- LK match: `qcom,msm-id = <246 0x30001>`, `qcom,board-id = <100 0>`, PMIC id via `pmi8996.dtsi`.
- Memory: standard msm8996 reserved-memory, the splash at 0x83400000 kept, ramoops at 0xbfc00000 as downstream (readable from TWRP).
- Enabled: UFS, microSD (`broken-cd`: the card-detect polarity is unverified, so the slot is polled), USB 2.0 peripheral (dwc3), touch (RMI4 on `blsp2_i2c6`), volume keys (PM8994 GPIO 2/3), NFC, Wi-Fi (ath10k, QCA6174 on PCIe0), Bluetooth, RGB LED, GPU, Venus, ADSP and modem remoteprocs, all regulators with downstream voltages.
- Display: `simple-framebuffer` on the splash buffer (1440x2560 r8g8b8). TLMM 81-84 reserved (TrustZone owns the fingerprint SPI).
- Hall sensor left disabled until its polarity is known.

## Building (needs sudo for pmbootstrap's chroots)

```sh
pmbootstrap init        # vendor "zte", codename "axon7"; if asked, it's a mainline port
cp -r pmaports-local/device/testing/* "$(pmbootstrap config aports)/device/testing/"
pmbootstrap build linux-zte-axon7 firmware-zte-axon7 device-zte-axon7
pmbootstrap install
pmbootstrap export      # -> /tmp/postmarketOS-export/{boot.img,zte-axon7.img}
```

### Firmware tarball

`firmware-zte-axon7-1.tar.gz` must contain, from your own phone:

```
qcom/msm8996/zte/axon7/{a530_zap,adsp,mba,modem,slpi,venus}.mbn
postmarketos/ath10k/QCA6174/hw3.0/board.bin      (= bdwlan30.bin)
```

The `.mdt` + `.bNN` sources are in the `modem` partition (FAT, `image/`) and
in `/vendor/firmware`; join each with `scripts/pil-squasher.py OUT.mbn IN.mdt`.
Then put the tarball's sha512 into the firmware APKBUILD.

## Dual boot with iOS (Volume Down)

The boot partition can hold the iOS port and postmarketOS together
(ios/PORTING-AXON7.md, "Dual boot"): iOS boots by default, holding
**Volume Down after the ZTE logo appears** starts postmarketOS. With the
rootfs on the microSD card (below) and the phone in TWRP:

```sh
cd ../ios && tools/axon7-dualboot-flash.sh   # bundle from pmbootstrap's chroot, iOS half kept
```

On the phone, kernel and initramfs updates rebuild the postmarketOS half
themselves (`deviceinfo_flash_kernel_on_update="false"`;
`/usr/libexec/axon7-dualboot-update` from the /boot apk trigger and the
`axon7-dualboot` OpenRC service, log `/var/log/axon7-dualboot.log`). It only
writes when the boot partition already has the iOS shim, so it never
overwrites iOS.

## Installing (no fastboot on this phone)

The Axon 7's LK has no `fastboot boot` and `pmbootstrap flasher` won't work.
From TWRP:

```sh
# rootfs -> microSD (erases the card)
adb exec-in "dd of=/dev/block/mmcblk0 bs=4M" < /tmp/postmarketOS-export/zte-axon7.img
# kernel + initramfs -> boot partition (keep a backup of the old boot.img)
adb push /tmp/postmarketOS-export/boot.img /tmp/ && adb shell dd if=/tmp/boot.img of=/dev/block/bootdevice/by-name/boot
adb reboot
```

Logs after a crash: boot TWRP and read `/sys/fs/pstore/*` (see `../docs/hardware.md`).

## Known gaps

- **Display**: no mainline driver for the dual-DSI S6E3HA3 command-mode panel yet, so the screen likely stays on the boot logo (a command-mode panel needs frames to be started, see `../docs/display.md`). A reference panel driver exists in ungeskriptet's msm8996 tree.
- Charging control (PMI8996 SMBCharger/FG drivers are only in the msm8996 fork; SMB1351 has no driver), USB-C role switching (HD3SS3220), audio (WCD9335 + AK4490), sensors, cameras, suspend (broken on msm8996 mainline in general).
