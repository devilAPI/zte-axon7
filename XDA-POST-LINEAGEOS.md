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
[TR][TD]boots to the home screen, display, touch, encrypted storage, USB/adb, Wi-Fi, Bluetooth, NFC, flashlight, all 42 sensors, GPS service, fingerprint sensor driver, both cameras detected, sound (speaker; AK4961 codec + AK4490 Hi-Fi DAC drivers), modem services for both SIM slots (dual SIM)[/TD][TD]rear camera (no picture sizes yet, the camera app crashes), screen colours differ between the left and right half after waking, the phone sometimes wakes up or locks by itself, flashlight tile says "Camera in use", volume cannot be changed, fingerprint enrolment (untested), calls/data with a SIM (untested)[/TD][/TR]
[/TABLE]

[SIZE=5][B]Installation[/B][/SIZE]
[B]No downloads and no flashable zips during the alpha.[/B] Flashable zips come with the first beta.
Developers can build it from source; the developer setup (a multi-boot with iOS and Nura on one phone) is described here: [URL='https://github.com/devilAPI/zte-axon7/blob/main/DEV-MULTIBOOT.md']DEV-MULTIBOOT.md[/URL]

[SIZE=5][B]Changelog[/B][/SIZE]
[SPOILER="2026-11-08"]
[LIST]
[*]Sound is audible (confirmed on the phone); the volume cannot be changed yet.
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
[URL='https://github.com/devilAPI/zte-axon7']github.com/devilAPI/zte-axon7[/URL] (folder lineageos: device tree patches, kernel patches, Android tree patches)
The same project also brings Nura (Linux, beta) and iOS 16 (alpha) to the Axon 7, each with its own thread.

[SIZE=5][B]Credits[/B][/SIZE]
LineageOS, the Axon 7 LineageOS maintainers (device tree base), ZTE (kernel source), TWRP.

[I]Not affiliated with ZTE or LineageOS. You flash this at your own risk.[/I]
```
<!-- XDA-POST-END -->
