# Nura: postmarketOS for the ZTE Axon 7 (mainline Linux)

Status: **beta** (2026-11-08). Nura is this postmarketOS port's name for
users; packages and device names stay `zte-axon7`. Install guide for users:
[../INSTALL-NURA.md](../INSTALL-NURA.md). What works: display, touch,
on-screen keyboard, Wi-Fi, Bluetooth, SSH, USB OTG, battery level. New and
still to be confirmed by eye/ear: Hi-Fi headphone audio, vibration, torch,
flip cover sensor (see *Hardware added 2026-11-09*).

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
- Enabled: UFS, microSD (`broken-cd`: the card-detect polarity is unverified, so the slot is polled), USB 2.0 dual role (dwc3 + HD3SS3220 or PI5USB302 Type-C controller on `blsp2_i2c1`, VBUS for host mode from the PMI8994 SMBCHG OTG boost, `qcom_smbchg_otg-regulator`, patch 0003; automatic role, see *USB OTG*), touch (RMI4 on `blsp2_i2c6`), volume keys (PM8994 GPIO 2/3), NFC, Wi-Fi (ath10k, QCA6174 on PCIe0; board data = the phone's `bdwlan30.bin` from firmware-zte-axon7; the kernel has no firmware user-helper fallback, which used to stall ath10k for ~3 minutes), Bluetooth, RGB LED, GPU, Venus, ADSP and modem remoteprocs, all regulators with downstream voltages.
- Display: MDSS with both DSI links bonded (DSI0 master) to the Samsung S6E3HA3 command-mode panel (`panel-samsung-s6e3ha3`, patch 0002: downstream init sequence, reset, DCS brightness as `/sys/class/backlight`). Bonded DSI needs the DPU driver: kernel command line `msm.prefer_mdp5=0` (MDP5 does single DSI only). `simple-framebuffer` on the splash buffer covers early boot. TLMM 81-84 reserved (TrustZone owns the fingerprint SPI).
- Hall sensor (TLMM 124, high = open) as SW_LID; it is powered from PM8994 LVS2, which is kept on (with LVS2 off the line reads low = "closed").

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

## Dual boot with iOS (boot menu)

The boot partition can hold the iOS port and postmarketOS together
(ios/PORTING-AXON7.md, "Dual boot"): after the ZTE logo a menu comes up,
**Vol+/Vol- choose, Power starts** the entry, and iOS starts after 10 s
without a key. postmarketOS needs its rootfs installed first. With the
rootfs on the microSD card (below) and the phone in TWRP:

```sh
cd ../ios && tools/axon7-dualboot-flash.sh   # bundle from pmbootstrap's chroot, iOS half kept
```

On the phone, kernel and initramfs updates rebuild the postmarketOS half
themselves (`deviceinfo_flash_kernel_on_update="false"`;
`/usr/libexec/axon7-dualboot-update` from the /boot apk trigger and the
`axon7-dualboot` service at boot, systemd unit or OpenRC script, log
`/var/log/axon7-dualboot.log`). It only
writes when the boot partition already has the iOS shim, so it never
overwrites iOS.

## On-screen keyboard (buffyboard)

The console image ships buffyboard; device-zte-axon7 adds its config
(`/usr/share/buffyboard/buffyboard.conf.d/50-zte-axon7.conf`: breezy-dark,
touchscreen only, `fbdev_force_refresh`) and `buffyboard.service` (enabled by
preset). It finds the Synaptics touchscreen and /dev/uinput, but draws nothing
on the 24 bpp simple-framebuffer yet; with the msm DRM driver's 32 bpp fbdev
it is to be checked again.

## USB OTG

Some Axon 7s have a TI HD3SS3220 Type-C chip, others (this one) a Pericom
PI5USB302 (I2C 0x0d, `pi5usb302` driver, patch 0006); the DTS describes
both. OTG is automatic: plug a device in and VBUS (PMI8994 OTG boost) comes
on within about a second, plug a PC in and the phone is a USB gadget again.

How: with nothing attached the driver keeps dwc3 in **host** role (VBUS
off). The PI5USB302 only reports an attached device (CC_STAT attached=1)
while dwc3 is in host role; in device role it never does, which is why the
first version (idle = device role) never saw a mouse. A host partner
(attached=2) switches to device role. The interrupt (PM8994 GPIO 14) fails
with -EIO, so the driver polls CC_STAT every 500 ms.

For accessories that present no Rd (some cheap adapters), host mode and
VBUS can still be forced (never with a PC on the cable):

```sh
echo 1 | sudo tee /sys/module/pi5usb302/parameters/force_host   # host + VBUS
echo 0 | sudo tee /sys/module/pi5usb302/parameters/force_host   # automatic again
```

## Bluetooth

QCA6174 Bluetooth on `blsp1_uart2` (`qcom,qca6174-bt`, hci_uart + btqca,
rampatch/nvm `qca/*_00440302.bin` from linux-firmware). The chip has no
address of its own: the kernel keeps hci0 *unconfigured* (`btmgmt config`:
missing public-address) until userspace sets one. `axon7-btaddr` (udev +
`axon7-btaddr.service`) reads ZTE's factory address from the persist
partition, `/.bt_nv.bin` (Qualcomm NV records `[id][0][len][data]`, item 1 =
BD address, LSB first; persist mounted `ro,noload`), falling back to an
address derived from the SoC serial. The kernel needs `CONFIG_BT_LE` for LE
connections (HID over GATT), RFCOMM and BNEP are modules (r6). Tested: scan
(BR/EDR + LE), LE connection with GATT service discovery to a PC.
`Frame reassembly failed (-84)` once during the rampatch download is harmless.

## Boot menu default

`axon7-bootmenu default pmos 5` makes the shim start postmarketOS after 5 s
without a key (`axon7-bootmenu clear` goes back to iOS). The bundle lives in
the `pmos_boot` partition on LUN 0: LUNs 1-4 (boot, system, vendor) are write
protected while the phone runs normally.

## Installing (no fastboot on this phone)

Firmware tarball from the phone in TWRP: `scripts/axon7-firmware.sh` (see
*Firmware tarball*). Standalone boot from LK: LK unpacks the kernel to
0x80080000 (7.3.1 `image_size` ends at 0x81f20000, DTB at 0x82400000) and
puts the initramfs after the DTB at about 0x82600000; the 14.1 MB initramfs
ends at 0x83375254, just below the splash reservation at 0x83400000. An
initramfs more than about 550 KB larger would overlap it (the multi-boot
shim moves its bundle out of the way, so it doesn't have this limit).

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

- **Display**: the S6E3HA3 driver and the bonded-DSI setup (patches 0002, 0004) are built but not yet tested on the phone; without `msm.prefer_mdp5=0` the MDP5 driver takes MDSS and cannot drive two links.
- **USB OTG**: works on PI5USB302 units (automatic host/device); the HD3SS3220 variant is untested on a phone. The PI5USB302 interrupt is unusable (polled).
- **Wi-Fi roaming**: the QCA6174 firmware often does not acknowledge key deletions; ath10k waited 3 s for it on every roam and group rekey, after which a WPA3/PMF router (FRITZ!Box here) rejected the new association and every 4-way handshake timed out for minutes. Patch 0008 (after Richard Acayan's RFC on the ath10k list) stops waiting for DISABLE_KEY. Tested: forced roams 2.4 → 5 GHz and back now take 0.4–0.5 s with no key timeout.
- Charging control (PMI8996 SMBCharger/FG drivers are only in the msm8996 fork; SMB1351 has no driver), audio (WCD9335 + AK4490), sensors, cameras, suspend (broken on msm8996 mainline in general).

## Hardware added 2026-11-09 (kernel patches 0010-0014)

| Part | Driver | State |
| --- | --- | --- |
| Hall sensor | gpio-keys SW_LID + LVS2 always on (0010) | open confirmed; closed needs a magnet. logind ignores the lid (`50-zte-axon7-lid.conf`) while suspend doesn't work |
| Fuel gauge | `qcom_fg` from msm8996-mainline, read-only without a charger driver (0011) | confirmed: level, voltage, temperature, current sign (positive = discharging) |
| Vibrator | `qcom-pmi8994-haptics` (0012), ZTE's 2668 mV / 4255 us | LRA auto-resonance locks while playing; to be felt |
| Torch | `leds-qcom-pmi8994-torch` (0013), `white:torch`, 1-16 (12.5 mA steps per LED) | registers as downstream, no LED fault; to be seen |
| Hi-Fi audio | `ak4490`, `ak8157`, `isl98608-regulator`, MI2S in `apq8096` (0014) | plays in real time on Quaternary MI2S, clocked by the AK8157; to be heard |

Hi-Fi path: the AK8157 is the I2S clock master (the ADSP's Quaternary MI2S
is a clock consumer with its EBIT clock gated on, data on SD1 = TLMM 61);
AK4490 power is the TLMM 93 LDO plus the ISL98608 (PMI MPP 4, then ZTE's 14
registers), PDN on PMI GPIO 1; the ISL54405 jack switch (PM8994 MPP 2) stays
on the AK4490 and its mute (MPP 4) follows the stream. All these PMIC pins
came up on VPH and are set to 1.8 V (S4) as downstream. UCM: verb HiFi,
device Headphones (`ucm-zte-axon7*.conf` in device-zte-axon7).

Test from the console: `alsaucm -c hw:0 set _verb HiFi` (or
`amixer -c0 cset name='QUAT_MI2S_RX Audio Mixer MultiMedia1' 1`), then
`speaker-test -c 2 -t sine`.
