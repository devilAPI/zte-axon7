# XDA thread: first post (BBCode)

The first post of the XDA thread, kept current with every user-visible
change (status table, changelog). Only things confirmed on the phone go into
the "works" columns; "built, untested" is said as such.

To update the thread: copy everything between the two marker lines into the
XDA editor (switch the editor to BBCode mode with the `[ ]` button first),
replacing the old text, then save.

Last update: 2026-11-08

<!-- XDA-POST-BEGIN -->
```bbcode
[CENTER][SIZE=6][B]ZTE Axon 7 (A2017G): iOS 16 + postmarketOS + LineageOS 22 multi-boot[/B][/SIZE]
[I]Choose the OS at power-on. Experimental, not for your daily phone.[/I][/CENTER]

[SIZE=5][B]What is this?[/B][/SIZE]
A boot menu for the ZTE Axon 7 that starts one of three systems:
[LIST]
[*][B]iOS 16.7.16[/B] (Apple's XNU kernel on the Snapdragon 820, built on your PC from Apple's own IPSW)
[*][B]postmarketOS[/B] (Linux, mainline kernel, runs from the microSD card)
[*][B]LineageOS 22.2[/B] (Android 15, on its own partitions next to the other two)
[/LIST]
Bootloader, modem, EFS/IMEI and recovery are never touched. TWRP stays your way back.

[SIZE=5][B]Status (2026-11-08)[/B][/SIZE]
[TABLE]
[TR][TH][/TH][TH]Works[/TH][TH]Does not work / not tested[/TH][/TR]
[TR][TD][B]Boot menu[/B][/TD][TD]choose iOS / postmarketOS / LineageOS with the volume keys, remembers a default[/TD][TD][/TD][/TR]
[TR][TD][B]iOS 16.7.16[/B][/TD][TD]home screen, touch, Wi-Fi, GPU, Sileo (jailbreak)[/TD][TD]calls, mobile data, camera, audio[/TD][/TR]
[TR][TD][B]postmarketOS[/B][/TD][TD]display, touch, on-screen keyboard, Wi-Fi, Bluetooth, SSH, USB OTG[/TD][TD]calls, audio, camera[/TD][/TR]
[TR][TD][B]LineageOS 22.2[/B][/TD][TD][I]developer builds only, not released yet:[/I] boots to the home screen, display, touch, encrypted storage, USB/adb, Wi-Fi, Bluetooth, NFC, flashlight, all 42 sensors, GPS service, fingerprint sensor driver, both cameras detected, sound card and audio routing (AK4961 + AK4490 Hi-Fi DAC), modem starts and its services come up[/TD][TD]camera app (crashes on a bad stream size), sound actually audible and fingerprint enrolment (untested), dual SIM (in test), calls/data with a SIM (untested), screen colours on one half after waking[/TD][/TR]
[/TABLE]

[SIZE=5][B]Installation[/B][/SIZE]
There are [B]no ready-made downloads[/B]: Apple's iOS and the phone's firmware may not be redistributed, so the guide builds everything on your PC from Apple's own IPSW and from your own phone. Allow an afternoon.
[LIST]
[*]Tested on the [B]A2017G[/B] (4 GB / 64 GB) only. Other models: don't.
[*]Your [B]internal storage and microSD card are erased[/B].
[*]You need: unlocked bootloader, TWRP 3.3.0 or newer, a Linux PC with about 60 GB free.
[/LIST]
Step-by-step guide: [URL='https://github.com/devilAPI/zte-axon7/blob/main/INSTALL.md']INSTALL.md on GitHub[/URL]
LineageOS has no install steps yet; they come with the first release.

[SIZE=5][B]Changelog[/B][/SIZE]
[SPOILER="2026-11-08"]
[LIST]
[*]LineageOS: Bluetooth works.
[*]LineageOS: the modem's radio service (rild) runs on Android 15's new radio interface; the Qualcomm modem daemons no longer crash.
[*]LineageOS: fingerprint sensor driver (Goodix, ported from ZTE's kernel) works; enrolling a finger is not tested yet.
[*]LineageOS: both cameras are detected (Android 15 needs the HAL3 mode of the camera blob); flashlight works.
[*]LineageOS: NFC works (PN548 driver ported from ZTE's kernel).
[*]LineageOS: audio: the sound card comes up (AK4961 codec and AK4490 Hi-Fi DAC drivers ported from ZTE's kernel); the audio HAL routes sound and switches the speaker amplifier on. Not yet confirmed audible.
[*]LineageOS: telephony starts cleanly (single SIM for now).
[/LIST]
[/SPOILER]
[SPOILER="2026-11-07"]
[LIST]
[*]LineageOS 22.2 (developer builds): first boot to the setup wizard in the multi-boot setup; encrypted storage on its own partition, display, USB/adb, battery and charging info.
[*]LineageOS: Wi-Fi works; all 42 sensors are detected.
[*]LineageOS: the modem starts and its services register with Android 15 (new radio service on top of Qualcomm's RIL); mobile data and IMS daemons no longer crash.
[/LIST]
[/SPOILER]

[SIZE=5][B]Source[/B][/SIZE]
[URL='https://github.com/devilAPI/zte-axon7']github.com/devilAPI/zte-axon7[/URL] (boot menu, iOS port, postmarketOS and LineageOS device trees, kernel patches)

[SIZE=5][B]Credits[/B][/SIZE]
TWRP, LineageOS, postmarketOS, the Axon 7 LineageOS maintainers (device tree base), Apple's open-source XNU.

[I]Not affiliated with ZTE, Apple, LineageOS or postmarketOS. You flash this at your own risk.[/I]
```
<!-- XDA-POST-END -->
