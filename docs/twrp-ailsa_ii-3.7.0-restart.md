# TWRP 3.7.0_9-0 on ZTE Axon 7 (ailsa_ii): restart report

Date: 2026-11-26 (source check), hardware test 2026-11-26/27.
Status: **tested on the second phone; the restart and the "only `fastboot boot`"
claims were not reproduced.** 3.3.0-0 stays the TWRP version the LineageOS
zips are tested with; 3.3.1-0 was left flashed on the second phone.

## The report

- A user reported (2026-11-14) that **TWRP 3.7.0_9-0 restarts by itself** on
  the Axon 7, in its main menu.
- The same report said that on the second phone it **only starts via
  `fastboot boot`**, not when flashed to the recovery partition.

## Source check (2026-11-26)

- Official TWRP device page: <https://twrp.me/zte/zteaxon7.html> (ailsa_ii,
  maintainer jcadduono, android-6.0 device tree).
- Official downloads: <https://dl.twrp.me/ailsa_ii/> lists 3.7.0_9-0
  (2022-10-09, 15.8M) as latest; previous 9.0 builds 3.6.2_9-0, 3.6.1_9-0,
  3.6.0_9-0, 3.5.x_9-0, 3.4.0-0, 3.3.1-0.
- TeamWin device tree `TeamWin/android_device_zte_ailsa_ii` (android-6.0
  branch, only branch): prebuilt kernel `Image.gz-dtb`, cmdline includes
  `androidboot.selinux=permissive enforcing=0`, no watchdog-disable argument;
  `TW_INCLUDE_CRYPTO := true`, `TARGET_HW_DISK_ENCRYPTION := true`,
  `TARGET_RECOVERY_QCOM_RTC_FIX := true`.
- XDA official TWRP thread (3515715, pages 1 and 16 checked) contains no
  3.7.0-specific report; thread mostly historical (2016-2019).
- TeamWin issue tracker search for `ailsa_ii`: only #1329 (decrypt/pattern),
  no restart report.

## Hardware test (2026-11-26/27)

Phone: the second phone (A2017G, serial redacted), stock partition layout
(no vendor partition), bootloader unlocked. At the start TWRP 3.7.0_9-0 was
running from `fastboot boot`, **not** from the recovery partition.

Recovery partition: `/dev/block/sde14`, 65536 KiB (64 MiB). Before anything
was written, the whole partition was copied off the phone; its SHA1
(`87880f6900811ed0fdab9bbe9fafc2c9e47c62b0`) matched on the read-back. The
first 16515072 bytes were byte-identical to the official
`twrp-3.7.0_9-0-ailsa_ii.img`, i.e. the partition already contained the
official 3.7.0_9-0 image.

Images: downloaded from <https://dl.twrp.me/ailsa_ii/> on 2026-11-26. Each
SHA256 was checked against the published `.sha256` file and the PGP signature
against the TeamWin key (RSA, fingerprint
`9570 7D42 307C 9D41 D09B F709 1D85 97D7 891A 43DF`); all three signatures
are good.

| image | bytes | SHA256 |
|---|---|---|
| twrp-3.7.0_9-0-ailsa_ii.img | 16515072 | `d74410d0f82808901123609bad04d20362a30280dca03cac5e5c68b38380473b` |
| twrp-3.6.2_9-0-ailsa_ii.img | 16515072 | `bd1967af212a6dd4d660e75c8fd06363ddf9e2d65bb49cbd32311da40320e8fe` |
| twrp-3.3.1-0-ailsa_ii.img | 14897152 | `9a4fbad9da06306d6430944335718fca7636d101926d47dd119ab5a80a53afa1` |

All three images contain the same kernel: `Linux version
3.18.47-twrp-ailsa_ii-3.1 (jc@westerley)`, built 2017-01-22 22:27:31 EST.
Only the ramdisk differs between the versions, so a 3.7.0-specific kernel
watchdog change is not possible; any behavioural difference is in the
userspace/ramdisk.

Method, for each image:

1. `adb push` to `/tmp`, then `dd` to `/dev/block/sde14` (recovery), `sync`.
2. Read the image length back from the partition; the SHA256 matched the
   downloaded image every time.
3. `adb reboot recovery` (the bootloader then loads the recovery partition).
4. Poll `adb shell cat /proc/uptime` and `getprop ro.twrp.version` every 5 s
   for 620 s (10 minutes) and log a restart if uptime ever drops.
5. Afterwards capture `dmesg`, `/tmp/recovery.log` and `/sys/fs/pstore`.
Before switching to the next image, the running TWRP's `dmesg`,
`/tmp/recovery.log` and `/sys/fs/pstore` were captured as well.

### UI state

3.7.0_9-0 stops on its first-boot "Unmodified System Partition" page and,
after the screen timeout, shows a lock overlay ("Swipe to Unlock").
3.3.1-0 boots straight to the main menu. The touchscreen cannot be driven
over adb: TWRP holds `/dev/input/event1` grabbed, so a second reader gets no
events and synthetic touch events written to it are dropped. The power key on
`/dev/input/event0` can be injected (a short press toggles the backlight).
The 3.7.0_9-0 main menu was therefore reached by running a `twrp` CLI command:
the GUI switches through its `singleaction_page` back to `main2` (`Set page:
'main2'` in `/tmp/recovery.log`) without touching anything. It stayed behind
the screen-timeout lock, idle, for the whole run.

The battery was at 100 % on USB. Nothing else was done in TWRP: no zip
install, no wipe, no touch input; the display turned off after the screen
timeout on 3.7.0_9-0.

### Results

| flashed recovery | state under test | end uptime | restarts | read-back SHA256 |
|---|---|---|---|---|
| 3.7.0_9-0 | first-boot page (run 1) | 627 s | 0 | matched |
| 3.7.0_9-0 | first-boot page + lock (run 2, 122 samples) | 614 s | 0 | matched |
| 3.7.0_9-0 | main menu `main2`, behind the lock (620 s monitored) | 864 s | 0 | matched |
| 3.6.2_9-0 | 10 min after boot | 609 s | 0 | matched |
| 3.3.1-0 | 10 min after boot; main menu (checked on the final boot) | 611 s | 0 | matched |

Evidence:

- **Each start came from the recovery partition.** The bootloader log in the
  next boot's `pstore` shows `booting linux @ 0x80080000, ramdisk @
  0x82600000 (<size>)` with the ramdisk size of the image just flashed:
  10899207 bytes for 3.7.0_9-0, 10896497 for 3.6.2_9-0 and 9278828 for
  3.3.1-0. These values match the image headers exactly, so the bootloader
  did not reuse the fastboot-loaded image from before the reboot.
- **No restart.** `ro.twrp.version` reported the expected version after each
  reboot and `/proc/uptime` grew monotonically through every 10-minute run.
  `/tmp/recovery.log` contains exactly one `Starting TWRP <version> ...`
  line per run (a userspace restart would have logged another start). On
  3.7.0_9-0 the main menu (`Set page: 'main2'`) was the active page for the
  whole 620 s monitor (from 236 s to 864 s uptime), i.e. just over 10 minutes
  without a restart.
- **The UI was up, not hung.** Framebuffer dumps (`/dev/graphics/fb0`,
  1440x2560) show the 3.7.0_9-0 first-boot page, the 3.7.0_9-0 main menu
  (Install, Wipe, Backup, Restore, Mount, Settings, Advanced, Reboot; title
  "3.7.0_9-0") behind the lock overlay, and the 3.3.1-0 main menu after the
  final flash. TWRP's own title/version was drawn correctly in each dump.
- **No crash or watchdog bite.** No `Kernel panic`, `Oops`, `Unable to handle
  kernel` or watchdog-bite message in `dmesg`; the previous boot's `pstore`
  console ends with our own `reboot: Restarting system with command
  'recovery'`, not with an abrupt end. The watchdog driver initializes on
  every boot (`msm_watchdog 9830000.qcom,wdt: MSM Watchdog Initialized`);
  recovery has no `/dev/watchdog` node, so userspace does not pet it. No
  watchdog reset happened.
- **Baseline:** the `fastboot boot`-ed 3.7.0_9-0 had already been up for
  366 s when the test started, and it did not restart either.

Raw logs (full `dmesg`, `recovery.log`, `pstore`) are kept outside the
repository because they contain the device serial and hardware addresses;
the hashes and the summary above are the committed record.

## Assessment

- On this phone, **flashed 3.7.0_9-0 boots and stays up for more than
  10 minutes**, and so do 3.6.2_9-0 and 3.3.1-0. The "only `fastboot boot`,
  not when flashed" part is contradicted by this test: the recovery partition
  already held the official 3.7.0_9-0 image, and flashing it again and
  rebooting into recovery worked.
- The user's restart could not be reproduced. It may depend on the affected
  unit, on the multi-boot layout/boot menu, on interaction (installing,
  backing up) or on a longer idle time. On 3.7.0_9-0 the main menu itself was
  the active page for the 620 s monitor, but idle behind the screen-timeout
  lock; the exact "user actively using the menu" state cannot be driven
  unattended because TWRP grabs the touchscreen. The report is pre-existing
  evidence from one phone and is not disproven for other units.
- No source fix was produced, and there is no watchdog/crash evidence in our
  run to base one on.

## Recommendation

- **TWRP 3.3.0-0** stays the version the LineageOS 22.2/24 zips are tested
  with. **3.3.1-0** is the long-standing stable flashed baseline; it was left
  flashed on the second phone, which boots it straight to the main menu.
- 3.6.2_9-0 and 3.7.0_9-0 also passed the 10-minute idle test here, so the
  restart report is not a reason to avoid 3.7.0_9-0 by itself. If it does
  restart on a phone, use 3.3.x or `fastboot boot`.
- If it restarts, capture before rebooting: `adb pull /tmp/recovery.log` and
  `adb shell dmesg`; after the reboot `adb pull /sys/fs/pstore/`. The PMIC
  power-on reason (`qpnp-power-on ... Power-on reason: ...`) and the last
  `pstore` line distinguish a watchdog/hard reset from a normal reboot.
