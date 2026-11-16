# XDA thread: LineageOS 24 on mainline Linux (first post, BBCode)

The first post of the LineageOS 24 thread, kept current with every
user-visible change (status table, changelog). Only things confirmed on the
phone go into the "works" list; "built, untested" is said as such.

To update the thread: copy everything between the two marker lines into the
XDA editor (switch the editor to BBCode mode with the `[ ]` button first),
replacing the old text, then save.

Last update: 2026-11-16 (builds 40-47: GPU fault fix, web pages, lights, MTP, camera through cameraserver, radio status; kernel 0013/0014 on build 47: hardware scaling in the display, GPU memory bandwidth, animations)

First alpha (lineageos-24-YYYYMMDD draft release, published by hand after
testing). Everything in "Works" was seen on our phone in the unattended test
runs (PLAN.md, runs up to 36) or by the owner. Not yet confirmed: headphone
playback by ear, vibration, a GPS fix, the zip install path as a whole and
the firmware read from the phone's partitions (new in this release). Encryption is not part of
this alpha.

Changelog notes:
- 2026-11-16: builds 40-47 (PLAN.md runs 40-47). Vibration counted by the
  driver, not felt; camera frames come through, picture not looked at (phone
  in the dark); hall sensor closed state needs a magnet. Animations still
  janky (no hardware scaling on msm8996: QSEED2 TODO in dpu), being fixed.
- 2026-11-16 (later): kernel 0013 (QSEED2 scaler in dpu) and 0014 (GPU DDR
  votes) measured on build 47 with los24-anim.sh and los24-bench.sh (kfast
  kernel #23). Wallpaper zoom off (RRO) is in build 48, not confirmed yet,
  so not in the post. Shade and open/back still above 10 %.
- 2026-11-15: first alpha. Multi-boot slot only (system + los_boot,
  los_metadata/los_data wiped). No SIM detected so far (UIM: no ATR in both
  slots, SIM presence asked in to-test.md).

<!-- XDA-POST-BEGIN -->
```bbcode
[CENTER][SIZE=6][B][ROM][17][ALPHA][UNOFFICIAL] LineageOS 24 on mainline Linux for the ZTE Axon 7 (A2017G)[/B][/SIZE]
[I]Android 17 on the mainline Linux 7.3.1 kernel, with open graphics drivers. A developer preview.[/I][/CENTER]

[SIZE=5][B]What is this?[/B][/SIZE]
A port of LineageOS 24 (Android 17) to the ZTE Axon 7 that does not use the old Android kernel or the old vendor blobs. It runs on [B]mainline Linux 7.3.1[/B] (the same kernel series as Nura, our postmarketOS-based Linux for the phone) plus the patches Android needs. Graphics are open source: Mesa freedreno for the Adreno 530 (OpenGL ES 3.1), drm_hwcomposer and minigbm.
Phase: [B]alpha / developer preview[/B]. It boots and a good part of the hardware works, but there are no calls, no mobile data and no suspend, and the camera is new and unchecked. Not for your daily phone. If you want a usable Android today, use our [B]LineageOS 22.2[/B] (4.4 kernel, own thread).
Build type userdebug, SELinux [B]permissive[/B] (the policy is being written).

[SIZE=5][B]Status (2026-11-16)[/B][/SIZE]
[SPOILER="Works (tested on our phone)"]
[LIST]
[*]Boots to the setup wizard and the home screen
[*]Display 1440x2560 (command-mode panel), brightness slider
[*]Touchscreen and the three touch keys (Back, Home, App switch)
[*]Wi-Fi (scans and connects)
[*]Bluetooth turns on
[*]Speaker playback (heard by the phone's own microphone), microphone recording
[*]Sensors: accelerometer, gyroscope, compass, light, proximity
[*]Battery level, charging status, voltage and temperature in Settings
[*]Notification LED, flashlight tile in Quick Settings
[*]USB file transfer (MTP)
[*]Web pages in the browser and in Chromium-based browsers (Cromite)
[*]Flip cover sensor reads "open" (closing not tried yet)
[*]Temperature sensors and thermal limits
[*]Hardware watchdog (restarts the phone if the kernel hangs)
[*]A normal restart returns to LineageOS
[*]Modem firmware starts and goes online (its services are up); the GPS service starts
[*]Software audio and video codecs
[/LIST]
[/SPOILER]
[B]Built, not tested yet:[/B]
[LIST]
[*]Headphone playback (plugging in is detected, nobody has listened yet)
[*]Vibration (the driver plays it; nobody has felt it yet)
[*]GPS position fix (the GPS runs and reports; no fix indoors so far)
[*]Camera, front and rear: preview and photos come through the camera service (Aperture app included), but nobody has looked at a picture with light yet
[*]USB tethering
[/LIST]
[B]Does not work / not done:[/B]
[LIST]
[*]Calls, SMS, mobile data: a first radio service shows the modem version and the network signal, but the SIM card is not detected so far, and mobile data needs a kernel driver that is not ported yet
[*]Fingerprint (controlled by TrustZone; not possible on mainline)
[*]NFC
[*]Suspend / deep sleep: the phone never sleeps, so battery life is short
[*]SELinux enforcing, storage encryption
[/LIST]
[B]Performance:[/B] scrolling is smooth: under 1 % late frames in our scroll benchmark (was 13 % in the first builds). Animations got much better after two kernel fixes: the display hardware now scales images itself (before, any scaled layer such as the wallpaper made the whole screen go through the GPU), and the GPU now asks for enough memory bandwidth. Late frames: app drawer 3 %, ripple on press 5-7 %, opening an app and going home 11 %, notification shade about 17 %, opening a settings page and going back about 19 % (were 30-40 %). The shade and opening pages still stutter a little: those apps need about 18 ms of drawing per frame on this GPU driver, more than one screen refresh.
[B]Stability:[/B] 30-minute stress tests ran clean on several builds. A rare crash in the kernel's display driver (twice in one build) is being investigated; the phone restarts by itself when it happens.

[SIZE=5][B]Warning[/B][/SIZE]
[LIST]
[*]This is an [B]alpha[/B]. Things will break. Back up first (TWRP: Boot, EFS, Modem, and anything else you want to keep) and copy the backup to a computer.
[*]Tested on the [B]A2017G[/B] (4 GB / 64 GB) only. Other models: don't.
[*]It only installs into our [B]multi-boot setup[/B] (boot menu with iOS, Nura and LineageOS), a developer setup: [URL='https://github.com/devilAPI/zte-axon7/blob/main/DEV-MULTIBOOT.md']DEV-MULTIBOOT.md[/URL]. It is not a stand-alone ROM yet.
[*]Any failure while flashing can brick the phone. Keep EDL in mind.
[/LIST]

[SIZE=5][B]Installation[/B][/SIZE]
[B]You need:[/B] unlocked bootloader, TWRP 3.3.0-0 (the tested one), the multi-boot setup from DEV-MULTIBOOT.md including the partition step ([I]axon7-tripleboot-gpt[/I], it creates the LineageOS partitions), and the vendor partition of a ROM installed before (LineageOS 16 to 18.1, or our LineageOS 22.2) still in place: LineageOS 24 reads the GPU firmware from it. Do not wipe Vendor in TWRP.
[B]What the zip does:[/B] it writes the system image into the partition [I]system[/I] and the kernel into [I]los_boot[/I], and erases [I]los_metadata[/I] and [I]los_data[/I]. [B]All LineageOS data in the multi-boot slot is erased[/B]; a LineageOS 22.2 installed in the multi-boot slot is replaced. It does not touch boot, misc, iOS, Nura, persist, the modem/EFS partitions or the bootloader.
[LIST=1]
[*]TWRP: make a backup (above).
[*]Download the zip from the [URL='https://github.com/devilAPI/zte-axon7/releases']releases page[/URL] (tag [I]lineageos-24-DATE[/I], file [I]lineage-24-DATE-UNOFFICIAL-axon7m.zip[/I]) and check it against the [I].sha256[/I] file.
[*]Copy it to the phone and install it in TWRP; it must end without an error.
[*]Reboot, choose [B]LineageOS[/B] in the boot menu. The first start takes a few minutes.
[/LIST]
[B]No proprietary firmware in the download:[/B] LineageOS 24 loads the modem, DSP, GPU and Wi-Fi firmware straight from your phone's own partitions, read-only, at every start (the modem partition, and the GPU's a530_zap from the vendor partition). This is new in this release and still being tested; if the screen stays black or Wi-Fi/sound are missing, please send the logs below.

[SIZE=5][B]Problems?[/B][/SIZE]
[LIST]
[*][B]It starts, but something does not work:[/B] switch on USB debugging (Settings → About phone → tap Build number 7 times; System → Developer options), and before rebooting run [I]adb logcat -b all -d > logcat.txt[/I] and [I]adb shell dmesg > dmesg.txt[/I].
[*][B]Crash or restart:[/B] go to TWRP right away (hold [B]Power + Volume Up[/B] about 10 s) and save the kernel log of the failed start: [I]adb pull /sys/fs/pstore/ los24-pstore[/I].
[*]Please also say what you did right before the problem and which build (date) you run.
[/LIST]

[SIZE=5][B]Changelog[/B][/SIZE]
[SPOILER="2026-11-16, kernel update"]
[LIST]
[*]Animations: the display hardware scales layers itself now (the wallpaper and windows while apps open), so the screen no longer falls back to drawing everything on the GPU. App drawer, opening apps and the notification shade stutter much less (late frames 30-40 % before, now 3-19 %).
[*]The GPU asks for memory bandwidth while it draws; before, the memory ran at the speed the display alone needed.
[*]Scrolling: under 1 % late frames in our scroll benchmark.
[/LIST]
[/SPOILER]
[SPOILER="2026-11-16"]
[LIST]
[*]No more GPU faults and garbled areas (seen on the wallpaper): a buffer shared between apps was taken away from the GPU when one app closed it, while the others still used it.
[*]Web pages load and show in the browser and in Chromium-based browsers (their sandbox could not use shared memory before).
[*]Scrolling: about 2 % late frames (was 13 %); the GPU runs at full clock while drawing and still powers down when idle.
[*]Notification LED and flashlight tile, brightness slider fixed.
[*]Battery level, charging status, voltage and temperature in Settings.
[*]USB file transfer (MTP).
[*]Camera: both cameras deliver preview and photos to Android's camera service, with the Aperture camera app (picture quality not checked yet).
[*]Vibration, flip cover sensor and GPS services added (not confirmed by hand or outdoors yet).
[*]First radio service: modem version and network signal (SIM, calls and data still missing).
[*]Kernel fixes for crashes in the camera control bus and the audio data bus; the display no longer loses its refresh signal after a timeout.
[*]Bluetooth tries again if the chip does not answer at start.
[/LIST]
[/SPOILER]
[SPOILER="2026-11-15"]
[LIST]
[*]First alpha: TWRP zip for the LineageOS slot of the multi-boot setup.
[*]Works: display with brightness, touch and touch keys, Wi-Fi, Bluetooth on, speaker and microphone, five sensors, battery and charging, temperature sensors, watchdog, modem online, software codecs.
[*]Scrolling much smoother than in the first builds (kernel display driver and Mesa frame pacing fixes); still about 13 % late frames.
[*]Firmware is read from the phone's own partitions, nothing proprietary in the zip (new, still being tested).
[/LIST]
[/SPOILER]

[SIZE=5][B]Source[/B][/SIZE]
[B]Kernel source (GPLv2):[/B] [URL='https://github.com/devilAPI/linux/tree/zte-axon7']github.com/devilAPI/linux, branch zte-axon7[/URL] (Linux 7.3.1 with the Axon 7 patches), plus the Android patches in the branch below
Device tree, Android, kernel and Mesa patches, build scripts: [URL='https://github.com/devilAPI/zte-axon7/tree/lineageos-24-mainline']github.com/devilAPI/zte-axon7, branch lineageos-24-mainline[/URL] (folder lineageos-24-mainline)
The same project also brings LineageOS 22.2 (unofficial release), Nura (Linux, beta) and iOS 16 (alpha) to the Axon 7, each with its own thread.

[SIZE=5][B]Credits[/B][/SIZE]
LineageOS, AOSP, the Mesa/freedreno developers, drm_hwcomposer and minigbm, Linaro (dragonboard device and tools), AOSPM, the mainline Linux and msm8996 mainline developers, postmarketOS, TWRP.

[I]Not affiliated with ZTE or LineageOS. You flash this at your own risk.[/I]
```
<!-- XDA-POST-END -->
