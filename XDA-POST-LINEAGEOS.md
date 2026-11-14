# XDA thread: LineageOS 22.2 (first post, BBCode)

The first post of the LineageOS thread, kept current with every user-visible
change (status table, changelog). Only things confirmed on the phone go into
the "works" column; "built, untested" is said as such.

To update the thread: copy everything between the two marker lines into the
XDA editor (switch the editor to BBCode mode with the `[ ]` button first),
replacing the old text, then save.

Last update: 2026-11-14

First release published 2026-11-09 (lineageos-22.2-20261109; the download
link in the post points to lineageos-latest, which follows each published
release). The install was tested with the devtest variant of the same zip
(/data on los_data): TWRP 3.3.0-0 (the oldest supported) flashed system,
vendor and boot, the phone
booted with SELinux enforcing. The release variant itself (/data on userdata)
has not been booted on our phone, and TWRP 3.7.0_9-0 was never used with it.

2026-11-14: a user report (TWRP 3.7.0_9-0 restarted by itself in its main
menu; with an unofficial TWRP 3.2.1-8 TREBLE the zip flashed, then a boot loop
after the logo, coming from crDroid 11 / LineageOS 18.1) made the install
steps stricter: TWRP 3.3.0-0 (the tested one) instead of "3.7.0 recommended",
Format Data always (Advanced Wipe > Data keeps internal storage, and
Android 15's file-based encryption cannot take it over), /data as ext4
(18.1 also allowed F2FS, Format Data keeps the file system), and a
"Problems" section with the logs to send.

2026-11-14, second report from the same user (A2017G, daily driver a
modified stock ZTE Oreo 8.0): after several attempts the ROM booted to the
home screen, but no SIM card was detected and the camera app showed a black
screen; after a reboot, a boot loop. Telephony with a SIM in the phone was
never tested by us (rild_axon7 is our own shim, 0033/0043/0046), and the
release variant (/data on userdata) was never booted by us, so all three are
listed as known issues. The zip only installs with the TrustZone check
passed and a vendor partition present (block_image_update does not create
the device node), so that phone had TZ.BF.4.0.1-00353 and a vendor partition
at the time. Added: a "Coming from stock ZTE firmware" section with read-only
checks for both, and how to collect logs while it still boots.

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
[*][B]SIM card not detected[/B] (one user report, A2017G). Our phone was only tested without a SIM: the modem and the radio services start, but SIM detection, calls and mobile data are untested. Do not use this ROM as your daily phone yet if you need the SIM.
[*][B]Camera app shows a black screen[/B] (one user report; both cameras work on our phone)
[*][B]Boot loop on the second start[/B] after a working first start (one user report, under investigation; logs wanted, see Problems)
[/LIST]

[SIZE=5][B]Warning[/B][/SIZE]
[LIST]
[*]This ROM only works with the [B]Oreo "universal" bootloader[/B] (TrustZone TZ.BF.4.0.1-00353, the bootstack LineageOS 15.1 to 18.1 needed) and the [B]modem package for your model[/B]. The installer checks the bootloader and stops if it is missing. If LineageOS 18.1 or crDroid 7.x installs on your phone, you have it (their installers check the same version).
[*]Tested with [B]TWRP 3.3.0-0[/B] only. TWRP 3.7.0_9-0 has been reported to restart by itself on this phone; older TWRP builds (3.2.x, e.g. the 3.2.1 "TREBLE" build) are untested.
[*]Installing [B]erases internal storage[/B] (Format Data, see below). Copy your photos and files to a computer first.
[*]It needs the [B]community vendor partition[/B] (512 MB after system, the same as LineageOS 16 to 18.1). The original ZTE partition layout without a vendor partition is [B]not supported[/B]. With the vendor partition you cannot flash official ZTE firmware until you remove it again (PARTY tool).
[*]Tested on the [B]A2017G[/B] only. A2017U / A2017 (China): untested, at your own risk.
[*]Any failure while flashing or repartitioning can brick the phone. Make a backup and keep EDL in mind.
[/LIST]

[SIZE=5][B]Coming from stock ZTE firmware (Nougat or Oreo)?[/B][/SIZE]
The stock ZTE partition layout has [B]no vendor partition[/B], and this ROM needs one. Check first, in TWRP → Advanced → Terminal (read-only, changes nothing):
[CODE]cat /dev/block/bootdevice/by-name/tz | tr -c '[:print:]' '\n' | grep QC_IMAGE_VERSION_STRING
ls -l /dev/block/bootdevice/by-name/vendor[/CODE]
[LIST]
[*]The first line must contain [B]TZ.BF.4.0.1-00353[/B]. If not (Nougat or older bootloader), install the Oreo universal bootloader and the modem for your model first (step 1 below).
[*]The second line must show a link to a block device. [I]No such file or directory[/I] means no vendor partition: create it with PARTY (step 2 below). Without it the ROM install stops with an error (after it has already overwritten system).
[*]Note the baseband version of your current ROM (Settings → About phone) for a problem report.
[/LIST]
A good first test of firmware and partitions: install [B]LineageOS 18.1[/B] (rcky844's unofficial build, see his XDA thread) and check that calls, mobile data and the camera work there. If they do, your firmware is fine for this ROM too. Going back to stock ZTE firmware later needs the vendor partition removed again (PARTY) or a full stock package for your model; keep your TWRP backup and EFS backup.

[SIZE=5][B]Installation[/B][/SIZE]
[B]Attention:[/B] the bootloader must be unlocked, and you need the vendor partition.
[LIST=1]
[*]Install the [B]Oreo universal bootloader[/B] and the [B]modem for your model[/B] (unnecessary if you ran LineageOS 15.1 to 18.1 before). They are linked in the [URL='https://xdaforums.com/t/official-lineageos-15-1-for-zte-axon-7.3800214/']official LineageOS 15.1 thread[/URL].
[*]Create the [B]vendor partition[/B] with Oki's [URL='https://xdaforums.com/t/tool-treble-party-v0-5-vendor-partition-manager-2018-08-31.3831517/']PARTY tool[/URL] (a TWRP zip; unnecessary if you have it already, e.g. from LineageOS 16 to 18.1). If TWRP restarts on the first run, boot back into recovery and flash it again.
[*]Install [B]TWRP 3.3.0-0[/B] ([I]twrp-3.3.0-0-ailsa_ii.img[/I] from [URL='https://dl.twrp.me/ailsa_ii/']dl.twrp.me/ailsa_ii[/URL]; the version this zip was tested with): Install → Install Image → the .img → [B]Recovery[/B], then Reboot → Recovery and check the version in the title bar. If TWRP restarts by itself, do not flash anything with it; go back to 3.3.0-0.
[*]Back up your current ROM in TWRP (Boot, System, Vendor, Data, EFS) and copy it, and your photos and files, to a computer.
[*]Wipe → Advanced Wipe → tick only [B]Data[/B] → Repair or Change File System. If it says [B]F2FS[/B]: Change File System → [B]EXT4[/B] → swipe (this ROM mounts /data as ext4 only). Back.
[*]Wipe → [B]Format Data[/B] → type [I]yes[/I]. [B]Always[/B], whichever ROM you come from (stock, LineageOS, crDroid, encrypted or not); only an update from an earlier LineageOS 22.2 build skips this. Android 15 uses file-based encryption and cannot use an old data partition; [I]Advanced Wipe → Data[/I] alone is not enough (it keeps internal storage). Then Reboot → Recovery.
[*]Wipe → Advanced Wipe: [B]Dalvik / ART Cache, Cache, System, Vendor[/B].
[*]Copy the ROM zip to the phone (USB in TWRP, or a microSD card) and install it: [URL='https://github.com/devilAPI/zte-axon7/releases/tag/lineageos-latest']newest release[/URL] ([I]lineage-22.2-DATE-UNOFFICIAL-axon7.zip[/I]; check it against the [I].sha256[/I] file). The install must end without an error.
[*]GApps (optional): a package for [B]Android 15, arm64[/B] (e.g. MindTheGapps 15), right after the ROM, before the first start. If the first start fails, try once without GApps.
[*]Reboot → System. The first start takes a few minutes.
[/LIST]
Not needed: the multi-boot with iOS and Nura is a developer setup, not part of this ROM ([URL='https://github.com/devilAPI/zte-axon7/blob/main/DEV-MULTIBOOT.md']DEV-MULTIBOOT.md[/URL]).

[SIZE=5][B]Problems?[/B][/SIZE]
[LIST]
[*][B]TWRP restarts by itself[/B]: use TWRP 3.3.0-0 (above). Flash the ROM only with a TWRP that runs stably.
[*][B]Boot loop or stuck at the logo[/B]: did you Format Data (typed [I]yes[/I]) and is /data EXT4? If not, do it and install again. Otherwise hold [B]Power + Volume Up[/B] about 10 s to get to TWRP, and right away (before starting anything else) save the kernel log of the failed start: with a computer, [I]adb pull /sys/fs/pstore/ los-pstore[/I]; or with a microSD card in the phone, Advanced → Terminal: [I]cat /sys/fs/pstore/console-ramoops* > /external_sd/los-ramoops.txt[/I] (not to internal storage: TWRP cannot read Android 15's encrypted /data). If adb works during the start, [I]adb logcat > logcat.txt[/I] helps too.
[*][B]It starts, but something does not work[/B] (SIM, camera, ...): before rebooting, switch on Settings → About phone → tap Build number 7 times, then System → Developer options → USB debugging, connect a computer and run [I]adb logcat -b all -d > logcat.txt[/I], [I]adb shell dmesg > dmesg.txt[/I] and [I]adb shell getprop > props.txt[/I]. For a SIM problem, also say which slot the SIM is in and your carrier/country.
[*]When you report a problem, please post: the ROM you came from and whether it was encrypted, whether you did Format Data, your TWRP version, your model and modem/baseband version, the kernel log above and TWRP's log ([I]adb pull /tmp/recovery.log[/I], or Advanced → Copy Log to the microSD card, right after installing the zip).
[/LIST]

[SIZE=5][B]Changelog[/B][/SIZE]
[SPOILER="2026-11-09"]
[LIST]
[*]First TWRP-flashable zip (no multi-boot): needs the Oreo universal bootloader and the community vendor partition; download link under Installation.
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
