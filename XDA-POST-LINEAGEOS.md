# XDA thread: LineageOS 22.2 (first post, BBCode)

The first post of the LineageOS thread, kept current with every user-visible
change (status table, changelog). Only things confirmed on the phone go into
the "works" column; "built, untested" is said as such.

To update the thread: copy everything between the two marker lines into the
XDA editor (switch the editor to BBCode mode with the `[ ]` button first),
replacing the old text, then save.

Last update: 2026-11-08

<!-- XDA-POST-BEGIN -->
```bbcode
[CENTER][SIZE=6][B][ALPHA] LineageOS 22.2 (Android 15) for the ZTE Axon 7 (A2017G)[/B][/SIZE]
[I]Android 15 on the 4.4 kernel, with ZTE's drivers ported from their 3.18 kernel.[/I][/CENTER]

[SIZE=5][B]What is this?[/B][/SIZE]
A port of LineageOS 22.2 (Android 15) to the ZTE Axon 7. The newest official LineageOS for the phone is 18.1; this one runs on the msm8996 4.4 kernel with ZTE's own drivers (audio codec, fingerprint, NFC, camera parts) ported from ZTE's 3.18 kernel, and Android 15 shims for the old vendor blobs.
Phase: [B]alpha[/B]. Developer builds only.

[SIZE=5][B]Status (2026-11-08)[/B][/SIZE]
[TABLE]
[TR][TH]Works[/TH][TH]Does not work / not tested[/TH][/TR]
[TR][TD]boots to the home screen, display, brightness, touch and the three touch keys, battery level, encrypted storage, USB/adb, Wi-Fi, Bluetooth (also audio to speakers), Wi-Fi hotspot, NFC, flashlight, all 42 sensors, GPS service, fingerprint (enrolment works), both cameras with optical image stabilisation, sound and volume (speaker; AK4961 codec + AK4490 Hi-Fi DAC drivers), modem services for both SIM slots (dual SIM)[/TD][TD]GPS (no position yet), the phone sometimes wakes up or locks by itself, calls/data with a SIM (untested)[/TD][/TR]
[/TABLE]

[SIZE=5][B]Installation[/B][/SIZE]
[B]No downloads and no flashable zips during the alpha.[/B] Flashable zips come with the first beta.
Developers can build it from source; the developer setup (a multi-boot with iOS and Nura on one phone) is described here: [URL='https://github.com/devilAPI/zte-axon7/blob/main/DEV-MULTIBOOT.md']DEV-MULTIBOOT.md[/URL]

[SIZE=5][B]Changelog[/B][/SIZE]
[SPOILER="2026-11-08"]
[LIST]
[*]The battery icon sits at the right edge of the status bar (Android kept space free there for a privacy dot).
[*]Screen colours stay correct after waking (a colour table of the display engine lost its contents during sleep and turned colours into rainbow blocks on each half).
[*]Battery percentage is shown correctly (was stuck at 50 %; the battery profile is now chosen by name, as ZTE does).
[*]Back key works (it was sent as a Menu key).
[*]Bluetooth audio to speakers works.
[*]Wi-Fi hotspot can be switched on and off, and Wi-Fi has internet again afterwards (the device declared a tethering offload driver that does not exist; Android waited for it forever).
[*]Front camera works (the image processor speaks ZTE's camera interface now).
[*]Rear camera works, with optical image stabilisation (the kernel ran Xiaomi's stabiliser firmware routine on ZTE's module, which blocked the camera's I2C bus; ZTE's camera software loads the right firmware itself).
[*]Sound is audible and the volume works (the audio policy lost all volume steps over a missing Bluetooth include).
[*]The brightness slider works (the Samsung panel needs ZTE's brightness command sequence in high-speed mode).
[*]Fingerprint enrolment works (ZTE's fingerprint HAL no longer depends on an Android framework library).
[*]Bluetooth works.
[*]The modem's radio service (rild) runs on Android 15's new radio interface; the Qualcomm modem daemons no longer crash.
[*]Fingerprint sensor driver (Goodix, ported from ZTE's kernel) works; enrolling a finger is not tested yet.
[*]Both cameras are detected (Android 15 needs the HAL3 mode of the camera blob); flashlight works.
[*]NFC works (PN548 driver ported from ZTE's kernel).
[*]Audio: the sound card comes up (AK4961 codec and AK4490 Hi-Fi DAC drivers ported from ZTE's kernel); the audio HAL routes sound and switches the speaker amplifier on.
[*]Telephony starts cleanly with both SIM slots (dual SIM, one radio service per slot).
[/LIST]
[/SPOILER]
[SPOILER="2026-11-07"]
[LIST]
[*]First boot to the setup wizard: encrypted storage on its own partition, display, USB/adb, battery and charging info.
[*]Wi-Fi works; all 42 sensors are detected.
[*]The modem starts and its services register with Android 15 (new radio service on top of Qualcomm's RIL); mobile data and IMS daemons no longer crash.
[/LIST]
[/SPOILER]

[SIZE=5][B]Source[/B][/SIZE]
[B]Kernel source (GPLv2):[/B] [URL='https://github.com/devilAPI/android_kernel_zte_msm8996/tree/axon7']github.com/devilAPI/android_kernel_zte_msm8996, branch axon7[/URL] (Linux 4.4, LineageOS msm8996 kernel with the Axon 7 drivers and fixes)
Device tree, Android patches and build notes: [URL='https://github.com/devilAPI/zte-axon7']github.com/devilAPI/zte-axon7[/URL] (folder lineageos)
The same project also brings Nura (Linux, beta) and iOS 16 (alpha) to the Axon 7, each with its own thread.

[SIZE=5][B]Credits[/B][/SIZE]
LineageOS, the Axon 7 LineageOS maintainers (device tree base), ZTE (kernel source), TWRP.

[I]Not affiliated with ZTE or LineageOS. You flash this at your own risk.[/I]
```
<!-- XDA-POST-END -->
