# LineageOS 24 on mainline Linux for the ZTE Axon 7: plan

Status: **M0: boot path works (M0a''); M0b' found the recovery crash (no DRM device in recovery), kernel #4 with the display built in, M0b'' images ready; full build running** (started 2026-11-09). Codename for this
port: **`axon7m`** (device `zte/axon7m`, so it can live next to the 4.4
`axon7` tree of LineageOS 22.2 without clashing).

Markers used below: **[V]** verified (source or command given), **[A]**
assumption, still to verify, **[D]** decision.

---

## 0. Key decisions in one table

| Topic | Decision | Why (details in the sections below) |
| --- | --- | --- |
| Android base | LineageOS **24.0** = Android 17 (`android-17.0.0_r1`), branch `lineage-24.0` [V] | the current LineageOS release |
| Kernel | **Nura's tree: Linux 7.3.1 + the 18 Axon 7 patches**, plus an Android config fragment; **no GKI** [D] | all hardware support the phone has on mainline lives in that tree; Android 17 runs on upstream kernels if a few ACK-only features are replaced (§3) |
| Fallback kernel | rebase the same 18 patches onto ACK `android-mainline` (at 7.3 now) [D] | brings ashmem, dm-default-key, incfs, xt_quota2, f_accessory if one of them turns out to be required |
| Boot | the multi-boot shim's existing LineageOS path: **boot image header v2, raw `Image`, DTB in the dtb section**, kernel at 0x80000000 [V] | the shim already boots 4.4 this way; a mainline Image (text_offset 0, 2 MiB aligned base) fits the same path |
| Kernel build | outside the Android tree (`scripts/kernel-build.sh` on the server), result used as prebuilt [D] | fast iteration, same tree as Nura, no LineageOS kernel.mk quirks |
| Partitions | LineageOS 24 **takes over LineageOS 22.2's multi-boot slot** (user, 2026-11-10): `los_boot`, 22.2's GPT `system` (5.5 GiB) as the dynamic-partitions super device (system, system_ext, product, vendor), `los_metadata`, `los_data` [D] | no new partitions, no shim change; 22.2 no longer needs to stay bootable |
| Graphics | Mesa **freedreno** (Adreno 530, GLES 3.x, no Vulkan) + **drm_hwcomposer** + **minigbm** gralloc; SwiftShader/ANGLE as bring-up fallback [D] | the Linaro db845c recipe; turnip (Vulkan) does not support a5xx [A] |
| Audio | fork of AOSP's **AIDL example audio HAL** (tinyalsa "primary" module) + routing from Nura's UCM [D] | no proprietary HAL can run on the mainline ASoC card; the example HAL already drives ALSA PCMs [V] |
| Wi-Fi / BT | wpa_supplicant nl80211 on ath10k; AOSP default Bluetooth AIDL HAL (HCI user channel) + a BD-address tool [D] | exactly what db845c does [V] |
| Modem | last: open QRTR/QMI radio AIDL HAL (after AOSPM's qrild), IPA v2.5 kernel port for data, q6voice for call audio [D] | no working open RIL exists for Android 17; proprietary RIL needs the downstream kernel ABI |
| Sensors | port the out-of-tree **qcom_smgr** IIO driver (MSM8996 SLPI Sensor Manager) + a small IIO sensors HAL [D] | the only mainline path to the SLPI sensors [V: patch series exists, not merged] |
| Out of scope | fingerprint (Goodix owned by TrustZone/QSEE), probably NFC (mainline NCI driver vs. NXP Android HAL) | |

---

## 1. LineageOS 24: what it is [V]

- **LineageOS 24.0, based on Android 17**, announced 2026-10-11 in
  [Changelog 32](https://lineageos.org/Changelog-32/). Manifest branch
  `lineage-24.0` in [LineageOS/android](https://github.com/LineageOS/android/tree/lineage-24.0);
  the AOSP remote is pinned to `refs/tags/android-17.0.0_r1` (checked in
  `default.xml`, 2026-11-09). Other branches: `lineage-23.0/23.1/23.2` (Android 16).
- **Kernel policy**: "even though some devices using Linux Kernel versions 4.4
  and 4.9 have been ported to LineageOS 23.2 and 24.0, we have decided to only
  accept LineageOS 22.2 submissions for these devices" and "on LineageOS
  23.2/24.0 we're currently only shipping kernels that have 1:1 eBPF
  backports, build fully without GCC". This is the official reason the 4.4
  `axon7` port stops at 22.2, and why this port uses a mainline kernel. A
  mainline 7.3 kernel has upstream eBPF and builds with clang only.
- **Android 17 kernel requirements**: AOSP `kernel/configs` at
  `android-17.0.0_r1` has only `c/android-6.18/` (launch kernel 6.18), whose
  `android-base.config` is **empty** and `android-base-conditional.xml` holds
  just `<kernel minlts="6.18.0" />`. Android 16's `b/android-6.12/android-base.config`
  (261 lines) is the real requirement list; our fragment follows it (§3).
- **Framework compatibility matrices** at that tag: levels 7, 8, 202404,
  202504, 202604, 202704 (`hardware/interfaces/compatibility_matrices/`). So a
  device must declare target FCM level ≥ 7 (Android 12). We will use 202404
  (vendor API level of Android 15) or newer; everything in our vendor is new
  AIDL code anyway.
- **GKI / boot header v4 / vendor_boot** are requirements for devices
  *launching* with Android 12+ on GKI kernels (VSR), not for LineageOS builds
  of other devices. mkbootimg still writes header v0-v4; LineageOS 22.2 axon7
  already builds v2 for the shim. [V for 22.2; A for 24 until the tree builds]
- **ashmem**: `libcutils/ashmem-dev.cpp` at `android-17.0.0_r1` uses memfd
  when `sys.use_memfd=true`, or when the kernel has the SELinux
  `memfd_class` policy capability **and** `ro.vendor.api_level ≥ 202604`
  **and** the app targets SDK ≥ 37. Mainline 7.3.1 has `memfd_class`
  (`security/selinux/include/policycap_names.h`) but no ashmem driver, so we
  set `sys.use_memfd=true`. [V]
- **GL-only devices still work**: `frameworks/native/libs/renderengine/skia/`
  at `android-17.0.0_r1` still has `SkiaGLRenderEngine.cpp` next to the
  Vulkan engines [V]; db845c runs with `debug.hwui.renderer=skiagl` [V].
  Whether every Android 17 feature degrades gracefully without Vulkan is [A].
- **First stage init on a v2 boot image**: Android 17's init reads
  `androidboot.*` from both `/proc/bootconfig` and the kernel command line
  (`system/core/init/property_service.cpp` at `android-17.0.0_r1`:
  `ProcessBootconfig(); ProcessKernelCmdline();`) [V]. The super
  partition can be named by `androidboot.super_partition` on non-A/B devices
  (we use GPT `system`): `fs_mgr_get_super_partition_name()` in
  `system/fs/fs_mgr/fs_mgr.cpp` (fs_mgr moved out of `system/core` in
  Android 17) [V, synced tree].

## 2. Prior art: AOSP on mainline Qualcomm kernels

| Project | What it shows | What we take |
| --- | --- | --- |
| **Linaro `device/linaro/dragonboard`** (db845c, rb5, sm8450, sm8550) in AOSP ([tree](https://android.googlesource.com/device/linaro/dragonboard/+/refs/heads/main)), last public commit 2025-03-26 [V] | AOSP on ACK/android-mainline for Qualcomm boards: dynamic partitions, erofs, f2fs + FBE, wpa_supplicant `-Dnl80211`, `bdaddr` tool for the BT address, `rmtfs`/`pd-mapper`/`qrtr`/`tqftpserv` in vendor, `dlkm_loader` (modules after /vendor), `suspend_blocker`, legacy tinyalsa audio HAL (`audio.primary.db845c`), graphics: Mesa (`libEGL_mesa`, `ro.hardware.egl=mesa`), `drm_hwcomposer`, `minigbm` (`soong_config minigbm platform msm`), `swangle` (SwiftShader + ANGLE) fallback | the whole skeleton: fstab, init rc, sepolicy pieces, shared/utils, graphics config. No msm8996 target exists there [V: directory listing] |
| **AOSPM** ([github.com/aospm](https://github.com/aospm)) by the sdm845 mainline community (OnePlus 6, Poco F1), 2021-2023 | `android_device_generic_sdm845`, **qrild** + **libqril** (open QMI/QRTR RIL on the split **AIDL** radio interfaces `radio.config/data/messaging/modem/network` [V: source in /srv/los24/ref]; data call came up, DNS never did; development halted, libqril rewritten as a standalone library), `tinyhal` audio, `external_vibrator-ff` (force-feedback vibrator HAL for upstream haptics), `android-lights-hal` | radio HAL starting point, vibrator HAL (our haptics driver is an ff device), lights HAL |
| **Linaro "AOSP on Pixel 3 / Poco F1"** ([blog](https://old.linaro.org/blog/aosp-on-pixel3-pocof1-running-aosp-with-mainline-kernel-on-form-factor-devices)) | AOSP on mainline phones (not dev boards) is doable | confidence, not code |
| **GloDroid** ([manifest](https://github.com/GloDroid/glodroid_manifest)) | AOSP on mainline for Allwinner/RPi/PinePhone: Mesa built with meson inside AOSP (`aospext`), drm_hwcomposer, minigbm `gbm_mesa`, tinyhal | Mesa build recipe if NDK prebuilts become a pain |
| **Mesa in AOSP** (`external/mesa3d` @ android-17: Mesa 26.1-devel) [V] | its generated `Android.bp` builds only the gfxstream (virtual GPU) parts | freedreno has to be built separately: Mesa's [documented](https://gitlab.freedesktop.org/mesa/mesa/-/blob/main/docs/android.rst) meson + NDK build (`-Dplatforms=android -Dandroid-stub=true -Dgallium-drivers=freedreno -Dallow-fallback-for=libdrm`, "frequently used by Chrome OS developers"), shipped as vendor prebuilts (what Linaro's vendor package does) [V docs; A that EGL/GLES for a5xx on Android works] |
| **qcom_smgr** IIO drivers, Yassine Oudjana, [v2 2025-07](https://patchew.org/linux/20250710-qcom-smgr-v2-0-f6e198b7aa8e@protonmail.com) [V: not in 7.3.1] | MSM8996 SLPI Sensor Manager over QRTR: accel, gyro, pressure, prox, mag as IIO devices; pmOS userspace draft [MR 4118](https://gitlab.postmarketos.org/postmarketOS/pmaports/-/merge_requests/4118) | sensors milestone |
| **IPA v2.x**, Sireesh Kodali, [RFC 2021-09](https://lore.kernel.org/all/20210920030811.57273-1-sireeshkodali1@gmail.com/) [V: not in 7.3.1, `drivers/net/ipa` starts at v3.0] | IPA v2.5 for MSM8996; with it ModemManager got an IP on an MSM8996 phone | mobile data milestone |

## 3. Kernel

### 3.1 Choice [D]

Base: `linux-stable v7.3.1` + Nura's series
(`postmarketos/pmaports-local/device/testing/linux-zte-axon7/0001-0018`) +
`kernel/android-axon7m.config` + (later) `kernel/patches/*.patch`.

Why not GKI / an `android17-6.18` kernel: the Axon 7 drivers (S6E3HA3 panel,
dual-DSI DPU fix, PI5USB302, SMBCHG OTG, FG, haptics, torch, AK4490/AK8157/
ISL98608, AK4961, TFA989x changes) were written against 7.3; a 6.18 backport is
work without benefit, and GKI's vendor-module split buys nothing on a phone
that no vendor updates.

Why plain mainline before ACK `android-mainline` (which is at 7.3 now [V:
`kernel/common` `android-mainline` Makefile 7.3, 2026-11-09]): the first boot
should change one thing at a time. The Nura kernel is the one tested on this
phone; only the config differs. If an ACK-only feature proves necessary, the
18 patches move onto `android-mainline` at the matching point (small effort,
same base version).

### 3.2 ACK-only features and their replacements

| ACK feature | Used by | Replacement on mainline |
| --- | --- | --- |
| ashmem | libcutils shared memory | memfd: `sys.use_memfd=true` [V, §1] |
| dm-default-key | metadata encryption | none: FBE (fscrypt v2) without `keydirectory=`/metadata encryption [A: vold accepts it] |
| incremental-fs | `adb install --incremental`, Play streaming installs | not needed (`ro.incremental.enable` unset) |
| xt_quota2 | netd bandwidth alerts | missing → alert errors in logcat only [A]; port the ACK patch if it breaks data usage limits |
| uid_sys_stats, cpufreq_times | battery stats detail | eBPF time_in_state; uid io stats missing |
| f_accessory / f_audio_source | Android Open Accessory | not supported |
| vendor hooks, GKI module ABI | vendor modules | not needed |
| dm-user (snapuserd) | Virtual A/B | no A/B on this phone |

### 3.3 Config fragment

`kernel/android-axon7m.config`: binder + binderfs, SELinux (Nura has none),
eBPF, cgroups/PSI/uclamp, erofs/f2fs/ext4 + fscrypt + fs-verity built in,
dm-linear/verity, loop (APEX), FUSE passthrough, the netfilter/xfrm list,
configfs FunctionFS (adb/MTP), dma-buf heaps, sync files, firmware user helper
(Android's ueventd answers requests; Nura had none and ath10k stalled),
`STATIC_USERMODEHELPER=""`, pstore, no Rust/BTF/debug info.
`scripts/kernel-config-check.sh` lists every option that did not land.

### 3.4 Constraints from the boot path [V, ios/shim/android.c]

- Kernel copied to `0x80000000 + text_offset` = **0x80000000** (mainline
  text_offset 0; base 2 MiB aligned, as `booting.rst` asks).
- DTB at the next 2 MiB boundary after `image_size`; that plus 2 MiB must stay
  below **0x83400000** (splash reserved) → **image_size ≤ ~48 MiB**. Nura's
  Image is ~31.6 MiB. `kernel-build.sh` checks it. Keep drivers as modules.
- Ramdisk stays in the shim's staging area (0xa4000000+), recorded in
  `/chosen linux,initrd-*`; inside rmtfs's widened `alloc-ranges`
  (0xa0000000-0xc0000000, patch 0009) but memblock-reserved before the
  dynamic reserved-memory allocation [A: arm64_memblock_init order; check
  rmtfs address in the first dmesg].
- One DTB chosen by `qcom,msm-id <246 0x30001>` / `qcom,board-id <100 0>`;
  needs `/memory` and `/chosen` nodes (Nura's DTS has both).
- Command line = DTB bootargs + image cmdline + LK's tokens (minus LK's
  system-as-root ones). Ours: `msm.prefer_mdp5=0 clk_ignore_unused
  pd_ignore_unused androidboot.hardware=axon7m androidboot.boot_devices=soc@0/624000.ufshc
  androidboot.super_partition=system (added by the build) console=...`
  (`soc@0` vs `soc`: check the mainline platform device name [A]).

### 3.5 Modules and firmware

- Built in (needed by first-stage init): UFS + PHY, erofs, f2fs, ext4, dm,
  SELinux, binder.
- Modules from `/vendor/lib/modules`, loaded by a `modprobe` service after
  /vendor is mounted (dragonboard's `dlkm_loader` idea): remoteprocs
  (q6v5 PAS/MSS), DRM msm + panel, ath10k, BT, sound, haptics, FG, typec.
- Firmware: from the phone, never from this repo. Two sources:
  1. the `modem` partition (FAT, `image/`, read-only mount at
     `/vendor/firmware_mnt`): modem, adsp, slpi, venus, wlan board files,
     split `.mdt`/`.bNN` (mainline's mdt loader reads split files, so no
     pil-squasher needed [A: DTS firmware-name must then say `.mdt`]);
  2. GPU zap shader (`a530_zap.*`, signed for this phone) and linux-firmware
     files (a530_pm4/pfp, ath10k firmware-6.bin, QCA BT rampatch) in
     `/vendor/firmware` (build-time copy from the server, not committed).

## 4. Userspace stack per hardware block

Effort = agent work; phone time is extra (each phone test ~20-40 min with the
unattended test loop).

| Block | Mainline state (Nura) | Android component | Source | Effort | Risk |
| --- | --- | --- | --- | --- | --- |
| Boot, storage, adb | works | init, fstab, configfs USB (`init.axon7m.usb.rc`) | dragonboard | 1-2 wk | medium (first contact) |
| Display | works (DRM DPU, dual-DSI cmd mode, fbdev) | drm_hwcomposer (HWC3 AIDL) | AOSP `external/drm_hwcomposer` | 1 wk | medium: command-mode + bonded DSI through HWC3 untested anywhere [A] |
| GPU | A530 enabled in DTS, not used by Nura (console only); other msm8996 phones run Phosh on freedreno [A] | Mesa freedreno (EGL/GLES), minigbm `msm` gralloc + mapper | Mesa upstream (NDK build), AOSP minigbm | 2 wk | medium-high: zap shader load, Mesa Android build, a5xx+Android untested |
| GPU fallback | - | SwiftShader Vulkan (`vulkan.pastel`) + ANGLE | AOSP, dragonboard `swangle` | 2 d | low; slow at 1440x2560 |
| Touch, keys | works (RMI4, gpio-keys) | idc/kl files | - | 1 d | low |
| Wi-Fi | works (ath10k QCA6174, roaming fix 0008) | wpa_supplicant `-Dnl80211`, Wi-Fi AIDL HAL without vendor lib | AOSP, dragonboard | 3-5 d | low-medium (Wi-Fi HAL without a `libwifi-hal` vendor lib [A]) |
| Bluetooth | works, needs BD address (unconfigured until set) | `android.hardware.bluetooth-service.default` (HCI user channel via MGMT) [V], BD-address tool reading persist `.bt_nv.bin` (port of `axon7-btaddr`) | AOSP + dragonboard `bdaddr` | 3-5 d | low-medium |
| Audio out | headphones (AK4490), speakers (AK4961 + 2x TFA9890), earpiece switch; card "ZTE Axon 7", playback hw:0,1, capture hw:0,0 (r10) | AIDL audio HAL: fork of `hardware/interfaces/audio/aidl/default` primary module (`CARD_x_DEV_y` addresses [V]) + mixer routes from Nura's UCM | AOSP | 2 wk | medium |
| Microphone | mic 1 works (r10) | same HAL | | incl. | medium |
| Vibrator | works (ff haptics, `spmi_haptics`, FF_RUMBLE) | own AIDL IVibrator V4 on the FF device: `device/zte/axon7m/vibrator` (written 2026-11-10; AOSPM's `external_vibrator-ff` is HIDL 1.1) | own | done, untested | low |
| Torch, LED | works (`white:torch`, RGB LED) | lights AIDL, camera torch via sysfs later | AOSPM lights HAL | 2 d | low |
| Battery | FG read-only works | health AIDL default (sysfs power_supply) | AOSP | 2 d | low |
| Charging | **missing** (SMBCHG unported; SMB1351 no driver) | - (kernel) | msm8996-mainline `qcom_smbchg` | 2-3 wk (shared with Nura) | high; daily use blocker |
| Suspend | **broken** on msm8996 mainline | `suspend_blocker` (keep awake) first | dragonboard | 1 d / open-ended | high for battery life |
| Hall sensor | works (SW_LID) | lid in input/overlay | - | 1 d | low |
| GPS | works via QMI LOC (axon7-gps) | GNSS AIDL HAL over QMI LOC | new (small) | 1-2 wk | medium |
| Sensors | SLPI firmware present, no driver | qcom_smgr IIO port + IIO sensors AIDL HAL | patchew v2 + new HAL | 3-4 wk | high |
| Camera | CAMSS upstream; front OV8856 has a driver, rear S5K2T8 none | libcamera Android HAL (simple pipeline + SoftISP) | AOSP `external/libcamera` [V in manifest] | 4-8 wk | high |
| Modem control | online (rmtfs, qrtr, DMS) | radio AIDL HAL over QRTR/QMI (UIM, NAS, WMS, VOICE, WDS) | qrild/libqril as base | 6-10 wk | very high |
| Mobile data | no IPA v2.5 driver | rmnet + IPA v2.5 port | Sireesh's RFC | 3-4 wk | very high |
| Call audio | no q6voice upstream | q6voice/CVD port + HAL voice path | out-of-tree q6voice | 3-5 wk | very high |
| NFC | NXP NCI, mainline nxp-nci (kernel NFC stack) | NXP Android HAL expects a downstream char device | - | ? | out of scope for now |
| Fingerprint | TrustZone-owned | - | - | - | infeasible |

## 5. Testing without disturbing the other systems

Never touched: iOS (`userdata` = iOS root), Nura's microSD, `persist`,
`modemst1/2`, `fsg`, `fsc`, bootloader partitions, `boot` (shim), LineageOS
22.2's `system`/`vendor`. The `modem` partition is only ever mounted read-only.

**M0 (no repartition):** time-share `los_boot`. `ios/tools/axon7-los-test.sh`
already saves the old image (`boot-before.img`) and restores it; M0 boots a
ramdisk-only image (Android first-stage init + recovery-mode adbd, or a
minimal init that starts adbd), so no system partition is needed. LineageOS
22.2 is back after each test.

**M1+: LineageOS 22.2's slot (user decision, 2026-11-10: "you can replace
the LOS 22.2 that's currently installed for testing").** No new partitions
and no shim change; LineageOS 22.2 does not need to stay bootable.

| Partition | Size | LineageOS 24 use |
| --- | --- | --- |
| `los_boot` (LUN 0) | 96 MiB | boot image v2 (the shim's LineageOS entry) |
| `system` (sde13, LUN 4) | 5.5 GiB | super device: `super.img` (system, system_ext, product, vendor) via `androidboot.super_partition=system`. TWRP can no longer mount it as ext4 |
| `vendor` (sde28) | 512 MiB | unused |
| `los_metadata` (LUN 0) | 16 MiB | `/metadata` (ext4, formattable); 22.2's raw boot log there ends |
| `los_data` (LUN 0) | ~32 GiB | `/data` (f2fs, FBE). Must be wiped once (22.2's FBE data cannot be read by 24) |

Writes for a test (by the main session, from TWRP; LUN 1-4 are only
writable there): `boot.img`/`recovery.img` → `los_boot`, `super.img`
(sparse: `simg2img`) → `system`, wipe `los_metadata` and the start of
`los_data` before the first boot. Never: iOS `userdata`, Nura's microSD,
`persist`, `modemst*`, `fsg`, `fsc`, bootloader partitions, `boot`.

(The earlier proposal, a fourth slot `l24_*` carved from `los_data` with a
fourth boot menu entry, is dropped; its shim patch is in the git history of
this branch.)

**M0a' procedure (first phone test, about 20 min, nothing permanent):**

1. PC: `lineageos-24-mainline/scripts/make-m0-testimg.sh` → `/tmp/axon7m-m0/m0-test-boot.img`
   (checked offline by `axon7-androidimg.py check` and by the shim's own
   `android.c` built for the host).
2. Phone in TWRP: save `los_boot` (`dd if=/dev/block/by-name/los_boot of=/tmp/los_boot-before.img`,
   pull it), push and `dd` the test image into `los_boot`, set the boot menu
   to entry 2 (LineageOS) once (misc block 255, "AX7BOOT1", see the memory
   notes / `axon7-bootmenu`), reboot.
3. Expected: USB network 172.16.42.1 with telnet (no password), as with
   Nura's test image. Collect `dmesg`, `/proc/cmdline`, `/proc/iomem`
   (rmtfs, initrd), `ls /sys/class/udc`, `cat /sys/fs/selinux/policy_capabilities/memfd_class`
   (SELinux is built in but not initialised without a policy; expect "not mounted"),
   `/proc/config.gz` present.
4. If nothing comes up within 60 s: hold Power + Volume Up (TWRP), read
   `/sys/fs/pstore/console-ramoops*` and `pmsg-ramoops-0` (shim log).
5. Restore `los_boot` from the saved image in TWRP.

**Reading the log of a failed test boot (lesson from M0b, 2026-11-10):** the
pstore console zone (0xbfc00000) holds the log of the *previous* boot only
until the next kernel starts writing into it. With the test shim, any reset
after a LineageOS boot (watchdog, panic, Power + Volume Up) lands in TWRP,
and TWRP's 3.18 kernel shows the old log as `/sys/fs/pstore/console-ramoops*`
and then overwrites the zone with its own. So read `console-ramoops*` and
`pmsg-ramoops-0` (the shim's log: `LOS size=`, `LOS cmdline`, `LOS entry`,
`LOS dtb` right before the jump) **in that TWRP session**, before anything
reboots. What Nura stores in `/var/lib/systemd/pstore` afterwards is TWRP's
log. The shim's log never shows up in a mainline kernel: the shim writes it
at 0xbff00000, TWRP's pmsg zone, but mainline's ramoops order is dmesg,
console (0xbfd00000), pmsg (0xbfe00000), ftrace (0xbff00000), and the
ftrace zone's signature includes LINUX_VERSION_CODE, so Nura and the
LineageOS 24 kernel discard ("zap") it at boot. Nura's `pmsg-ramoops-0`
holds Nura's own lines only; ZTE LK rewrites the console zone with its log
at every start.

What is in `boot` (shim with or without the LineageOS entry, LOS_TEST or
normal, or a plain kernel that LK starts without any menu):
`scripts/boot-ident.py` (read-only, stdlib Python, runs on Nura as root).
Last known content (2026-11-09 11:29 and 12:36, saved by the test runs):
LOS_TEST shim + postmarketOS bundle, sha256 `e3ace801...0dcbd69`
(`ios/research/axon7/losdev1/boot-before.img`).

**M0b' procedure (2 tests, ~30 min, only `los_boot` and the boot menu are
written).** Both images are on the server in `/srv/los24/out-test/`; both
use kernel `7.3.1-axon7m` #3 (07:46 UTC, `WATCHDOG_SYSFS`), which no test
has booted yet.

1. Size test: `m0-pad15-boot.img` (45,858,816 bytes, sha256
   `61d8bd84dc52649993b5dff28adbee0856f5bac5f1a11e5b95bed67aabc09490`):
   the M0a'' busybox image plus 15 MiB of random data in the initramfs
   (`PAD_MB=15 scripts/make-m0-testimg.sh`), larger than the failed
   recovery image (44,310,528). Expected as in M0a'': telnet 172.16.42.1
   within ~30 s, `ls -l /pad.bin` = 15728640 bytes, `dmesg | grep -iE
   "Unpacking|Freeing initrd|Linux version"`, uptime past 60 s. If nothing
   comes up within 90 s: TWRP (the shim's 30 s watchdog does that by itself
   if the kernel never starts), pstore as above.
2. M0b front end: `m0b-fe-recovery.img` (45,453,312 bytes, sha256
   `819476cea960f2c9915481ee836f2d11501a412a984583136d5ac0bc9cbc1643`):
   the LineageOS 24 recovery (`recovery-orig-20261110-0329.img`) + adb key +
   the busybox front end `scripts/m0b-frontend-init.sh` (`rdinit=/axon7/init`):
   USB NCM + telnet 172.16.42.1 (busybox shell, Android's tools in
   /system/bin), busybox holds the watchdog, then `exec /init` (Android
   first stage, recovery mode). Kernel log on the panel (`console=tty0`).
   Collect over telnet: `dmesg` (whole: init's own log lines are in it),
   `cat /tmp/recovery.log`, `ps -A -o pid,args` (is `recovery`, `adbd`,
   `ueventd` running?), `/system/bin/getprop | grep -E "usb|init.svc|boot"`,
   `ls -l /dev/block/by-name/ | head` (checks `androidboot.boot_devices=soc@0/...`),
   `cat /sys/fs/selinux/enforce`, `ls /config/usb_gadget/`,
   `cat /sys/class/udc/*/state`. Expected while telnet holds the UDC:
   init's `write /config/usb_gadget/g1/UDC` fails with EBUSY (that shows
   adbd got as far as its descriptors). Then the adb test:
   `/axon7/adb-handover` (telnet ends; frees the UDC, `sys.usb.config` none
   then adb) and `timeout 60 adb wait-for-recovery; adb devices; adb shell
   getprop ro.build.fingerprint`. To end: in telnet `sync; reboot -f`, or
   with adb `adb reboot`; the test shim then goes to TWRP (read pstore
   there if anything was unclear). Set the boot menu back to postmarketOS.
   `FRONTEND=0 scripts/make-m0b-recovery.sh` builds the plain recovery with
   the same cmdline additions if needed.

**M0b' result (2026-11-10, main session; logs in
`logs/m0bprime-20261110/`):**
- Size test passed: `m0-pad15-boot.img` (45.9 MB) booted, telnet after
  25 s, `/pad.bin` 15728640 bytes, "Freeing initrd memory: 16476K",
  kernel #3 ran past 50 s without a watchdog reset; `reboot -f` went to TWRP
  through the test shim as designed. The image size never was the problem.
- Front end worked: telnet after 25 s, Android's second stage, ueventd,
  servicemanager, recovery (and charger) running, SELinux permissive,
  `ro.boot.boot_devices=soc@0/624000.ufshc` gives the by-name links
  (`boot -> sde12`). **Cause of M0b:** `recovery` SIGSEGVs ~0.6 s after
  every start (every 5 s): no DRM device ("Failed to find/open a drm
  device"), because recovery loads no kernel modules and msm DRM + the
  panel were modules; fbdev fallback on the 24 bpp simple-framebuffer:
  "gr_init: Only 4-byte pixel formats supported", then SEGV_ACCERR. It dies
  before setting `sys.usb.config=adb`, hence no USB at all.
- **adb works on mainline:** after `/axon7/adb-handover`, `adb devices`
  showed "7e15695a recovery", fingerprint
  `ZTE/lineage_axon7m/axon7m:17/CP2A.260605.016/eng.build:userdebug/test-keys`,
  shell as uid shell.
- Fix: `CONFIG_DRM_MSM=y`, `CONFIG_DRM_PANEL_SAMSUNG_S6E3HA3=y` in
  `kernel/android-axon7m.config` (kernel #4); M0b'' image below.

**Switching to the LineageOS entry remotely (works; the Nura route does
not):** `axon7-bootmenu default los 5` in Nura followed by a reboot came
back to Nura twice, even with the misc block verified with `iflag=direct`
(unexplained; needs someone to watch the menu). What works without anyone
at the phone:
1. Nura: `sudo systemctl reboot --reboot-argument=recovery` (PON reboot
   mode 1: LK starts TWRP, adb after ~30 s);
2. TWRP: `adb push misc-los.bin /tmp/ && adb shell dd if=/tmp/misc-los.bin
   of=/dev/block/sda3 bs=4096 seek=255` (`misc-los.bin`: "AX7BOOT1",
   entry 2, 5 s, 2 ^ 0xa5a5a5a5, padded to 4096; `ios/tools/axon7-los-test.sh`
   writes the same with 1 s);
3. `adb reboot`: the shim starts LineageOS. With the LOS_TEST shim the next
   reset after that goes to TWRP; set the default back to postmarketOS there
   (entry 1).

**M0b'' (display built in), images in `/srv/los24/out-test/`:**
`m0b2-fe-recovery.img` (46,964,736 bytes, sha256
`c38aa5491c4fbfbdd8b031dc43e4a10a1fbe3dc9b6dd82819a03e224691012a6`) = the
same recovery + front end with kernel #4 (12:27 UTC, Image 30 MiB);
`m0b2-fe-recovery-quiet.img` (same size, sha256
`d768b34ba044a642046ddf4c3311c5fe3f26de6c85e38634e54966729ebdeee2`) = the
same plus `androidboot.quiescent=1`
(recovery skips its UI, `StubRecoveryUI`: adb even if the display fails).
Expected with the first: the kernel log on the panel through msm DRM's
fbdev (simplefb replaced, `/proc/fb` "0 msmdrmfb"), `/dev/dri/card0`,
recovery's UI on the panel, `recovery` stays up (no SIGSEGV in `dmesg`),
`/tmp/recovery.log` without "gr_init" errors; adb after
`/axon7/adb-handover`. Collect `dmesg | grep -iE "msm|dpu|dsi|panel|drm"`,
`cat /proc/fb`, `ls -l /dev/dri`, `/tmp/recovery.log`. The second only if the
first still crashes.

**M1a procedure (first full boot; images from the build queued in
`los24next`, see section 9).** On the server after `build-exit 0`:
`out/target/product/axon7m/boot.img` and `super.img` (sparse). Check boot.img
on the PC with `scripts/shim-hostcheck.sh` and
`ios/tools/axon7-androidimg.py check` (cmdline must contain
`androidboot.super_partition=system`), then in TWRP: `boot.img` →
`los_boot` (dd), `scripts/simg-put.py super.img /dev/block/sde13` (only the
data chunks of the sparse image: ~2-3 GB instead of 5.5 GiB at TWRP's
~3.4 MB/s, every run read back with sha1; verify `sde13` is PARTNAME=system
first), wipe `los_metadata` (`dd if=/dev/zero bs=1M`, 16 MiB) and the first
64 MiB of `los_data` (22.2's FBE data cannot be read by 24), boot menu entry
LineageOS once. Expected: boot animation (SwiftShader, slow), `adb devices`
within ~3 min (developer build, PC key), `getprop sys.boot_completed`.
Checksums: printed by the build log's `ls -la` and to be taken with
`sha256sum` on the server before copying.

Test loop: reuse `axon7-los-test.sh` (unattended, pstore console; IMEM mark:
one LineageOS boot, then TWRP) with the same entry 2, writing `super.img` to
`system` instead of 22.2's system/vendor images. The test shim arms the APSS
watchdog (30 s) for this entry: the kernel must feed it, see section 8
(watchdog node, M0a').

## 6. Milestones

| # | Goal | Exit criterion | Needs phone | Estimate |
| --- | --- | --- | --- | --- |
| M0a | Kernel with Android config builds; boot image v2 builds | Image < 48 MiB, config check clean | no | 2-3 d (**in progress**) |
| M0a' | **Boot path test without Android**: Android-config kernel + Nura's storage-safe test initramfs (busybox, USB NCM 172.16.42.1 + telnet) as a header-v2 image in `los_boot` | telnet works; `dmesg` shows binder/SELinux/erofs/f2fs, rmtfs address, UDC `6a00000.usb`; pstore console after a crash | yes (1 test, ~20 min) | 1 d |
| M0b | Mainline kernel + Android first-stage init from `los_boot` | pstore shows init's first stage; adb in a ramdisk-only (recovery-mode) boot | yes (2-4 tests) | 3-5 d |
| M1a | Full Android boot with SwiftShader | `sys.boot_completed=1`, adb, boot animation then launcher (slow) | yes (22.2's slot) | **reached 2026-11-11** (run 14b: setup wizard "Welcome to LineageOS", SystemUI ANRs from CPU rendering) |
| M1b | freedreno + drm_hwcomposer + minigbm | SurfaceFlinger on DRM, smooth UI | yes | 1-2 wk |
| M2 | Wi-Fi, Bluetooth, USB (MTP/tethering) | connect to AP, pair a device | yes | 1 wk |
| M3 | Audio: speakers, headphones, mic, vibrator, torch, lights | media playback, recording, haptics | yes | 2 wk |
| M4 | Power: health, charging driver, suspend strategy, thermal | battery % in UI, charges from USB | yes | 2-4 wk |
| M5 | GPS + sensors (SLPI) | location fix, auto-rotate, proximity | yes | 3-5 wk |
| M6 | Camera (libcamera) | front camera preview/photo | yes | 4-8 wk |
| M7 | Telephony: SIM, SMS, calls, data | call with audio, mobile data | yes | 8-15 wk, may not finish |
| M8 | SELinux enforcing, FBE, flashable zip, user build, docs + XDA post | user-installable alpha | yes | 2 wk |

Order follows risk to the whole project: M0/M1 prove the kernel/boot/
graphics base everything else needs; telephony is last because it is the
most open-ended and the rest is useful as a Wi-Fi device without it.

## 7. Risks

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Shim's Android path + mainline kernel fails early (memory map, initrd vs. rmtfs) | M0 blocked | pstore console; Nura's pmos path as reference; the shim prints entry/DTB addresses |
| Build space on the server (199 GB free after the 24.0 sync started; tree ~100 GB + out ~100 GB) | builds fail | depth-1 sync done; `WITH_DEXPREOPT=false` in dev builds; build only needed images; drop unneeded prebuilts via `remove-project` if needed |
| Mesa freedreno on Android for a5xx | slow/no UI | SwiftShader fallback keeps the rest of the work going |
| No Vulkan (turnip has no a5xx) | some apps / future Android features | GL paths still exist in Android 17 [V renderengine]; watch deprecations |
| No charging control | battery drains while charging off USB | port SMBCHG (also wanted for Nura) |
| No suspend | poor standby | suspend_blocker first; cpuidle work later |
| Telephony stack (RIL + IPA v2.5 + q6voice) | no phone functions | treat as stretch; ship as Wi-Fi device first |
| Android 17 framework assumptions about ACK (quota2, uid_sys_stats) | log noise or broken features | ACK android-mainline fallback |

## 8. Findings while implementing

- Kconfig on 7.3.1 (2026-11-09): `SCHED_DEBUG`, `NF_CT_PROTO_UDPLITE` and
  `DMABUF_SYSFS_STATS` no longer exist; legacy iptables needs
  `IP_NF_IPTABLES_LEGACY`/`IP6_NF_IPTABLES_LEGACY`=y (else every `IP_NF_*`
  stays a module); `IFB` needs `NET_ACT_MIRRED`; Nura's lockdown LSM selects
  `MODULE_SIG` (dropped for Android).
- Server: `chown -R` on the kernel tree makes git re-hash all files (an hour
  on the busy HDD); `grep -q` behind `git log` under `pipefail` reports
  "not found" (SIGPIPE). Both handled in `kernel-build.sh`.
- Synced tree (2026-11-10): drm_hwcomposer ships as the APEX
  `com.android.hardware.graphics.composer.drm_hwcomposer`; minigbm has the
  AIDL allocator `android.hardware.graphics.allocator-service.minigbm` and the
  stable-C mapper `mapper.minigbm` (used here). Nura's config compresses
  modules with zstd (`MODULE_COMPRESS`, a bool in 7.3): switched off.
- **M0a' on the phone (2026-11-10, main session): the boot path works.** The
  mainline kernel booted from `los_boot` via the shim, USB network (NCM) and
  telnet were up at 5.3 s. Then a silent reset (no oops, log ends at 15.5 s,
  TWRP through the test shim's IMEM mark): the test shim arms the APSS
  watchdog (bark = bite = 30 s, `ios/shim/axon7.c` LOS_TEST) for the
  downstream kernel's msm_watchdog, and mainline `msm8996.dtsi` has **no
  watchdog node**, so `qcom-wdt` (built in, `WATCHDOG_HANDLE_BOOT_ENABLED`)
  never bound. Fix: `kernel/patches/0001` adds `watchdog@9830000`
  (`qcom,apss-wdt-msm8996`, `qcom,kpss-wdt`, bark SPI 28 as downstream).
  Nura is not affected (the shim's postmarketOS path leaves the watchdog
  off), but would gain a working watchdog from the same patch.
- **M0a'' (2026-11-10, main session): no reset any more.** With the watchdog
  node, `9830000.watchdog` binds as watchdog0, the heartbeat ran past 191 s;
  rmtfs at 0xbfa00000, no new errors (same benign ones as Nura: BAM DMA -22,
  UFS clock gating, PMIC temp-alarm deferred). `CONFIG_WATCHDOG_SYSFS` added
  for the watchdog attributes. Patch 0001 is also in Nura now (0025).
- **M0b without a new build:** `scripts/make-m0b-recovery.sh` repacks the
  built LineageOS 24 `recovery.img` with the current kernel/DTB and the PC's
  adb key as `/adb_keys` (`scripts/cpio-replace.py` edits the newc ramdisk
  in place, root ownership kept).
- **M0b on the phone (2026-11-10 07:53 UTC, main session): no USB, black
  screen, failed.** `m0b-recovery.img` (44.3 MB) from `los_boot`; for 6 min
  no USB device at all, then Power + Volume Up → TWRP (test shim's IMEM
  mark; its log says "Hard Reset and 'cold' boot", 08:03:59 UTC by the
  phone's clock) → postmarketOS. The pstore copy taken in Nura is that
  TWRP boot's console plus LK's log, so the M0b kernel's own log was
  overwritten by TWRP and is lost (procedure fixed in section 5). Analysis
  (no new phone data):
  - **Not a shim size limit.** `ios/shim/android.c` reads the whole image
    into a 128 MiB staging area at 0xa4000000 (2 MiB UFS commands, 2 s
    timeout each), copies the kernel to 0x80000000 and the DTB to
    0x81e00000 from a trampoline at 0xa3f00000, and leaves the ramdisk in
    place (initrd 0xa5b90000..0xa6a2dce3): all in plain RAM in mainline's
    map (memory 0x80000000-0x17e4bffff, reserved regions far from it),
    initrd reserved before any dynamic allocation. The host build of
    android.c accepts the image (`scripts/shim-hostcheck.sh`). The only
    size limits are 128 MiB (staging) and image_size ≤ ~48 MiB (kernel).
  - **The kernel most likely ran.** The test shim arms the APSS watchdog
    (30 s) before `android_boot()`: a failed start (error message under
    the menu) or a kernel that died before `qcom-wdt` probes would have
    been reset into TWRP, with USB, within ~35 s. The phone stayed without
    USB for 6 minutes, so something fed the watchdog: the kernel's
    watchdog core (`WATCHDOG_HANDLE_BOOT_ENABLED`). A black screen also
    fits: simplefb + fbcon take over the splash buffer (no `console=tty0`
    in that image, so no text).
  - So the failure is in Android userspace (recovery's init, `recovery`,
    adbd/configfs) or in kernel #3 after the watchdog probe. Recovery only
    binds the UDC after adbd wrote its FunctionFS descriptors and after the
    `recovery` binary set `sys.usb.config=adb` (it does that after UI
    init, `copy_userdata_files()` and a /data mount attempt), so any stall
    before that leaves no USB device at all. The busybox front end
    (M0b', section 5) answers which.
- **M0b' (2026-11-10): recovery has no kernel modules**, so everything the
  recovery UI needs must be built in: with msm DRM + panel as modules,
  minui fell back to the 24 bpp simplefb, failed and `recovery` crashed in
  a loop before enabling adb (section 5). Kernel #4 builds `DRM_MSM` and
  `DRM_PANEL_SAMSUNG_S6E3HA3` in (Image 28 → 30 MiB, 593 modules). Same
  rule for a normal boot's first stage: nothing before /vendor may need a
  module. `configs/modules.load.axon7m` is still empty, so the build lists
  all vendor modules for `axon7m-modules.sh` (to be narrowed for M2).
- Build host memory (2026-11-10): the first `m` OOM-killed soong_build in
  Android.bp analysis (container limit 31 GB, peak 30.76 GB, the 8 GB
  "virtual" swap of the unprivileged LXC container was hardly used, swap
  cannot be added from inside). Android 17's soong_ui dropped
  `SOONG_GOMEMLIMIT` and starts soong_build with `env -i`; the local patch
  `aosp/build/blueprint/0001-*` sets `debug.SetMemoryLimit` (80% of
  MemTotal). If that is not enough: more RAM or real swap for container 107
  on the Proxmox host (`pct set 107 --memory ... --swap ...`), a host action.
- `ios/` is a submodule (ios-sailfish). A fourth boot menu entry was
  prepared as a patch; not needed since LineageOS 24 uses 22.2's slot.

## 9. What is implemented, running jobs (2026-11-10)

| What | Where | State |
| --- | --- | --- |
| Plan, scripts, device tree skeleton, shim patch | branch `lineageos-24-mainline` of the zte-axon7 repo (local only, not pushed) | committed |
| LineageOS 24.0 source | `/srv/los24/lineage-24.0` (`repo init -b lineage-24.0 --depth=1 --git-lfs -g default,-darwin,-mips`) | **synced** (try 2, 00:37 UTC; 97 GB left on /srv). History: tmux `los24sync` (user `build`), `/srv/los24/sync.sh` retries 4x; try 1 ended with googlesource "Broken pipe" errors on ~20 projects, retries resume incrementally. ~80 GB so far, about 1-2 h to go |
| Kernel | `/srv/los24/kernel/linux` (v7.3.1 shallow + Nura 0001-0018, branch `axon7-android`) | **built and staged** 2026-11-10 00:40 UTC: `7.3.1-axon7m`, Image image_size 28 MiB, 605 modules, config check clean; rebuilt 07:46 UTC as #3 (`kernel/patches/0001` watchdog node, `WATCHDOG_SYSFS`): in `/srv/los24/kernel/prebuilt`, used by all M0b' images |
| M0a' test image | `/srv/los24/out-test/m0-test-boot.img` (sha256 `2f66b766...32aad8`, 30 MB) | **passed** on the phone as M0a'' (with the watchdog node, `m0b-test-boot.img`) |
| M0b images | `out/target/product/axon7m/{boot,recovery}.img` (29 / 42 MB, built 2026-11-10 03:29 UTC; recovery saved as `/srv/los24/out-test/recovery-orig-20261110-0329.img`) | repacked `m0b-recovery.img` **failed** on the phone (no USB, section 8). Recovery ramdisk: adbd, `init.recovery.axon7m.rc` (UDC `6a00000.usb`), no modules needed (UFS, dwc3, gadget built in). LineageOS userdebug is not debuggable and recovery has `ro.adb.secure=1`, so developer builds carry the PC's adb key (`AXON7_ADB_KEYS`, as in 22.2). Its fstab still names the l24_* partitions (built before the slot change) |
| M0b' test images | `/srv/los24/out-test/m0-pad15-boot.img`, `m0b-fe-recovery.img` | **ran** 2026-11-10: size fine, front end showed recovery's SIGSEGV loop (no DRM device), adb works after handover |
| M0b'' test images | `/srv/los24/out-test/m0b2-fe-recovery.img` (sha256 `c38aa549...91012a6`), `m0b2-fe-recovery-quiet.img` (`d768b34b...9ebdeee2`, + `androidboot.quiescent=1`) | **built, offline checks pass** (kernel #4 with msm DRM + panel built in; shim host check: entry 0x80000000, DTB 0x81e00000, staging to 0xa6cca000); waiting for the phone |
| Mesa freedreno | `/srv/los24/mesa/out` → `device/zte/axon7m-mesa` (`scripts/mesa-build.sh`: Mesa 26.2.6, NDK r30, API 35) | **built**: `libEGL_mesa.so`, `libGLESv2_mesa.so` (in `egl/`), `libgallium_dri.so` (19.5 MB); needs only core libdrm + LLNDK libs; used with `AXON7_GPU=mesa` (default stays SwiftShader for the first boot) |
| Vibrator HAL | `device/zte/axon7m/vibrator/` | written; compiles in the next build after `droid` |
| Bluetooth address | `device/zte/axon7m/bdaddr/` | dragonboard's `bdaddr` + `--nv` for ZTE's `persist/.bt_nv.bin` (host-tested parser), persist mounted `ro,noload` |
| M1a runs 1-14b (2026-11-11) | `ios/logs/los24-m1a-N-*` (pstore console, logcat, getprop, screenshot), images `research/los24-build-N` on the PC | **setup wizard reached** in run 14b. Fixes on the way: stale fstab from rsync -a (--checksum syncs), modules.load = the 81 Nura modules, debuggable userdebug (`LINEAGE_DEBUGGABLE_USERDEBUG`), kernel patch 0002 (PID 1 fs_struct), boot guard (recovery after 240 s without adbd), software KeyMint, minigbm `nocompression`, example AIDL audio HAL with a policy file naming default/r_submix/bluetooth modules, 4 GB dalvik heap. Each build ~16 min, each test ~10 min (delta flash) |
| Firmware (M2) | `vendor/zte/axon7m-firmware` in the server tree (`scripts/firmware-from-nura.sh`, 15 files, not in git) | build 15 is the first with `AXON7_FIRMWARE=1` (remoteprocs, a530, ath10k, QCA BT rampatch, regulatory.db) |
| M1b/M2 runs 15-18 (2026-11-11/12) | `ios/logs/los24-m1a-N-*` | firmware on (15: ADSP, BT rampatch/NVM), Mesa freedreno FD530 GLES 3.1 (16; panel garbled until `nocompression` also applied to Mesa, 17: MDP5 scans out linear only; no ANRs), Wi-Fi scans (18: PCIe rescan + goldfish `libwifi-hal-emu` via `BOARD_WLAN_DEVICE := emulator`), Bluetooth on. Developer builds run adbd as root. Run 18h: the panel was right (DRM plane dump), but SurfaceFlinger's GPU composition was black/garbage with the threaded RenderEngine; `debug.renderengine.backend=skiagl` fixed it (run 19: clean wizard screenshot). Mesa is the default from run 19 |
| M3 audio runs 20-23 (2026-11-12) | `ios/logs/los24-m1a-N-audio.txt` | mixer routes from Nura's UCM (`bin/axon7m-audio-routes.sh`), speaker/mic at CARD_0_DEV_1/CARD_0_DEV_0, kernel with the full Nura series 0001-0043 (merge of main), q6asm period steps (aosp/hardware/interfaces 0001 + `ro.vendor.audio.tinyalsa.period_step_frames=480`). Run 23: AAudio records through audioserver and the HAL (2 s, 48 kHz stereo), no ALSA errors on playback. Speaker test (audible) pending: 18:30 build without `AXON7_SPEAKER_MUTE` |
| M3 sensors run 24 (2026-11-12) | `ios/logs/los24-m1a-24b-*` | sensors HAL (IIO qcom-smgr accel/gyro/mag/prox-light), sns-reg serving the registry from /persist, smgr modules. Booted, then froze twice ~60 s in: sns-reg aborted on start (fdsan: close() of an fd owned by its FILE), so no sensors appeared, and `axon7m-slpi-kick` restarted the SLPI: the SLPI never came back up, then CPU stalls and a watchdog pretimeout without reboot (pstore in `los24-m1a-24b-ramoops.txt`). Fixed: fclose in sns-reg, no SLPI restart at boot. Build 25 pending (server reachable only from home) |
| Run 25 (2026-11-12) | `ios/logs/los24-m1a-25-*` | sns-reg serves 1437 keys from /persist, the smgr IIO devices appear, the HAL starts the accelerometer (24-byte scans). About 3 min after boot: kernel panic in RenderThread, `BUG at drm_crtc.c:161` (fence_to_crtc): dma_fence_signal_locked() NULLs the ops of CRTC fences while a SYNC_IOC_FILE_INFO name query is inside get_driver_name. Kernel patch 0003 warns instead. Nura has the same code: only userspace that asks fence names (Android HWUI) hits it |
| Runs 26, 26s (2026-11-12) | `ios/logs/los24-m1a-26*-hw.txt` | Kernel with patch 0003: no panic, wizard. Sensors work through sensorservice (tools/sensread, 2 s each): accel/gyro/mag 49 Hz, phone flat: accel (-1.78, -1.01, 10.40) m/s^2 (|a| 10.6, 8 % high: compare with Nura, maybe the registry offsets/scale are not applied), gyro z -0.047 rad/s at rest, mag |B| 74 uT (uncalibrated), light 25 lux, proximity 5 cm (far). Open: SELinux domain for the sensors HAL (init: "no domain transition"), accel magnitude |
| Reference trees | `/srv/los24/ref` (dragonboard, AOSPM qrild/libqril/tinyhal/vibrator-ff/lights/device_generic_sdm845) | cloned |

Check from the PC: `ssh root@compiler 'su - build -c "tmux ls"; tail -3 /srv/los24/logs/build-after.log /srv/los24/logs/build-latest.log'`.
`build-latest.log` points at the queued rebuild once it starts.

Next steps (2026-11-12): Wi-Fi association test, speaker/headphone
playback (M3; audible tests only 17:30-03:00, planned 18:30), headphone and
earpiece switching in the HAL, SELinux policy for the
firmware/DRM/minigbm denials, modem (rmtfs/qrtr) and sensors. All phone tests
run unattended (`ios/tools/axon7-los-test.sh`, `LOS_SETTLE`).

## 10. Sources

- LineageOS Changelog 32: https://lineageos.org/Changelog-32/
- LineageOS manifest lineage-24.0: https://github.com/LineageOS/android/tree/lineage-24.0
- AOSP kernel/configs at android-17.0.0_r1: https://android.googlesource.com/kernel/configs/+/refs/tags/android-17.0.0_r1
- libcutils ashmem-dev.cpp: https://android.googlesource.com/platform/system/core/+/refs/tags/android-17.0.0_r1/libcutils/ashmem-dev.cpp
- Compatibility matrices: https://android.googlesource.com/platform/hardware/interfaces/+/refs/tags/android-17.0.0_r1/compatibility_matrices/
- AIDL example audio HAL: https://android.googlesource.com/platform/hardware/interfaces/+/refs/tags/android-17.0.0_r1/audio/aidl/default/
- Default Bluetooth HAL: https://android.googlesource.com/platform/hardware/interfaces/+/refs/tags/android-17.0.0_r1/bluetooth/aidl/default/
- RenderEngine: https://android.googlesource.com/platform/frameworks/native/+/refs/tags/android-17.0.0_r1/libs/renderengine/skia/
- AOSP Mesa: https://android.googlesource.com/platform/external/mesa3d/+/refs/tags/android-17.0.0_r1/README.aosp.md
- Linaro dragonboard: https://android.googlesource.com/device/linaro/dragonboard/+/refs/heads/main
- ACK android-mainline: https://android.googlesource.com/kernel/common/+/refs/heads/android-mainline
- AOSPM: https://github.com/aospm (qrild, libqril, android_device_generic_sdm845, tinyhal, external_vibrator-ff)
- GloDroid: https://github.com/GloDroid/glodroid_manifest
- qcom_smgr v2: https://patchew.org/linux/20250710-qcom-smgr-v2-0-f6e198b7aa8e@protonmail.com
- IPA v2.x RFC: https://lore.kernel.org/all/20210920030811.57273-1-sireeshkodali1@gmail.com/
- Linaro, AOSP on Pixel 3 / Poco F1: https://old.linaro.org/blog/aosp-on-pixel3-pocof1-running-aosp-with-mainline-kernel-on-form-factor-devices
- This repo: `ios/shim/android.c` (LineageOS boot path), `docs/bootloader.md`,
  `postmarketos/README.md`, `DEV-MULTIBOOT.md`
