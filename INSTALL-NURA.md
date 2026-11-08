# Nura on the ZTE Axon 7: installation guide

Nura is Linux for the ZTE Axon 7 (A2017G), based on
[postmarketOS](https://postmarketos.org) with a mainline Linux 7.3 kernel.
This guide installs Nura **on its own**: Nura lives on the microSD card and
starts directly when you switch the phone on. (The multi-boot setup with iOS
and LineageOS is a development tool, see [DEV-MULTIBOOT.md](DEV-MULTIBOOT.md).)

For people who have flashed custom ROMs before (TWRP, ADB) but are not
developers. Every step is a button press or a command you can copy.

> **State: beta (2026-11-08)**
>
> | Works | Not yet |
> |---|---|
> | display, touch, on-screen keyboard, Wi-Fi, Bluetooth (mouse, keyboard), SSH over USB and Wi-Fi, USB OTG (mouse, keyboard, stick; automatic) | calls, SMS, mobile data, audio, camera, sensors, battery level and charging control, suspend; no graphical desktop yet (a text console with an on-screen keyboard) |
>
> There are **no ready-made downloads**: the phone's firmware may not be
> redistributed, so you build Nura on your PC with your own phone's firmware.
> Allow about two hours, most of it waiting.

---

## ⚠️ Read this first

- Tested on the **A2017G** (global, 4 GB / 64 GB) only. Other models (A2017U, A2017 China): don't.
- **Your microSD card is erased** (Nura lives on it).
- The phone's **`boot` partition is replaced** by Nura's kernel: Android no longer starts until you put your saved boot image back (see *Back to Android*). Your internal storage (photos, apps) is **not** touched.
- Bootloader, modem, EFS/IMEI and recovery are **never** touched. TWRP stays your way back.

## What you need

**Phone:** ZTE Axon 7 A2017G, **bootloader unlocked**, **TWRP** as recovery
(3.3.0 or newer; 3.7.0_9-0: [dl.twrp.me/ailsa_ii](https://dl.twrp.me/ailsa_ii/twrp-3.7.0_9-0-ailsa_ii.img.html)),
a ROM with a `vendor` partition installed (LineageOS 16 to 18.1: the GPU
firmware is copied from it). A **microSD card**, 8 GB or more. Charge to at
least 50 %.

**PC:** Linux (Debian/Ubuntu/Arch/Fedora all work) with about 15 GB free space,
`sudo` rights and internet. Install:

```sh
# Debian / Ubuntu:
sudo apt install git adb python3 android-sdk-libsparse-utils
# Arch:
sudo pacman -S git android-tools python
```

Get this repository:

```sh
git clone https://github.com/devilAPI/zte-axon7
cd zte-axon7/postmarketos
```

All commands below are run in `zte-axon7/postmarketos` unless stated otherwise.

**Buttons you will use:**

| | How |
|---|---|
| TWRP | phone off, hold **Power + Volume Up** until the ZTE logo, keep Volume Up until TWRP |
| Force restart | hold **Power + Volume Up** about 10 s (lands in TWRP) |

---

## Step 1: Backup (do not skip)

1. Boot TWRP, connect USB. `adb devices` must show the phone as `recovery`.
2. In TWRP: **Backup** → select **Boot, EFS, Modem** → swipe. Copy the `TWRP` folder to your PC.
3. Save the boot partition on your PC as well (you need it to go back to Android):

```sh
mkdir -p backup
adb exec-out 'dd if=/dev/block/bootdevice/by-name/boot bs=1M 2>/dev/null' > backup/android-boot.img
ls -la backup/   # 64 MB
```

## Step 2: Firmware from your phone (phone in TWRP)

```sh
scripts/axon7-firmware.sh
```

It reads (never writes) the `modem` and `vendor` partitions and makes the
firmware package for the build:
`pmaports-local/device/testing/firmware-zte-axon7/firmware-zte-axon7-1.tar.gz`.
Keep that file to yourself: the firmware belongs to Qualcomm and ZTE.

## Step 3: Build Nura (on the PC, 30-90 min)

Nura is built with postmarketOS's `pmbootstrap`:

```sh
git clone https://gitlab.postmarketos.org/postmarketOS/pmbootstrap.git
python3 pmbootstrap/pmbootstrap.py init
```

`init` asks a few questions: **vendor `zte`**, **device `axon7`**, **user
interface `console`**, the rest as offered. pmbootstrap doesn't know the Axon 7
yet, so it offers to start a new device port: say **yes**, answer its device
questions with anything (mainline port: yes); the next command replaces what it
creates with Nura's packages. Then:

```sh
cp -r pmaports-local/device/testing/* "$(python3 pmbootstrap/pmbootstrap.py config aports)/device/testing/"
python3 pmbootstrap/pmbootstrap.py build linux-zte-axon7 firmware-zte-axon7 device-zte-axon7
python3 pmbootstrap/pmbootstrap.py install --password CHOOSE_A_PASSWORD
python3 pmbootstrap/pmbootstrap.py export
ls -la /tmp/postmarketOS-export/     # boot.img and zte-axon7.img
```

`CHOOSE_A_PASSWORD` is the password of the user `user` on the phone (login
and `sudo`). Use digits only if you want to type it on the phone's keyboard
quickly.

## Step 4: Install (phone in TWRP, microSD card in the phone)

**This erases the microSD card and replaces the boot partition.**

```sh
adb shell 'umount /external_sd; dd if=/dev/zero of=/dev/block/mmcblk0 bs=1M count=8'
adb push /tmp/postmarketOS-export/zte-axon7.img /tmp/nura.img      # about 1 GB, a few minutes
adb shell 'simg2img /tmp/nura.img /dev/block/mmcblk0 && sync && rm /tmp/nura.img'
adb push /tmp/postmarketOS-export/boot.img /tmp/nura-boot.img
adb shell 'dd if=/tmp/nura-boot.img of=/dev/block/bootdevice/by-name/boot && sync && rm /tmp/nura-boot.img'
adb reboot
```

After the ZTE logo (and the orange "unlocked" warning) Nura starts; the first
boot takes about a minute. Log in as **`user`** with your password; the
on-screen keyboard is at the bottom of the screen.

## Step 5: First setup on the phone

```sh
sudo nmcli dev wifi connect "YOUR_WIFI" password "YOUR_PASSWORD"
sudo nmcli con mod "YOUR_WIFI" connection.autoconnect-retries 0   # keep reconnecting after a drop
```

From now on you can also log in from your PC: over USB `ssh user@172.16.42.1`,
over Wi-Fi `ssh user@PHONE_ADDRESS` (`ip addr` shows it).

## Updating

```sh
sudo apk upgrade -a
```

Programs are updated right away. A **new kernel** (package `linux-zte-axon7`)
needs one extra step, because the phone's `boot` partition can only be
written from TWRP: reboot into TWRP and run on the PC

```sh
adb shell 'mkdir -p /tmp/nb && mount /dev/block/mmcblk0p1 /tmp/nb && dd if=/tmp/nb/boot.img of=/dev/block/bootdevice/by-name/boot && sync; umount /tmp/nb'
adb reboot
```

(`mmcblk0p1` is Nura's boot partition on the card; `boot.img` there is always
the current kernel.)

## Tips

- **USB OTG** (mouse, keyboard, stick): just plug it in (USB-C plug or an OTG adapter); it works after about a second. A PC cable works as before (USB network, SSH).
- **OTG device not detected** (rare, some cheap adapters): `echo 1 | sudo tee /sys/module/pi5usb302/parameters/force_host`. Switch it **off again (`echo 0`) before connecting a PC**: otherwise both power the cable.
- **Bluetooth** (mouse, keyboard): `bluetoothctl`, then `scan on`, wait for the device, `pair XX:XX:...`, `trust XX:XX:...`, `connect XX:XX:...`, `exit`. The phone uses its own factory Bluetooth address. No Bluetooth audio (no audio yet).
- **Wi-Fi gone** (console still works): `sudo nmcli con up "YOUR_WIFI"`.
- **Charging:** battery level and charging control are not supported yet; charge the phone in TWRP or Android if it runs low.

## Back to Android

In TWRP:

```sh
adb push backup/android-boot.img /tmp/b.img && adb shell 'dd if=/tmp/b.img of=/dev/block/bootdevice/by-name/boot && sync'
adb reboot
```

Android starts as before (its data was never touched). The microSD card
still holds Nura: format it in Android to use it as a normal card again.

## Rescue

- **Black screen / hangs at the logo:** hold **Power + Volume Up** about 10 s → TWRP. Get the log (below), then either write the Nura boot image again (step 4, last three commands) or go back to Android.
- **Nothing boots, not even TWRP:** not seen so far. EDL mode (phone off, hold Volume Up + Volume Down, plug in USB) and a full A2017G EDL package; see the *EDL rescue* note in [lineageos/FLASHING-PLAN.md](lineageos/FLASHING-PLAN.md).

## Getting logs (for bug reports)

- Nura running: `sudo dmesg > dmesg.txt` (copy it to the PC with `scp user@172.16.42.1:dmesg.txt .`)
- Nura did not start: in TWRP `adb shell cat /sys/fs/pstore/console-ramoops*` (the kernel log of the failed start)

Developer documentation: [postmarketos/README.md](postmarketos/README.md), [docs/](docs/).
