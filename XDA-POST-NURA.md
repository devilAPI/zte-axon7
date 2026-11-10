# XDA thread: Nura (first post, BBCode)

The first post of the Nura thread, kept current with every user-visible
change (status table, changelog). Only things confirmed on the phone go into
the "works" column.

To update the thread: copy everything between the two marker lines into the
XDA editor (switch the editor to BBCode mode with the `[ ]` button first),
replacing the old text, then save.

Last update: 2026-11-09 (evening: battery, Hi-Fi audio, vibration, torch, cover)

First image release published 2026-11-09 (nura-20261109), tested on the
phone from a freshly written card: first start with the firmware copy, the
root partition grows to the card, modem online, Wi-Fi, GPS engine. The
"Nura images" workflow builds every change into a draft release (nura-DATE);
publish it after testing and the `nura-latest` link in this post follows.

<!-- XDA-POST-BEGIN -->
```bbcode
[CENTER][SIZE=6][B][BETA] Nura: Linux for the ZTE Axon 7 (A2017G)[/B][/SIZE]
[I]Mainline Linux 7.3, based on postmarketOS. Runs from the microSD card.[/I][/CENTER]

[SIZE=5][B]What is Nura?[/B][/SIZE]
Nura is a Linux system for the ZTE Axon 7, built on [URL='https://postmarketos.org']postmarketOS[/URL] with a current mainline kernel (Linux 7.3.1) instead of the old Android kernel. It lives on the microSD card; your internal storage is not touched.
Phase: [B]beta[/B]. What works, works reliably so far; a lot is still missing (see below).

[SIZE=5][B]Status (2026-11-09)[/B][/SIZE]
[SPOILER="Works"]
[LIST]
[*]Display
[*]Touch
[*]On-screen keyboard
[*]Wi-Fi (also roaming between 2.4 and 5 GHz)
[*]Bluetooth (mouse, keyboard; factory Bluetooth address)
[*]SSH over USB and Wi-Fi
[*]USB OTG (mouse, keyboard, USB stick; automatic)
[*]Battery level, voltage, current and temperature
[*]Charging control: charges to 4.4 V like stock, up to 2 A (stock reaches 3 A with a second charger chip that has no driver yet)
[*]Speakers (heard by the phone's own microphone)
[*]Microphone (bottom microphone)
[*]Earpiece (top speaker through the earpiece opening)
[*]Vibration (heard by the microphone)
[/LIST]
[/SPOILER]
[B]New, still to be confirmed by eye or ear:[/B]
[LIST]
[*]Headphone audio through the Hi-Fi DAC (AK4490)
[*]Flashlight (torch)
[*]Flip cover sensor (open is confirmed, closed not yet)
[/LIST]
[B]Not yet:[/B]
[LIST]
[*]Calls
[*]SMS
[*]Mobile data
[*]Second/third microphone, headset microphone, calls
[*]Camera apps (the front camera delivers raw pictures, see changelog; the rear camera has no driver yet)
[*]Sensors
[*]Fast charging above 2 A (second charger chip SMB1351)
[*]Suspend
[*]No graphical desktop yet (text console with an on-screen keyboard)
[/LIST]

[SIZE=5][B]Installation[/B][/SIZE]
[LIST]
[*]Tested on the [B]A2017G[/B] (4 GB / 64 GB) only. Other models: don't.
[*]Your [B]microSD card is erased[/B]; the [B]boot partition is replaced[/B] (restore your TWRP Boot backup to go back to Android). Internal storage stays as it is.
[*]You need: unlocked bootloader, TWRP 3.3.0 or newer, a microSD card (8 GB+), a computer with an image writer (balenaEtcher).
[/LIST]
[B]Download:[/B] [URL='https://github.com/devilAPI/zte-axon7/releases/tag/nura-latest']newest release[/URL]: [I]nura-axon7-DATE-sdcard.img.xz[/I] (microSD card) and [I]nura-axon7-DATE-boot.img[/I] (kernel).
Nura contains no Qualcomm/ZTE firmware: at the first start it copies the firmware from your phone's own partitions and restarts once.

[B]Short version:[/B]
[LIST=1]
[*]TWRP: back up [B]Boot[/B].
[*]Computer: write the sdcard image to the microSD card with balenaEtcher, put the card into the phone.
[*]TWRP: Install → Install Image → the boot.img → [B]Boot[/B] → Reboot.
[*]Log in as [B]user[/B] / [B]nura[/B] and change the password with [I]passwd[/I].
[/LIST]
Full guide with Wi-Fi setup, updates and the way back to Android: [URL='https://github.com/devilAPI/zte-axon7/blob/main/INSTALL-NURA.md']INSTALL-NURA.md[/URL]

[SIZE=5][B]Changelog[/B][/SIZE]
[SPOILER="2026-11-09"]
[LIST]
[*]The modem starts and switches itself on (it needed room for its file-system buffer above the kernel, and someone to set it online). It restarts itself a few times in the first two minutes after power-on; it is switched on again each time.
[*]Nura uses the whole microSD card: the system partition grows to the card size at the first start (it stayed at 1.2 GB before).
[*]GPS: the console tool [I]sudo axon7-gps --status[/I] shows the satellites and the position; [I]axon7-gps --nmea[/I] gives NMEA for other programs. Outdoors the first fix takes about 10 minutes, indoors there is usually none.
[*]A memory region that ZTE reserves for the modem side (vlog) is kept free.
[*]Battery level: the fuel gauge reports level, voltage, current and temperature ([I]cat /sys/class/power_supply/qcom-battery/capacity[/I]). It only reads; charging still works as the bootloader set it up.
[*]Headphone audio through the Hi-Fi DAC: the sound card "ZTE Axon 7" plays through the AK4490 to the headphone jack ([I]speaker-test -c 2 -t sine[/I]). New, please tell us if you hear it.
[*]Vibration (force-feedback rumble) and the flashlight ([I]echo 10 | sudo tee /sys/class/leds/white:torch/brightness[/I], 1-16). New, please confirm.
[*]Flip cover sensor: reported as a lid switch. Closing a cover does nothing yet, because suspend doesn't work.
[*]Charging: Nura now controls the charger. It charges to 4.4 V like the stock software (before, the bootloader's 4.2 V setting stayed, so the battery never got full) with up to 2 A, and the battery status shows Charging/Full.
[*]A crash in the battery driver that froze the phone when the charger driver appeared is fixed, and a hardware watchdog now restarts the phone if the kernel ever hangs.
[*]Front camera (OV8856): raw 8-megapixel pictures through the mainline camera subsystem (developers: media-ctl + v4l2-ctl, see the README). No camera app yet; the rear camera (Samsung S5K2T8) has no mainline driver.
[*]Wi-Fi is reliable again: the kernel from 2026-11-08 had been put back by mistake on some development installs.
[*]Speakers and microphone: the main codec (AK4961) runs on the mainline kernel and feeds both speaker amplifiers; a test tone on the speakers is picked up loudly by the bottom microphone. Keep the volume moderate (no speaker protection profile yet). In the sound settings: "Speakers", "Headphones", "Earpiece", "Microphone".
[/LIST]
[/SPOILER]
[SPOILER="2026-11-08"]
[LIST]
[*]The postmarketOS port is now called [B]Nura[/B] and is in beta.
[*]Install guide for Nura on its own (no multi-boot).
[*]Ready-made images: the firmware comes from your phone at the first start, so nothing proprietary is in the download.
[/LIST]
[/SPOILER]
[SPOILER="2026-11-06"]
[LIST]
[*]Boots from the microSD card: display (Samsung S6E3HA3, both DSI links), touch, on-screen keyboard with a large console font, Wi-Fi, SSH.
[*]USB OTG works automatically (Pericom PI5USB302 Type-C driver).
[*]Wi-Fi roaming fixed: switching between 2.4 and 5 GHz takes half a second instead of minutes.
[*]Bluetooth with the phone's own factory address.
[/LIST]
[/SPOILER]

[SIZE=5][B]Source[/B][/SIZE]
[B]Kernel source (GPLv2):[/B] [URL='https://github.com/devilAPI/linux/tree/zte-axon7']github.com/devilAPI/linux, branch zte-axon7[/URL] (Linux 7.3.1 with the Axon 7 patches); kernel configuration: [URL='https://github.com/devilAPI/zte-axon7/blob/main/postmarketos/pmaports-local/device/testing/linux-zte-axon7/config-zte-axon7.aarch64']config-zte-axon7.aarch64[/URL]
Packages, build scripts and docs: [URL='https://github.com/devilAPI/zte-axon7']github.com/devilAPI/zte-axon7[/URL] (folder postmarketos)
The same project also brings LineageOS 22.2 (unofficial release) and iOS 16 (alpha) to the Axon 7, each with its own thread.

[SIZE=5][B]Credits[/B][/SIZE]
postmarketOS, the mainline Linux and msm8996 mainline developers, Richard Acayan (ath10k key-deletion fix), TWRP.

[I]Not affiliated with ZTE or postmarketOS. You flash this at your own risk.[/I]
```
<!-- XDA-POST-END -->
