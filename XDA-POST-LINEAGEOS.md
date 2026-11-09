# XDA thread: LineageOS 22.2 (first post, BBCode)

The first post of the LineageOS thread, kept current with every user-visible
change (status table, changelog). Only things confirmed on the phone go into
the "works" column; "built, untested" is said as such.

To update the thread: copy everything between the two marker lines into the
XDA editor (switch the editor to BBCode mode with the `[ ]` button first),
replacing the old text, then save.

Last update: 2026-11-09

**Before posting this version:** the first TWRP zip must be tested on a phone
and published (Actions → "LineageOS 22.2 zip" → draft release → publish).

<!-- XDA-POST-BEGIN -->
```bbcode
[CENTER][SIZE=6][B][ROM][15][UNOFFICIAL] LineageOS 22.2 for the ZTE Axon 7 (A2017G)[/B][/SIZE]
[I]Android 15 on the 4.4 kernel, with ZTE's drivers ported from their 3.18 kernel.[/I][/CENTER]

[SIZE=5][B]What is this?[/B][/SIZE]
A port of LineageOS 22.2 (Android 15) to the ZTE Axon 7. The newest official LineageOS for the phone is 18.1; this one runs on the msm8996 4.4 kernel with ZTE's own drivers (audio codec, fingerprint, NFC, camera parts) ported from ZTE's 3.18 kernel, and Android 15 shims for the old vendor blobs.
An [B]unofficial LineageOS 22.2 release[/B]: almost everything works (see the status below), as a TWRP-flashable zip.

[SIZE=5][B]Status (2026-11-09)[/B][/SIZE]
[SPOILER="Works"]
[LIST]
[*]Boots to the home screen; SELinux enforcing
[*]Display and brightness
[*]Touch and the three touch keys
[*]Battery level
[*]Encrypted storage (file-based encryption)
[*]USB, adb
[*]Wi-Fi, Wi-Fi hotspot
[*]Bluetooth, also audio to speakers
[*]NFC
[*]Flashlight, with strength slider (long-press the tile)
[*]All 42 sensors
[*]GPS (fix outdoors in about 10 s)
[*]Fingerprint (enrolment works)
[*]Both cameras, optical image stabilisation
[*]Sound and volume (speaker; AK4961 codec and AK4490 Hi-Fi DAC drivers)
[*]Modem services for both SIM slots (dual SIM)
[/LIST]
[/SPOILER]
[B]Does not work / not tested:[/B]
[LIST]
[*]The phone sometimes wakes up or locks by itself
[*]Calls and mobile data with a SIM: untested
[/LIST]

[SIZE=5][B]Warning[/B][/SIZE]
[LIST]
[*]This ROM only works with the [B]Oreo "universal" bootloader[/B] (TrustZone TZ.BF.4.0.1-00353, the bootstack LineageOS 15.1 to 18.1 needed) and the [B]modem package for your model[/B]. The installer checks the bootloader and stops if it is missing.
[*]It needs the [B]community vendor partition[/B] (512 MB after system, the same as LineageOS 16 to 18.1). The original ZTE partition layout without a vendor partition is [B]not supported[/B]. With the vendor partition you cannot flash official ZTE firmware until you remove it again (PARTY tool).
[*]Tested on the [B]A2017G[/B] only. A2017U / A2017 (China): untested, at your own risk.
[*]Any failure while flashing or repartitioning can brick the phone. Make a backup and keep EDL in mind.
[/LIST]

[SIZE=5][B]Installation[/B][/SIZE]
[B]Attention:[/B] the bootloader must be unlocked, and you need the vendor partition.
[LIST=1]
[*]Install the [B]Oreo universal bootloader[/B] and the [B]modem for your model[/B] (unnecessary if you ran LineageOS 15.1 to 18.1 before). They are linked in the [URL='https://xdaforums.com/t/official-lineageos-15-1-for-zte-axon-7.3800214/']official LineageOS 15.1 thread[/URL].
[*]Create the [B]vendor partition[/B] with Oki's [URL='https://xdaforums.com/t/tool-treble-party-v0-5-vendor-partition-manager-2018-08-31.3831517/']PARTY tool[/URL] (a TWRP zip; unnecessary if you have it already, e.g. from LineageOS 16 to 18.1). If TWRP restarts on the first run, boot back into recovery and flash it again.
[*]Update [B]TWRP[/B] to 3.3.0 or newer ([URL='https://dl.twrp.me/ailsa_ii/']dl.twrp.me/ailsa_ii[/URL], 3.7.0_9-0 recommended).
[*]Back up your current ROM in TWRP (Boot, System, Vendor, Data, EFS) and copy it to a computer.
[*]Wipe → Advanced Wipe: [B]Dalvik / ART Cache, Cache, System, Vendor, Data[/B]. [B]Coming from LineageOS 18.1 or older or from stock: also Format Data[/B] (type [I]yes[/I]): Android 15 uses file-based encryption and cannot read the old encrypted data partition.
[*]Install the [B]ROM[/B]: [URL='https://github.com/devilAPI/zte-axon7/releases/tag/lineageos-latest']newest release[/URL] ([I]lineage-22.2-DATE-UNOFFICIAL-axon7.zip[/I]; check it against the [I].sha256[/I] file).
[*]Install GApps (optional): a package for [B]Android 15, arm64[/B] (e.g. MindTheGapps 15).
[*]Reboot → System. The first start takes a few minutes.
[/LIST]
Not needed: the multi-boot with iOS and Nura is a developer setup, not part of this ROM ([URL='https://github.com/devilAPI/zte-axon7/blob/main/DEV-MULTIBOOT.md']DEV-MULTIBOOT.md[/URL]).

[SIZE=5][B]Changelog[/B][/SIZE]
[SPOILER="2026-11-09"]
[LIST]
[*]GPS works (confirmed outdoors: fix in 8 s, 8 m accuracy). The location daemons start again (their config was in an older format), and a memory region that ZTE reserves for the modem side (vlog) is kept free.
[*]Flashlight strength: long-press the flashlight tile in Quick Settings for a slider (the torch blinks briefly at each step: the LED chip takes a new current only when switched on).
[/LIST]
[/SPOILER]
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
