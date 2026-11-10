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

- **Display**: works (S6E3HA3 driver and bonded DSI, patches 0002, 0004; DPU drives DSI-1 at 1440x2560, `msmdrmfb` console). It needs `msm.prefer_mdp5=0`, or the MDP5 driver takes MDSS and cannot drive two links.
- **USB OTG**: works on PI5USB302 units (automatic host/device); the HD3SS3220 variant is untested on a phone. The PI5USB302 interrupt is unusable (polled).
- **Wi-Fi roaming**: the QCA6174 firmware often does not acknowledge key deletions; ath10k waited 3 s for it on every roam and group rekey, after which a WPA3/PMF router (FRITZ!Box here) rejected the new association and every 4-way handshake timed out for minutes. Patch 0008 (after Richard Acayan's RFC on the ath10k list) stops waiting for DISABLE_KEY. Tested: forced roams 2.4 → 5 GHz and back now take 0.4–0.5 s with no key timeout.
- Charging control (PMI8996 SMBCharger/FG drivers are only in the msm8996 fork; SMB1351 has no driver), audio (WCD9335 + AK4490), sensors, cameras, suspend (broken on msm8996 mainline in general).

## Hardware added 2026-11-09/10 (kernel patches 0010-0041)

| Part | Driver | State |
| --- | --- | --- |
| Hall sensor | gpio-keys SW_LID + LVS2 always on (0010) | open confirmed; closed needs a magnet. logind ignores the lid (`50-zte-axon7-lid.conf`) while suspend doesn't work |
| Fuel gauge | `qcom_fg` from msm8996-mainline (0011; 0023 fixes an oops when a charger appears: SRAM access was set up after registering) | confirmed: level, voltage, temperature, current sign (positive = discharging) |
| Charger | `qcom-smbchg` from msm8996-mainline (0024), float 4.4 V, 2 A fast charge, 150 mA termination (no SMB1351 parallel charger) | confirmed: SDP detected, PMIC set to 4.4 V / 2.0 A (bootloader left 4.2 V / 1.7 A), status Full at 99 % |
| Watchdog | APSS watchdog node in msm8996.dtsi (0025, from the LineageOS 24 work) | bound; a hung kernel resets instead of freezing |
| Vibrator | `qcom-pmi8994-haptics` (0012), ZTE's 2668 mV / 4255 us | LRA auto-resonance locks while playing; to be felt |
| Torch | `leds-qcom-pmi8994-torch` (0013), `white:torch`, 1-16 (12.5 mA steps per LED) | registers as downstream, no LED fault; to be seen |
| Hi-Fi audio | `ak4490`, `ak8157`, `isl98608-regulator`, MI2S in `apq8096` (0014) | plays in real time on Quaternary MI2S, clocked by the AK8157; to be heard |
| Speakers | `ak4961` (new: SLIMbus slim1dd,4961, registers over SPI on BLSP2 QUP3) + mainline `tfa989x` x2 (0015, 0016, 0018) | confirmed: a -21 dBFS 1 kHz tone saturates the microphone; SBI1 looped back to SLIMbus TX is bit-exact |
| Microphones 1 and 2 | `ak4961` AIF1 capture: ADC1 left = AIN1 (bottom, TX7, 0018), right = AIN2 (top, TX8, 0026) | confirmed: the vibrator raises mic 1 by ~30 dB; a tone from the top speaker is 18 dB louder on mic 2 |
| Headset microphone | `ak4961` AIN4 with MPWR2 bias on Mic_1L (0031), UCM device `Headset` | measured without a headset: PM4/PM5 = 0x0a while recording, open-input bias noise; voice to be heard. No jack detection yet, so the device is chosen by hand. There is no third analog microphone: ZTE never routes AIN3 |
| Sensors | SLPI (sensor DSP) enabled (0034); Sensor Manager IIO drivers from msm8996-mainline (Yassine Oudjana's WIP, 0032/0033) with fixes (0035, 0036), a gyroscope/magnetometer driver (0037) and a QMI service lookup instead of the QRTR bus patch (0038); `sns-reg` serves the phone's own `/persist/sensors/sns.reg` (`axon7-sns-reg.service`) | confirmed: accelerometer (Bosch BMI160, ~390/s, 10.5 m/s² lying flat), gyroscope (BMI160, ~385/s, 0.05 rad/s bias at rest), magnetometer (AKM AK09915, ~95/s, uncalibrated); the devices follow an SLPI restart. proximity/light (ROHM RPR0521, 0039/0040): `qcom-smgr-prox-light` with `in_proximity` (raw count, 4-5 with nothing near) and `in_illuminance` (lux, Q16; 28 lux indoors); "near" still to be measured |
| Front camera | mainline `ov8856` + `qcom-camss` (0020 VFE power-down fix, 0021 DT; CONFIG_VIDEO_OV8856) | confirmed: 3280x2464 RAW10 frames of the room through CSIPHY2 -> CSID0 -> ISPIF0 -> VFE0 RDI0 (no ISP, no app) |
| Rear camera | `s5k2t8` (new, 0027; CONFIG_VIDEO_S5K2T8) + DT (0028): CCI 0 at 0x2d, CSIPHY0, 4 lanes; init and mode tables from ZTE's `libmmcamera_s5k2t8.so` | confirmed: chip id 0x2148; colour bars and real light in all three modes, 5952x3348 at 30 fps (834 MHz link), 2976x1674 at 30 fps, 1920x1080 at 60 fps. |
| Rear camera focus | AK7371 as a variant of mainline `ak7375` (0029), 10-bit position, CCI 0 at 0x0c, `lens-focus` link (0030) | confirmed: `focus_absolute` 0..1023 moves the lens (the torch spot on the table shifts and narrows step by step). No autofocus loop and no OIS (ROHM BU63165) yet |
| Earpiece switch | `tfa989x` Receiver Switch on rcv-gpios (PM8994 GPIO 13) (0017, 0019) | measured: only the top speaker (TFA9890 0x35) changes; UCM device Earpiece switches the bottom speaker's pin off (0022), the microphone level drops 17 dB |

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

Speakers: the AK4961 runs as ZTE ran it ("SLIMbus + SPI": CIF1 low, registers
over SPI with read 0x01/write 0x81 + 16-bit address, audio over SLIMbus PGD
ports 10/11). Its init values come from a register dump of the LineageOS 4.4
port at idle, and the playback writes from a dump while it played to the
speaker. ZTE's speaker path: SLIM RX1/2 = SB1_PB, PORT2 sync = SLIMbus,
SDTO2 = SBI1; PORT2 (I2S master) feeds two TFA9890 at 0x34/0x35 on BLSP1
QUP6 (mainline `tfa989x`, DSP bypass, no NXP container files). UCM device
`Speaker` (priority 100) next to `Headphones` (200), playback on MultiMedia2
(`hw:N,1`), `Mic` capture on MultiMedia1 (`hw:N,0`). The SLIMbus controller
runtime-suspends between streams and the bus restarts, which clears the
AK4961's PGD port arrays: they are written on every hw_params (as ZTE does),
otherwise the RX data never reaches SBI1 (silent speakers, 0016 alone).

Front camera: OV8856 at 0x36 on CCI bus 1, CSIPHY2, 4 lanes. CAMSS needs
CAMSS_GDSC as its top power domain (third entry in `power-domains`), or
`camss_top_ahb_clk` is enabled for the CSIPHY before any VFE domain is up
and stays stuck off. Test capture (as root):

```sh
M="media-ctl -d /dev/media0"; F="fmt:SGRBG10_1X10/3280x2464 field:none"
$M -l '"msm_csiphy2":1->"msm_csid0":0[1],"msm_csid0":1->"msm_ispif0":0[1],"msm_ispif0":1->"msm_vfe0_rdi0":0[1]'
$M -V "\"ov8856 6-0036\":0[$F],\"msm_csiphy2\":0[$F],\"msm_csid0\":0[$F],\"msm_ispif0\":0[$F],\"msm_vfe0_rdi0\":0[$F]"
v4l2-ctl -d $($M -e "ov8856 6-0036") --set-ctrl analogue_gain=1024
V=$($M -e msm_vfe0_video0); v4l2-ctl -d $V --set-fmt-video=width=3280,height=2464,pixelformat=pgAA
v4l2-ctl -d $V --stream-mmap --stream-count=4 --stream-to=/tmp/front.raw   # MIPI RAW10, GRBG, stride 4104
```

Rear camera: S5K2T8 at 0x2d on CCI bus 0 (`s5k2t8 5-002d`), CSIPHY0, 4 lanes,
SGRBG10. Its register tables come from ZTE's sensor library
(`libmmcamera_s5k2t8.so` in the vendor partition: `sensor_lib_t` at the
start of `.data`; init blocks of 0x4010 bytes from 0x8e28, mode tables from
0x40f0c). Same capture as above with `msm_csiphy0` and one of the three
sizes; exposure is in lines, `analogue_gain` 32 = 1x up to 512 = 16x,
`test_pattern=2` gives colour bars:

```sh
M="media-ctl -d /dev/media0"; F="fmt:SGRBG10_1X10/2976x1674 field:none"   # or 5952x3348, 1920x1080
$M -l '"msm_csiphy0":1->"msm_csid0":0[1],"msm_csid0":1->"msm_ispif0":0[1],"msm_ispif0":1->"msm_vfe0_rdi0":0[1]'
$M -V "\"s5k2t8 5-002d\":0[$F],\"msm_csiphy0\":0[$F],\"msm_csid0\":0[$F],\"msm_ispif0\":0[$F],\"msm_vfe0_rdi0\":0[$F]"
v4l2-ctl -d $($M -e "s5k2t8 5-002d") --set-ctrl exposure=2000,analogue_gain=64
V=$($M -e msm_vfe0_video0); v4l2-ctl -d $V --set-fmt-video=width=2976,height=1674,pixelformat=pgAA
v4l2-ctl -d $V --stream-mmap --stream-count=4 --stream-to=/tmp/rear.raw
```

Focus: the lens subdev `ak7375 5-000c` keeps its position only while it is
open (it powers down on close), so hold it open during the capture:
`exec 3<>/dev/v4l-subdevN; v4l2-ctl -d /dev/v4l-subdevN --set-ctrl focus_absolute=600`
(0 = far end of travel, 1023 = the other end).

Sensors: all of them hang off the SLPI. At boot it asks the apps side for
its sensor registry (QMI service SNS_REG); `sns-reg` (package in
`pmaports-local/temp/sns-reg`) answers from `/etc/sns-reg.d/registry.conf`,
which `axon7-sns-registry` generates once from the phone's own
`/persist/sensors/sns.reg` (written by the stock or LineageOS sensor daemon,
so Android must have run once). Then the SLPI offers the Sensor Manager
(QRTR service 256, v1, instance 50) and `smgr` registers one IIO device per
sensor: `qcom-smgr-accel`, `-gyro`, `-mag` (buffered only, Q16: scale
1/65536 m/s², rad/s, gauss) and `-prox-light` (proximity count, lux in
Q16). The report's index TLV lists one entry per data type; the WIP driver
decoded it as a single struct (0039). Read a few samples:

```sh
D=$(grep -l qcom-smgr-accel /sys/bus/iio/devices/iio:device*/name); D=${D%/name}
for c in x y z; do echo 1 | sudo tee $D/scan_elements/in_accel_${c}_en; done
echo 1 | sudo tee $D/buffer/enable; sudo timeout 1 cat /dev/${D##*/} | od -A d -t d4 | head; echo 0 | sudo tee $D/buffer/enable
```

Desktop use: `iio-sensor-proxy` (in the device package) finds the
accelerometer, light and proximity sensor (`monitor-sensor`). It needs a
trigger on buffered accelerometers, named `<name>-dev<IIO device number>`,
and polls `in_illuminance_raw` / `in_proximity_raw`: each sensor gets its
own trigger fired per report, and the light/proximity sensor reports at
10 Hz all the time (0041). `61-axon7-sensors.rules` sets ZTE's accelerometer
axes (x = -y, y = -x, z = -z: lying flat screen up gives "face-up") and a
first-guess `PROXIMITY_NEAR_LEVEL` of 100. The compass is not used: the
proxy wants a tilt-compensated heading.

The WIP driver used u8 for QMI length fields; the 7.3 QMI code copies them as
u32, so every request for a sensor other than ID 0 failed ("qmi_encode:
Invalid data length") until 0035.

Wi-Fi: the QCA6174's PCIe link sometimes comes up only after `qcom-pcie`
has given up at boot ("Device found, but not active"; 3 of 16 boots before
the SLPI was enabled, more often since). The root port then shows the link
active; `axon7-wifi-rescan.service` rescans the bus and the chip appears
(5 of 5 test boots with Wi-Fi, 3 of them rescued).

Speaker stereo is open: with the bottom amplifier on "Right" its output was
nearly silent in a measurement (the TFA9890 in DSP bypass may ignore the
channel select), so UCM puts both amplifiers on the left channel (mono).
