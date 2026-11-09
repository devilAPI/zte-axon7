# ZTE Axon 7 multi-boot (iOS 16 + Nura + LineageOS): development setup

**This is the developers' setup**, used to work on all three systems on one
phone: a boot menu after the ZTE logo starts iOS, Nura (postmarketOS) or
LineageOS. To just use Nura, follow [INSTALL-NURA.md](INSTALL-NURA.md)
instead; LineageOS on its own is a TWRP zip ([newest release](https://github.com/devilAPI/zte-axon7/releases/tag/lineageos-latest)).
iOS is **alpha**: no downloads; this guide builds iOS and the multi-boot
LineageOS from source.

Written for people who have flashed custom ROMs before (TWRP, ADB). Every
step is a button press or a command you can copy.

> **State (2026-11-08)**
>
> | | Status |
> |---|---|
> | Boot menu (choose the OS at power-on) | works |
> | iOS 16.7.16 | boots to the home screen, touch, Wi-Fi, GPU, Sileo (jailbreak). No calls/mobile data, no camera, no audio. |
> | Nura (postmarketOS, Linux) | boots from the microSD card: display, touch, on-screen keyboard, Wi-Fi, Bluetooth, SSH, USB OTG (mouse, keyboard, stick). No calls, no audio, no camera. |
> | LineageOS 22 (Android 15) | **unofficial release**: almost all hardware works (see [lineageos/README.md](lineageos/README.md)); on its own as a TWRP zip, here in the multi-boot slot built from source |
>
> There are **no ready-made downloads** yet: Apple's iOS and the phone's
> firmware may not be redistributed, so the guide builds them on your PC
> from Apple's own IPSW and from your own phone. Allow an afternoon.

---

## ⚠️ Read this first

- Tested on the **A2017G** (global, 4 GB / 64 GB) only. Other models (A2017U, A2017 China) are untested: don't.
- **Your internal storage is erased** (iOS lives in `userdata`). **Your microSD card is erased** (Nura lives on it). Copy your photos and files off the phone first.
- Bootloader, modem, EFS/IMEI and recovery are **never** touched. If something goes wrong you can always get back to TWRP (see *Rescue*).
- This is experimental software. Not for your daily phone.

## What you need

**Phone:** ZTE Axon 7 A2017G, **bootloader unlocked**, **TWRP** as recovery
(3.3.0 or newer; 3.7.0_9-0: [dl.twrp.me/ailsa_ii](https://dl.twrp.me/ailsa_ii/twrp-3.7.0_9-0-ailsa_ii.img.html)), ideally
LineageOS 16–18.1 installed before (its `vendor` partition holds the GPU
firmware the guide copies). A microSD card (8 GB or more) for Nura.
Charge to at least 50 %.

**PC:** Linux (Debian/Ubuntu/Arch/Fedora all work) with about 60 GB free space,
`sudo` rights and internet. Install:

```sh
# Debian / Ubuntu:
sudo apt install git adb python3 clang lld llvm zstd gzip hfsprogs rsync lzfse apfs-fuse dtc
# Arch:      sudo pacman -S git android-tools python clang lld llvm zstd hfsprogs rsync dtc  (apfs-fuse, lzfse: AUR)
```

Get this repository:

```sh
git clone --recurse-submodules https://github.com/devilAPI/zte-axon7
cd zte-axon7/ios
```

All commands below are run in `zte-axon7/ios` unless stated otherwise.

**Buttons you will use:**

| | How |
|---|---|
| TWRP | phone off, hold **Power + Volume Up** until the ZTE logo, keep Volume Up until TWRP |
| Force restart | hold **Power + Volume Up** about 10 s (lands in TWRP) |
| Emergency download (EDL) | phone off, hold **Volume Up + Volume Down**, plug in USB (only for full restores, see *Rescue*) |

---

## Step 1: Backup (do not skip)

1. Boot TWRP, connect USB. `adb devices` must show the phone as `recovery`.
2. In TWRP: **Backup** → select **Boot, EFS, Modem** (and System/Data if you want to go back to Android later) → swipe. Copy the `TWRP` folder to your PC.
3. Also save the boot partition and the partition table on your PC:

```sh
mkdir -p backup
adb exec-out 'dd if=/dev/block/bootdevice/by-name/boot bs=1M 2>/dev/null' > backup/stock-lineage-boot.img
adb exec-out 'dd if=/dev/block/bootdevice/by-name/recovery bs=1M 2>/dev/null' > backup/recovery.img
ls -la backup/   # boot and recovery: 64 MB each
```

`backup/stock-lineage-boot.img` is needed later: the boot image is built from it.

## Step 2: Copy the firmware from your phone

Still in TWRP:

```sh
mkdir -p research/firmware/gpu research/firmware/wlan
adb shell 'mkdir -p /mnt/v /mnt/m; mount -o ro /dev/block/bootdevice/by-name/vendor /mnt/v; mount -o ro -t vfat /dev/block/bootdevice/by-name/modem /mnt/m'
for f in a530_pm4.fw a530_pfp.fw a530_zap.mdt a530_zap.b00 a530_zap.b01 a530_zap.b02; do adb pull /mnt/v/firmware/$f research/firmware/gpu/; done
adb pull /mnt/m/image/qwlan30.bin research/firmware/wlan/
adb pull /mnt/m/image/otp30.bin research/firmware/wlan/
adb pull /mnt/m/image/bdwlan30.bin research/firmware/wlan/
adb shell 'ls /mnt/m/image/ | grep "^bdwlan30.b"' | tr -d '\r' | while read f; do adb pull "/mnt/m/image/$f" research/firmware/wlan/; done
adb shell 'umount /mnt/v /mnt/m'
```

No `vendor/firmware` (stock ZTE firmware instead of LineageOS)? Try
`/system/vendor/firmware` after mounting `system` the same way.

## Step 3: iOS

### 3a. Build the iOS system image (on the PC, about an hour)

1. Download the iPhone 8 IPSW **iPhone_4.7_P3_16.7.16_20H392_Restore.ipsw** (Apple's file, e.g. via [ipsw.me](https://ipsw.me/iPhone10,1)).
2. It is a zip. Take out three files and put them into `research/ipsw-8/`:
   `087-86684-044.dmg` (the system), `087-86580-047.dmg`, `087-86715-047.dmg`.
3. Build:

```sh
tools/axon7-mkroot.sh            # -> research/axon7/ios16-root.img (16 GB), asks for your sudo password
tools/axon7-jailbreak.sh         # optional: Sileo + rootless jailbreak (/var/jb)
```

### 3b. Get the iOS kernel

Download the latest **xnu-kernel** artifact from the
[ios-sailfish Actions page](https://github.com/devilAPI/ios-sailfish/actions/workflows/xnu.yml)
(latest successful run on branch `axon7`; needs a GitHub login), unzip it,
keep `kernel.development.sweet`. Artifacts expire after 90 days: if none is
left, open an issue and ask for a new build.

### 3c. Flash (phone in TWRP)

**This erases your internal storage.**

```sh
tools/axon7-flashroot.sh                                     # iOS system -> userdata (10-30 min)
tools/axon7-flash-ios-kernel.sh ~/Downloads/kernel.development.sweet   # boot menu + kernel -> boot, reboots
```

After the ZTE logo you see the **boot menu**; after 10 s it starts iOS. The
first iOS boot takes a few minutes (it sets itself up).

## Step 4: Nura (postmarketOS)

### 4a. Build it (on the PC)

Nura is built with `pmbootstrap` (see [postmarketos/README.md](postmarketos/README.md) for details):

```sh
cd ../postmarketos
git clone https://gitlab.postmarketos.org/postmarketOS/pmbootstrap.git
cd pmbootstrap
python3 ./pmbootstrap.py init     # vendor "zte", device "axon7", user interface "console"
cp -r ../pmaports-local/device/testing/* "$(python3 ./pmbootstrap.py config aports)/device/testing/"
python3 ./pmbootstrap.py build linux-zte-axon7 firmware-zte-axon7 device-zte-axon7
python3 ./pmbootstrap.py install --password CHOOSE_A_PASSWORD
python3 ./pmbootstrap.py export   # -> /tmp/postmarketOS-export/zte-axon7.img
cd ../../ios
```

The firmware package needs a tarball made from your phone's firmware: before
the `build` line, with the phone in TWRP, run `scripts/axon7-firmware.sh` in
`zte-axon7/postmarketos`.

### 4b. Put it on the microSD card (phone in TWRP, card in the phone)

**This erases the microSD card.**

```sh
adb shell 'umount /external_sd; dd if=/dev/zero of=/dev/block/mmcblk0 bs=1M count=8'
adb push /tmp/postmarketOS-export/zte-axon7.img /tmp/pmos.img      # ~1 GB, takes a few minutes
adb shell 'simg2img /tmp/pmos.img /dev/block/mmcblk0 && sync && rm /tmp/pmos.img'
tools/axon7-dualboot-flash.sh      # adds Nura to the boot menu, iOS stays
adb reboot
```

In the menu choose **postmarketOS** (Nura; Volume Down, then Power). First boot
takes about a minute. Log in as `user` with your password; the on-screen
keyboard is at the bottom.

### 4c. In Nura: finish the setup (once)

```sh
sudo nmcli dev wifi connect "YOUR_WIFI" password "YOUR_PASSWORD"
sudo nmcli con mod "YOUR_WIFI" connection.autoconnect-retries 0   # keep reconnecting after a drop
sudo axon7-tripleboot-gpt          # partitions for kernel updates and LineageOS (keeps iOS, see below)
sudo /usr/libexec/axon7-dualboot-update
```

`axon7-tripleboot-gpt` shrinks the iOS partition to 20 GB (iOS uses 16 GB)
and adds the partitions Nura and LineageOS need. It checks
everything first, saves the old table in `/root/` (copy it to your PC) and
does nothing if it ran before. Without it, Nura kernel updates only
take effect after re-running `tools/axon7-dualboot-flash.sh` from TWRP.

## Using the boot menu

| | |
|---|---|
| **Volume Up / Down** | move the highlight |
| **Power** | start the highlighted OS |
| nothing pressed | the default starts after 10 s (iOS, unless you change it) |

Change the default from Nura: `sudo axon7-bootmenu default pmos 5`
(Nura after 5 s), `sudo axon7-bootmenu clear` (back to iOS).

## Updating

- **Nura:** `sudo apk upgrade -a`, then reboot. New kernels are put in place automatically (needs step 4c).
- **iOS kernel:** new `xnu-kernel` artifact → TWRP → `tools/axon7-flash-ios-kernel.sh kernel.development.sweet`.

## Tips for Nura

- **USB OTG** (mouse, keyboard, stick): just plug it in (USB-C plug or an OTG adapter); it works after about a second. A PC cable works as before (USB network, SSH).
- **OTG device not detected** (rare, some cheap adapters): `echo 1 | sudo tee /sys/module/pi5usb302/parameters/force_host`. Switch it **off again (`echo 0`) before connecting a PC**: otherwise both power the cable.
- **Bluetooth** (mouse, keyboard): `bluetoothctl`, then `scan on`, wait for the device, `pair XX:XX:...`, `trust XX:XX:...`, `connect XX:XX:...`, `exit`. The phone uses its original Bluetooth address from the factory. No Bluetooth audio yet (no sound yet).
- **Wi-Fi gone** (console still works): `sudo nmcli con up "YOUR_WIFI"`.
- **SSH:** over USB `ssh user@172.16.42.1`, over Wi-Fi to the phone's address.
- The screen of Nura is the text console with an on-screen keyboard (no graphical desktop yet).

## Rescue

- **iOS restarts about 25 s after every start** (images flashed before 2026-11-07): a watchdog in the boot menu reset it. Update the repository (`git pull --recurse-submodules`) and flash the iOS kernel again (step 3c, second command); nothing else changes.
- **Stuck on a black screen / logo:** hold **Power + Volume Up** ~10 s → TWRP.
- **Boot menu broken (phone always goes to TWRP or hangs):** in TWRP restore the boot partition:
  `adb push backup/stock-lineage-boot.img /tmp/b.img && adb shell dd if=/tmp/b.img of=/dev/block/bootdevice/by-name/boot`
- **Back to Android (LineageOS 18.1):** TWRP → Wipe → Format Data, then flash the ROM zip as described in [lineageos/FLASHING-PLAN.md](lineageos/FLASHING-PLAN.md). This removes iOS. If you ran `axon7-tripleboot-gpt`, restore the saved partition table first (from Nura: `sudo sfdisk /dev/sda < /root/axon7-lun0-before-tripleboot-*.sfdisk`), otherwise Android only sees 20 GB.
- **Nothing boots, not even TWRP:** EDL mode (above) and a full A2017G EDL package; see the *EDL rescue* note in [lineageos/FLASHING-PLAN.md](lineageos/FLASHING-PLAN.md). Not needed so far.

## Getting logs (for bug reports)

- iOS: in TWRP `tools/sweet-log-pull.sh ios-log.txt`
- boot menu: in TWRP `adb shell cat /sys/fs/pstore/pmsg-ramoops-0`
- Nura: `sudo dmesg > dmesg.txt`

Developer documentation: [ios/PORTING-AXON7.md](ios/PORTING-AXON7.md),
[postmarketos/README.md](postmarketos/README.md), [docs/](docs/).
