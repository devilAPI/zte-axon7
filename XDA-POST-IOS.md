# XDA thread: iOS 16 (first post, BBCode)

The first post of the iOS thread, kept current with every user-visible
change (status table, changelog). Only things confirmed on the phone go into
the "works" column.

To update the thread: copy everything between the two marker lines into the
XDA editor (switch the editor to BBCode mode with the `[ ]` button first),
replacing the old text, then save.

Last update: 2026-11-08

<!-- XDA-POST-BEGIN -->
```bbcode
[CENTER][SIZE=6][B][ALPHA] iOS 16.7.16 on the ZTE Axon 7 (A2017G)[/B][/SIZE]
[I]Apple's XNU kernel on the Snapdragon 820, iPhone 8 userland.[/I][/CENTER]

[SIZE=5][B]What is this?[/B][/SIZE]
A port of Apple's open-source XNU kernel to the Axon 7's Snapdragon 820, running the iPhone 8's iOS 16.7.16 system. The system image is built on your own PC from Apple's own IPSW file; nothing of Apple's is redistributed.
Phase: [B]alpha[/B]. For developers and the curious.

[SIZE=5][B]Status (2026-11-08)[/B][/SIZE]
[SPOILER="Works"]
[LIST]
[*]Lock and home screen
[*]GPU acceleration (Adreno 530 via Mesa freedreno)
[*]Touch
[*]Home on Volume Down
[*]Wi-Fi (WPA2, rejoins on its own)
[*]Safari
[*]OpenSSH
[*]Rootless jailbreak with Sileo (app installs work)
[/LIST]
[/SPOILER]
[B]Does not work:[/B]
[LIST]
[*]Calls
[*]SMS
[*]Mobile data
[*]Camera
[*]Audio
[*]Bluetooth
[/LIST]

[SIZE=5][B]Installation[/B][/SIZE]
[B]No downloads and no flashable zips during the alpha[/B] (and iOS itself can never be offered as a download: it is built from Apple's IPSW on your PC).
Developers can build and install it; the developer setup (a multi-boot with Nura and LineageOS on one phone) is described here: [URL='https://github.com/devilAPI/zte-axon7/blob/main/DEV-MULTIBOOT.md']DEV-MULTIBOOT.md[/URL]. Your internal storage is erased by it.

[SIZE=5][B]Changelog[/B][/SIZE]
[SPOILER="2026-11-07"]
[LIST]
[*]iOS no longer restarts about 25 s after every start (a watchdog in the boot loader). Images flashed before: flash the iOS kernel again.
[/LIST]
[/SPOILER]

[SIZE=5][B]Source[/B][/SIZE]
[URL='https://github.com/devilAPI/zte-axon7']github.com/devilAPI/zte-axon7[/URL] (submodule ios: the XNU port, loader and tools; branch axon7 of [URL='https://github.com/devilAPI/ios-sailfish/tree/axon7']devilAPI/ios-sailfish[/URL])
The same project also brings Nura (Linux, beta) and LineageOS 22.2 (unofficial release) to the Axon 7, each with its own thread.

[SIZE=5][B]Credits[/B][/SIZE]
Apple's open-source XNU, Mesa (freedreno), Sileo and the rootless jailbreak tools, TWRP.

[I]Not affiliated with ZTE or Apple. iOS is Apple's software; you build it from your own IPSW. You flash this at your own risk.[/I]
```
<!-- XDA-POST-END -->
