# XDA thread: Nura (first post, BBCode)

The first post of the Nura thread, kept current with every user-visible
change (status table, changelog). Only things confirmed on the phone go into
the "works" column.

To update the thread: copy everything between the two marker lines into the
XDA editor (switch the editor to BBCode mode with the `[ ]` button first),
replacing the old text, then save.

Last update: 2026-11-08

**Before the first post:** the install without the boot menu
(INSTALL-NURA.md) still has to be confirmed once on a phone.

<!-- XDA-POST-BEGIN -->
```bbcode
[CENTER][SIZE=6][B][BETA] Nura: Linux for the ZTE Axon 7 (A2017G)[/B][/SIZE]
[I]Mainline Linux 7.3, based on postmarketOS. Runs from the microSD card.[/I][/CENTER]

[SIZE=5][B]What is Nura?[/B][/SIZE]
Nura is a Linux system for the ZTE Axon 7, built on [URL='https://postmarketos.org']postmarketOS[/URL] with a current mainline kernel (Linux 7.3.1) instead of the old Android kernel. It lives on the microSD card; your internal storage is not touched.
Phase: [B]beta[/B]. What works, works reliably so far; a lot is still missing (see below).

[SIZE=5][B]Status (2026-11-08)[/B][/SIZE]
[TABLE]
[TR][TH]Works[/TH][TH]Not yet[/TH][/TR]
[TR][TD]display, touch, on-screen keyboard, Wi-Fi (also roaming between 2.4 and 5 GHz), Bluetooth (mouse, keyboard; factory Bluetooth address), SSH over USB and Wi-Fi, USB OTG (mouse, keyboard, USB stick; automatic)[/TD][TD]calls, SMS, mobile data, audio, camera, sensors, battery level and charging control, suspend; no graphical desktop yet (text console with an on-screen keyboard)[/TD][/TR]
[/TABLE]

[SIZE=5][B]Installation[/B][/SIZE]
There is [B]no ready-made download[/B]: the phone's firmware may not be redistributed, so you build Nura on a Linux PC with the firmware of your own phone (one script reads it from the phone in TWRP). Allow about two hours, most of it waiting.
[LIST]
[*]Tested on the [B]A2017G[/B] (4 GB / 64 GB) only. Other models: don't.
[*]Your [B]microSD card is erased[/B]; the [B]boot partition is replaced[/B] (Android starts again when you restore your boot backup). Internal storage stays as it is.
[*]You need: unlocked bootloader, TWRP 3.3.0 or newer, a microSD card (8 GB+), a Linux PC with about 15 GB free.
[/LIST]
Step-by-step guide: [URL='https://github.com/devilAPI/zte-axon7/blob/main/INSTALL-NURA.md']INSTALL-NURA.md on GitHub[/URL]

[SIZE=5][B]Changelog[/B][/SIZE]
[SPOILER="2026-11-08"]
[LIST]
[*]The postmarketOS port is now called [B]Nura[/B] and is in beta.
[*]Install guide for Nura on its own (no multi-boot), and a script that makes the firmware package from your phone.
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
The same project also brings LineageOS 22.2 and iOS 16 to the Axon 7 (both alpha, own threads).

[SIZE=5][B]Credits[/B][/SIZE]
postmarketOS, the mainline Linux and msm8996 mainline developers, Richard Acayan (ath10k key-deletion fix), TWRP.

[I]Not affiliated with ZTE or postmarketOS. You flash this at your own risk.[/I]
```
<!-- XDA-POST-END -->
