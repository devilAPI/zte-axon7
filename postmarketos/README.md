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
| `tools/axon7-nfc-test.py`, `tools/axon7-nfc-netlink.c` | minimal generic-netlink clients for Nura / Android: `info` reads `nfc0`, `up`/`poll` need root (`GENL_ADMIN_PERM`); no neard needed |

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

This is developed on an A2017G. The **A2017U (US)** shares the hardware and
codename but its stock B35 has **no fastboot endpoint at all**; restore it
with the B15-NEW EDL `aboot`+`fbop` (B29 alone was not enough for the
reporter) and reflash TWRP. The TWRP/microSD path below needs neither
fastboot nor a vendor partition: `axon7-firmware` falls back to the stock
`system` firmware if there is no vendor partition. Use an **A2017U**
modem/firmware base, and note that cellular is **untested** on A2017U. See
[../docs/variant-a2017u.md](../docs/variant-a2017u.md) and run
`tools/axon7-preflight.sh --rom nura` in TWRP.

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
- Still missing: the SMB1351 parallel charger (charging stops at 2 A), headset buttons, camera autofocus loop and OIS, fingerprint (TrustZone), suspend (broken on msm8996 mainline in general). Charging, audio, sensors and both cameras are in the table below.

## Audio: repeated playback and the ADSP restart (2026-11-22)

The r26/r27 finding (a second 1 s playback about 20 s after the first, or one
started while `axon7-audio-kick` restarts the ADSP, failed and sound stayed
off until a reboot) does not reproduce as a playback bug in the kernel: on
the main phone under LineageOS 24 (same 7.3.1 kernel series, the same
q6asm/q6adm/q6afe/q6routing, APR, SLIMbus NGD and AK4961 code) ten 1 s
silent playbacks with pauses of 1, 2, 3, 5, 10, 20, 30, 60, 5 and 1 s all
returned rc=0, the PCM went back to `closed` after each one, and dmesg had
no q6/APR/SLIMbus errors; a playback started after an ADSP stop/start and
one 20 s later also succeeded
(`ios/logs/audio-20261122-los-final.txt`; silence over
MultiMedia2 -> SLIMBUS_0_RX, the TFA9890 switches verified `Off` and
`Digital Playback Volume 0 0` before every playback).

What does break is the ADSP *restart*: stopping the ADSP removes the APR
devices, which unregisters the sound card, and the ASoC card teardown waits
for every open `/dev/snd` file to be closed. With a process that ignores the
card-removal event the `echo stop` never returns; the ADSP is left half
stopped (state still `running`, card gone), and every later APR command times
out until that process is gone. Reproduced on the main phone by holding
`/dev/snd/controlC0` open: the stop did not finish within 30 s while the card
disappeared, and recovered as soon as the holder was killed
(`ios/logs/audio-20261122-los-stop-blocked-fd.txt`). This is the "APR
services timing out until a reboot" state. The old `axon7-audio-kick` did
`echo stop`, `sleep 2`, `echo start` and could hit it when the card appeared
between its last check and the stop, or when a player already held it.

Fix in `device-zte-axon7` (r31, pkgrel 26): `axon7-audio-kick` now waits for
a *usable* card (`/proc/asound/cards`, the AK4961 bound on
`/sys/bus/slimbus/drivers/ak4961-slim/1dd:4961:2:0`, MultiMedia2 in
`/proc/asound/pcm`), looks again immediately before touching the DSP, refuses
to stop while any process holds `/dev/snd/*`, bounds the stop with `timeout`
and requires state `offline` before writing `start` (a half-stopped DSP is
never started), and the unit retries with `Restart=on-failure`. After a
successful restart it asks the logged-in user's PipeWire/WirePlumber to
re-scan the card, so a player that cached the old card does not stay silent
until a reboot. Off-device tests (fake sysfs/proc): `audio-tools/test-audio-kick.sh`
23/23 pass; on the second phone (Nura 7.3.1-t7+) `axon7-audio-kick --check`
as the unprivileged user printed
`card=yes codec=yes pcm=yes open=no` and "the sound card is ready".

One path stays uncovered by that test: while Android held the card, the
LineageOS build kept the SLIMbus NGD `active`
(`/sys/bus/platform/devices/qcom,slim-ngd.1/power/runtime_status`), while on
Nura it is `suspended` between streams (patch 0018 rewrites the AK4961 port
arrays in every `hw_params` exactly for that). So the NGD resume after a long
idle is still to be exercised on Nura; on the second phone the card, codec
and PCM are present, but the SSH user cannot open `/dev/snd` and there is no
sudo password, so `to-test.md` asks the owner for it.

Still to do: install r31 on the second phone, play ten times with pauses and
once while forcing an ADSP restart (`to-test.md`); the script's `--check`
needs no root, the restart itself does.

## NFC wiring and mainline status (2026-11-21)

The Axon 7 has an NXP PN548 (PN547/PN548 "NPC300" family) NFC controller.
ZTE's own 3.18 device tree and driver are preserved in this repo as
`../lineageos-22.2/kernel-4.4-patches/0001-ARM-dts-msm8996-Add-ZTE-Axon-7-ailsa_ii-device-tree.patch`
(node `pn5xx@28` on `i2c_8`) and `0013-nfc-NXP-PN5xx-I2C-driver-from-the-ZTE-3.18-kernel-ax.patch`.
They are the source of the wiring; the mainline binding needs only a subset:

| Signal | Downstream (ZTE) | Mainline `msm8996-zte-axon7.dts` |
| --- | --- | --- |
| Controller | `nxp,pn5xx`, I2C address 0x28 | `nxp,nxp-nci-i2c` (`nxp-nci_i2c`) at 0x28 |
| Bus | `i2c_8` = BLSP2 QUP2, 400 kHz | `&blsp2_i2c2`, `clock-frequency = <400000>` |
| Interrupt | TLMM 9, `nxp,int_active_low = <0>`, `IRQF_TRIGGER_HIGH` in the driver | TLMM 9, `IRQ_TYPE_LEVEL_HIGH` (same polarity and trigger) |
| VEN (enable) | `nxp,pn5xx-ven` = TLMM 12 | `enable-gpios = <&tlmm 12 GPIO_ACTIVE_HIGH>` |
| Firmware download | `nxp,pn5xx-fw-dwnld` = TLMM 96 | `firmware-gpios = <&tlmm 96 GPIO_ACTIVE_HIGH>` |
| eSE power | `nxp,pn5xx-ese-pwr` = PM8994 GPIO 7 | not used: mainline nxp-nci has no eSE/SWP support |
| Clock request / 19.2 MHz | ZTE defines `NFC_RF_CLK_FREQ 19200000` and `bb_clk2`, but both the `CONFIG_NFC_ENABLE_BB_CLK2` block and its `nxp,pn5xx-clkreq` property are disabled in the shipped driver | no `clocks`/clkreq property; no driver patch needed. The I2C bus clock is handled by the bus driver |

The node, its pinctrl state and `CONFIG_NFC=m`, `CONFIG_NFC_NCI=m`,
`CONFIG_NFC_NXP_NCI=m`, `CONFIG_NFC_NXP_NCI_I2C=m` have been in the series
since the first port (patch 0001 and `config-zte-axon7.aarch64`). This
investigation therefore produced **no new kernel patch** (no 0070 numbering,
no APKBUILD/pkgrel change): a second DT node for the same I2C address or a
clock driver would duplicate working support. A full clang build of that
unmodified series on 2026-11-21 (`make O=... Image.gz dtbs modules`) finished
cleanly; the only warning was the pre-existing `sns_smgr.ko` missing
`MODULE_DESCRIPTION()` (build log kept as `nfc-test/build-20261121.log`).

Evidence for the kernel/NCI side:

- Nura: commit `1a07559` (2026-11-10) recorded the controller answering NCI
  (reset/init interrupts on `up`, RF polling started) with
  `tools/axon7-nfc-test.py`. `to-test.md` §8 still asks the owner for a real
  tag/card to hold at the back of the phone; reading a tag is untested.
- 2026-11-21, second phone in Nura (battery 18-19 %, short check over USB
  SSH): `/sys/class/nfc/nfc0` exists and the (now fixed)
  `tools/axon7-nfc-test.py info` returns
  `idx 0 name nfc0 protocols 0xfe powered 0`
  (`ios/logs/nfc-20261121-nura.txt`, not committed). `up`/`poll`/`stop`/
  `down` need `CAP_NET_ADMIN` (`GENL_ADMIN_PERM` in `net/nfc/netlink.c`) and
  returned EPERM for the unprivileged SSH user; the early "ok" lines in that
  log were a stale-ACK bug in the first version of the tool and are corrected
  at the end of the file. No Nura sudo password was available here, root SSH
  and unprivileged reboot are denied, so the privileged test could not be
  repeated. The phone's SDP input limit is 500 mA and its capacity was not
  rising, so no long LineageOS RAM-boot test was made; the phone was left in
  Nura with NFC down.
- LineageOS 24 (`ios/logs/los24-m1a-31-pstore-console-ramoops.txt`): `nfc:
  nfc_init: NFC Core ver 0.1` and the `nfc`/`nci`/`nxp-nci`/`nxp-nci_i2c`
  modules load; run 51's `los24-m1a-51-hw.txt` has
  `rfkill0 -> .../3-0028/nfc/nfc0/rfkill0`. `tools/axon7-nfc-netlink.c` is a
  generic-netlink client for the same commands on Android.

### What Android still needs (LineageOS 24 plan row)

Android's NFC app talks to an NXP NFC HAL over a `/dev/pn5xx` character
device (NXP ioctls, vendor firmware download); mainline's `nxp-nci` is a
kernel NCI driver exposed through generic netlink. Its Kconfig says so
explicitly: "This is a driver based on the NCI NFC kernel layers and will
thus not work with NXP libnfc library." This is why `nfc0` existing is not
the same as NFC working in the Android UI. `virtual_ncidev` is a loopback
char device for a *userspace* NCI stack, not a compatible replacement for
the NXP HAL.

Smallest paths, from here:

1. **Port ZTE's char driver (recommended, ~3-5 days).** The code is already
   in this repo (`lineageos-22.2/kernel-4.4-patches/0013-...`, 773 lines):
   port `pn5xx_i2c.c` to 7.3.1, switch the existing DT node's compatible to
   `nxp,pn5xx` in the LineageOS build (and disable `CONFIG_NFC_NXP_NCI*`
   there; do not add a second node at 0x28), then use the stock `NfcNci` +
   `libnfc-nxp` blobs/config and the NFC firmware from the phone's own
   system/vendor; add ueventd and SELinux rules for `/dev/pn5xx`. Risk: the
   4.4 gpio/I2C API changes are mechanical, but the vendor blob and firmware
   must be present on the mainline filesystem; eSE/SWP can be dropped.
2. **Userspace netlink-to-AIDL HAL (~4-8 weeks).** Implement Android's NFC
   AIDL interface on top of `NFC_CMD_DEV_UP`/`START_POLL`/`*_EVENTS`: no
   vendor blobs, but NCI state machine, tag protocols and eSE all have to be
   written. Only worth it if the vendor HAL cannot be used.
3. **`virtual_ncidev` raw mode (~1 day, not a solution):** gives a char
   device to a userspace NCI stack; it does not transport NCI to the real
   PN548, nor speak NXP's ioctls. Useful only to develop option 2.

LineageOS 24 PLAN.md row and detail: 2026-11-21 entry in the LOS worktree.
No XDA changelog yet: nothing changed for an end user on either OS.

## Hardware added 2026-11-09/11 (kernel patches 0010-0043)

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
| Sound card at boot | `axon7-audio-kick` (device-zte-axon7 r31, pkgrel 26): waits 45 s for a *usable* card (card + AK4961 bound + MultiMedia2 PCM), restarts the ADSP up to twice, never stops it while `/dev/snd` is open, never starts a half-stopped ADSP, and asks the user audio session to re-scan afterwards | on some boots the SLIMbus controller never gets the ADSP's "master capability", so no AK4961 and no card; tested: ADSP stopped by hand, the service restarted it and the card came back. The restart race and the frozen "APR timeouts" are explained in *Audio: repeated playback and the ADSP restart* |
| Microphones 1 and 2 | `ak4961` AIF1 capture: ADC1 left = AIN1 (bottom, TX7, 0018), right = AIN2 (top, TX8, 0026) | confirmed: the vibrator raises mic 1 by ~30 dB; a tone from the top speaker is 18 dB louder on mic 2 |
| NFC | mainline `nxp-nci-i2c` (NXP PN5xx at 0x28 on `blsp2_i2c2`, IRQ TLMM 9, enable TLMM 12, firmware TLMM 96; in the DT since the start) | confirmed: the controller answers NCI (`tools/axon7-nfc-test.py up`: 3 interrupts for reset/init; `poll`: RF discovery runs). Reading a tag not tried (no tag at hand) |
| Headset microphone | `ak4961` AIN4 with MPWR2 bias on Mic_1L (0031), UCM device `Headset` | measured without a headset: PM4/PM5 = 0x0a while recording, open-input bias noise; voice to be heard. There is no third analog microphone: ZTE never routes AIN3 |
| Headset detection | `ak4961` jack detector as in ZTE's driver (0043): plug status (0xD8 bit 1), then the mic detector (bit 7, 5 hits in a row = headset, 9 rounds without = headphones), polled every 500 ms (the codec interrupt on TLMM 54 reads low with nothing pending, polarity unknown); `apq8096` makes a "Headset Jack" (ALSA controls `Headphone Jack`, `Mic Jack`, input device "ZTE Axon 7 Headset Jack") | registered and reads "unplugged" with nothing plugged in; plugging in still to be tested (to-test 11). UCM does not use the jack controls yet (added once a plug test confirms them), so the device is still chosen by hand |
| Sensors | SLPI (sensor DSP) enabled (0034); Sensor Manager IIO drivers from msm8996-mainline (Yassine Oudjana's WIP, 0032/0033) with fixes (0035, 0036), a gyroscope/magnetometer driver (0037) and a QMI service lookup instead of the QRTR bus patch (0038); `sns-reg` serves the phone's own `/persist/sensors/sns.reg` (`axon7-sns-reg.service`) | confirmed: accelerometer (Bosch BMI160, ~390/s, 10.5 m/s² lying flat), gyroscope (BMI160, ~385/s, 0.05 rad/s bias at rest), magnetometer (AKM AK09915, ~95/s, uncalibrated); the devices follow an SLPI restart. proximity/light (ROHM RPR0521, 0039/0040): `qcom-smgr-prox-light` with `in_proximity` (raw count, 4-5 with nothing near) and `in_illuminance` (lux, Q16; 28 lux indoors); "near" still to be measured |
| Front camera | mainline `ov8856` + `qcom-camss` (0020 VFE power-down fix, 0021 DT; CONFIG_VIDEO_OV8856) | confirmed: 3280x2464 RAW10 frames of the room through CSIPHY2 -> CSID0 -> ISPIF0 -> VFE0 RDI0 (no ISP, no app) |
| Rear camera | `s5k2t8` (new, 0027; CONFIG_VIDEO_S5K2T8) + DT (0028): CCI 0 at 0x2d, CSIPHY0, 4 lanes; init and mode tables from ZTE's `libmmcamera_s5k2t8.so` | confirmed: chip id 0x2148; colour bars and real light in all three modes, 5952x3348 at 30 fps (834 MHz link), 2976x1674 at 30 fps, 1920x1080 at 60 fps. |
| Rear camera focus | AK7371 as a variant of mainline `ak7375` (0029), 10-bit position, CCI 0 at 0x0c, `lens-focus` link (0030) | confirmed: `focus_absolute` 0..1023 moves the lens (the torch spot on the table shifts and narrows step by step). No autofocus loop and no OIS (ROHM BU63165) yet |
| Touch keys | mainline RMI4 F1A (0D buttons of the Synaptics S3718, `CONFIG_RMI4_F1A`) + DT key map (0042): back, home, app switch as `KEY_BACK`, `KEY_HOMEPAGE`, `KEY_APPSELECT`, in ZTE's order (`synaptics,cap-button-codes = <158 102 187>`) | the touchscreen input device declares the three keys (kernel #14 on the dev phone); pressing them is still to be felt (to-test 10). No key backlight driver |
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
decoded it as a single struct (0039).

Sensor scale measurements, 2026-11-21 (main phone, LineageOS 24, kernel
`#31 SMP PREEMPT`, build 51; read back from `/dev/iio:device{0,1,2}` with
24-byte scans, phone flat on the table):

| Sensor | raw x, y, z (means) | driver scale | value at rest |
| --- | --- | --- | --- |
| accel | -14730, 2327, -690149 (norm 690310) | 0.000015328 (9.81/640000) | norm 10.58 m/s², 7.9 % high |
| gyro | 302, 1028, 2931 (norm 3125) | 1/65536 | norm 0.048 rad/s (bias at rest) |
| mag | 40229, -8100, 18772 (norm 45131) | 1/65536, HAL x100 (G -> uT) | norm 0.689 G = 68.9 uT |

A plain Q16 scale (1/65536) would still leave the accel 7.4 % high: the
factory calibration which the SLPI applies to the reports from the phone's
own `sns.reg` makes 1 g about 690310 counts here, not the 640000 assumed by
the original WIP driver. `sensread` (sensorservice -> HAL -> IIO through
the same kernel) confirms it: `BMI160 Accelerometer ... -0.017 0.178 10.594`
in uT/m/s², i.e. norm 10.59 m/s². The same run reports
`BMI160 Gyroscope ... -0.018 -0.004 -0.045` rad/s at rest and
`AK09915 Magnetometer ... 10.200 -59.998 -28.798` uT (norm 67.4 uT).
Fix in kernel patch 0063: `smgr_accel` now uses 14211 nm/s^2 per LSB (9.81 / 690310) instead of 15328; for the raw values above that gives 690310 * 0.000014211 = 9.81 m/s^2. Gyro and mag keep their 1/65536 (Q16) scale: gyro bias is not a scale issue, mag reads ~67 uT (in range).

Verified on 2026-11-22 that the patched driver compiles into a module for the
running LineageOS 24 kernel (`7.3.1-axon7m SMP preempt mod_unload aarch64`,
same `vermagic` as the image's `smgr_accel.ko`): `llvm-objdump -d` of the new
module shows `mov w8, #0x3783 // =14211` in `smgr_accel_read_raw` where the
old module has `mov w8, #0x3be0 // =15328`.

Measured on the main phone the same day (LineageOS 24 build #31, adb root,
under the phone flock, no reboot/test kernel/SLPI restart): with the original
module `in_accel_scale = 0.000015328` and `|a| = 10.650 / 10.628 m/s^2` at
rest (flat, screen up); with the patched module swapped in `0.000014211` and
`9.876 / 9.849 m/s^2`, inside the 9.81 ± 1 % target. Gyro bias (0.049 rad/s)
and mag magnitude (66-67 uT) were unchanged. The original module and sensors
HAL were restored (scale back to 0.000015328, HAL running, adb up, battery
99 %). Details and the full test log:
`postmarketos/research/accel-sensors/RESULTS-2026-11-22.md`. Only one
orientation was measured: an unattended run cannot turn the phone.

The same patch is in the LineageOS 24 #1 kernel (build 58, 2026-11-26): flat
on the phone the sensors service reads 9.84 m/s² with the shipped module,
instead of 10.6 with the old scale (`XDA-POST-LINEAGEOS-24.md`, build 58
changelog). Nura r32 ships the same 0001-0063 series; its own phone reading is
still to be confirmed.

Read a few samples:

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
(5 of 5 test boots with Wi-Fi, 3 of them rescued). Since r27 the helper also
runs `modprobe ath10k_pci` after a successful rescan: on LOS 24 wifi24 the
chip was found but stayed unbound when ueventd had skipped the module because
its firmware comes from the modem partition first. Nura's board data is that
partition's `image/bdwlan30.bin`, copied to
`/usr/lib/firmware/postmarketos/ath10k/QCA6174/hw3.0/board.bin` by
`axon7-firmware` at first start; the helper checks the sysfs symlink (`-L`)
instead of following it (`-e`).

Speaker stereo is open: with the bottom amplifier on "Right" its output was
nearly silent in a measurement (the TFA9890 in DSP bypass may ignore the
channel select), so UCM puts both amplifiers on the left channel (mono).
