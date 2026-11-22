# Nura on the ZTE Axon 7: installation guide

Nura is Linux for the ZTE Axon 7, based on
[postmarketOS](https://postmarketos.org) with a mainline Linux 7.3 kernel.
It is developed and tested on the **A2017G**; A2017U (US) and A2017 (China)
share the hardware but are untested (see *A2017U owners* below).
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
> **Ready-made download** (two files, no PC tools needed besides an image
> writer). Nura contains no firmware of Qualcomm or ZTE: at its first start it
> copies the firmware from your phone's own partitions and restarts once.

---

## ⚠️ Read this first

- Developed and tested on the **A2017G** (global, 4 GB / 64 GB). The **A2017U** (US) and **A2017** (China) use the same SoC, display, touch and UFS layout but are untested here; their modem/band firmware and stock software differ. On a stock A2017U B35 there is no fastboot, so the unlock step is different (see *A2017U owners*). Cellular is untested on A2017U.
- **Your microSD card is erased** (Nura lives on it).
- The phone's **`boot` partition is replaced** by Nura's kernel: Android no longer starts until you put your saved boot image back (see *Back to Android*). Your internal storage (photos, apps) is **not** touched.
- Bootloader, modem, EFS/IMEI and recovery are **never** touched. TWRP stays your way back.

### A2017U owners (US model)

The install itself is the same TWRP/sdcard procedure (Nura does not need fastboot and does not need a vendor partition). Three things are different before step 1:

- **Getting root/recovery:** stock A2017U B35 has no fastboot endpoint. The route that worked for the reporter of [issue #1](https://github.com/devilAPI/zte-axon7/issues/1) was an **EDL flash** (phone off, hold Volume Up + Volume Down, plug in USB) of the **B15-NEW `aboot` + `fbop`** from the archived full EDL package, which restores `fastboot oem unlock`; **B29 alone was not enough**. Those packages overwrite recovery, so **flash TWRP again afterwards**.
- **Modem/firmware:** use an A2017U (US) modem/firmware base, never an A2017G one. At its first start Nura copies the files from your phone's `modem`, `vendor` (or `system`) partitions read-only; with no vendor partition it falls back to the stock firmware path in `system` (r27 and newer). Nothing is written to those partitions.
- **Cellular:** calls, SMS and mobile data are **untested** on A2017U. Nura's modem starts and goes online on the A2017G, but that does not prove the U's different modem path works. Do not rely on it.

Run `tools/axon7-preflight.sh --rom nura` in TWRP before starting (read-only). If you also want LineageOS 22.2 on the same phone, its ext4/f2fs and vendor-partition requirements are separate; read [docs/variant-a2017u.md](docs/variant-a2017u.md).

## What you need

**Phone:** ZTE Axon 7 A2017G (tested) or A2017U/A2017 (untested, see above), **bootloader unlocked**, **TWRP** as recovery
(3.3.0 or newer; 3.7.0_9-0: [dl.twrp.me/ailsa_ii](https://dl.twrp.me/ailsa_ii/twrp-3.7.0_9-0-ailsa_ii.img.html)),
an Android ROM installed (ideally LineageOS 16 to 18.1: Nura takes the GPU
firmware from its `vendor` partition). A **microSD card**, 8 GB or more.
Charge to at least 50 %.

**Computer:** any (Windows, macOS, Linux) with a microSD card reader and
[balenaEtcher](https://etcher.balena.io/) (or another image writer).

**Download** ([newest release](https://github.com/devilAPI/zte-axon7/releases/tag/nura-latest) on GitHub, also linked in the XDA thread):

| File | What it is |
|---|---|
| `nura-axon7-DATE-sdcard.img.xz` | Nura itself, for the microSD card |
| `nura-axon7-DATE-boot.img` | Nura's kernel, for the phone's `boot` partition |

**Buttons you will use:**

| | How |
|---|---|
| TWRP | phone off, hold **Power + Volume Up** until the ZTE logo, keep Volume Up until TWRP |
| Force restart | hold **Power + Volume Up** about 10 s (lands in TWRP) |

---

## Step 1: Backup (do not skip)

In TWRP: **Backup** → select **Boot** (and EFS, Modem) → swipe. Copy the
`TWRP` folder from the phone to your computer. The **Boot** backup is your
way back to Android.

## Step 2: Nura onto the microSD card (on the computer)

**This erases the microSD card.**

1. Put the card into the computer's card reader.
2. Open balenaEtcher → **Flash from file** → `nura-axon7-DATE-sdcard.img.xz` (no need to unpack it) → **Select target**: the microSD card (check the size!) → **Flash**.
3. Put the card into the phone.

## Step 3: Nura's kernel into the boot partition (in TWRP)

1. Copy `nura-axon7-DATE-boot.img` to the phone (connect USB in TWRP, it appears as a drive; or put it on a USB stick).
2. TWRP → **Install** → **Install Image** (bottom right) → choose `nura-axon7-DATE-boot.img` → **Boot** → swipe.
3. **Reboot** → **System**. If TWRP asks to install the TWRP app: **Do not install**.

## Step 4: First start

After the ZTE logo (and the orange "unlocked" warning) Nura starts. The
**first start restarts once by itself**: Nura copies the firmware for
modem, Wi-Fi and GPU from your phone's partitions (nothing is written to
them). After that a login prompt and the on-screen keyboard appear.

Log in as **`user`**, password **`nura`**, and **change the password right
away**:

```sh
passwd
```

Then connect to Wi-Fi:

```sh
sudo nmcli dev wifi connect "YOUR_WIFI" password "YOUR_PASSWORD"
sudo nmcli con mod "YOUR_WIFI" connection.autoconnect-retries 0   # keep reconnecting after a drop
```

From now on you can also log in from a computer: over USB `ssh user@172.16.42.1`,
over Wi-Fi `ssh user@PHONE_ADDRESS` (`ip addr` shows it).

## Building Nura yourself (instead of the download)

On a Linux PC with about 15 GB free and `sudo`:

```sh
git clone https://github.com/devilAPI/zte-axon7
cd zte-axon7/postmarketos
git clone https://gitlab.postmarketos.org/postmarketOS/pmbootstrap.git
python3 pmbootstrap/pmbootstrap.py init
```

`init` asks a few questions: **vendor `zte`**, **device `axon7`**, **user
interface `console`**, the rest as offered. pmbootstrap doesn't know the Axon 7
yet, so it offers to start a new device port: say **yes**, answer its device
questions with anything (mainline port: yes); the next command replaces what it
creates with Nura's packages. Then:

```sh
NURA_PASSWORD=nura scripts/nura-release.sh   # 30-90 min; out/release/: the same two files as the download
```

Continue with step 1 above. (Developers: [postmarketos/README.md](postmarketos/README.md).)

## Updating

```sh
sudo apk upgrade -a
```

Programs are updated right away. A **new kernel** (package `linux-zte-axon7`)
needs one extra step, because the phone's `boot` partition can only be
written from TWRP: copy the new kernel next to your files first

```sh
cp /boot/boot.img ~/nura-boot.img
```

copy it to the computer (`scp user@172.16.42.1:nura-boot.img .`), reboot
into TWRP, copy it to the phone over USB and flash it as in step 3. (TWRP
cannot see the files on Nura's card.)

## Tips

- **USB OTG** (mouse, keyboard, stick): just plug it in (USB-C plug or an OTG adapter); it works after about a second. A PC cable works as before (USB network, SSH).
- **OTG device not detected** (rare, some cheap adapters): `echo 1 | sudo tee /sys/module/pi5usb302/parameters/force_host`. Switch it **off again (`echo 0`) before connecting a PC**: otherwise both power the cable.
- **Bluetooth** (mouse, keyboard): `bluetoothctl`, then `scan on`, wait for the device, `pair XX:XX:...`, `trust XX:XX:...`, `connect XX:XX:...`, `exit`. The phone uses its own factory Bluetooth address. No Bluetooth audio (no audio yet).
- **Wi-Fi gone** (console still works): `sudo nmcli con up "YOUR_WIFI"`.
- **Charging:** battery level and charging control are not supported yet; charge the phone in TWRP or Android if it runs low.
- **First start without firmware** (no `modem` partition contents, e.g. after an EDL wipe): Nura still starts, without Wi-Fi; `journalctl -u axon7-firmware` says what was missing.

## Back to Android

In TWRP: **Restore** → your backup → select only **Boot** → swipe →
**Reboot** → **System**. Android starts as before (its data was never touched). The microSD card
still holds Nura: format it in Android to use it as a normal card again.

## Rescue

- **Black screen / hangs at the logo:** hold **Power + Volume Up** about 10 s → TWRP. Get the log (below), then either flash the Nura boot image again (step 3) or go back to Android.
- **Nothing boots, not even TWRP:** not seen so far. EDL mode (phone off, hold Volume Up + Volume Down, plug in USB) and a **full EDL package for your model** (A2017G, A2017U or A2017; never cross-flash one model's package onto another); see the *EDL rescue* note in [lineageos-22.2/FLASHING-PLAN.md](lineageos-22.2/FLASHING-PLAN.md).

## Getting logs (for bug reports)

- Nura running: `sudo dmesg > dmesg.txt` (copy it to the PC with `scp user@172.16.42.1:dmesg.txt .`)
- Nura did not start: in TWRP **Advanced → Terminal**, `cat /sys/fs/pstore/console-ramoops* > /sdcard/nura-log.txt`, then copy `nura-log.txt` to the computer (the kernel log of the failed start)

Developer documentation: [postmarketos/README.md](postmarketos/README.md), [docs/](docs/).
