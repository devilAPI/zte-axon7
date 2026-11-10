# LineageOS 24 on mainline Linux for the ZTE Axon 7: plan

Status: **planning + M0 groundwork** (started 2026-11-09). Codename for this
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
| Partitions | dynamic partitions (**one `super` image**: system, system_ext, product, vendor), `metadata`, `data`, each in **its own new GPT partition** (`l24_*`) [D, needs the user's OK: §5] | doesn't touch LineageOS 22.2's `system`/`vendor`; one partition for all read-only images |
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
  `ProcessBootconfig(); ProcessKernelCmdline();`) [V]. That the super
  partition can be named by `androidboot.super_partition` (we use
  `l24_super`) is [A] until checked in the synced tree (`fs_mgr`).

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
  androidboot.super_partition=l24_super firmware_class.path=... console=...`
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
| Vibrator | works (ff haptics) | vibrator AIDL on input-ff | AOSPM `external_vibrator-ff` / AOSP default | 2 d | low |
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

**M1+ (needs the user's OK): a fourth slot.** Proposal, carved from the end of
`los_data` (LUN 0, ~32 GiB, last partition):

| New partition | Size | Use |
| --- | --- | --- |
| `l24_boot` | 96 MiB | boot image v2 |
| `l24_super` | 4.5 GiB | dynamic partitions (system, system_ext, product, vendor) |
| `l24_meta` | 32 MiB | `/metadata` (ext4) |
| `l24_data` | 10 GiB | `/data` (f2fs, FBE) |

This shrinks `los_data` from ~32 to ~17 GiB. f2fs cannot shrink safely, so
LineageOS 22.2's `/data` is **wiped** once (it is a developer install: setup
wizard again). The shim gets a fourth menu entry "LineageOS 24 (mainline)"
(`android_boot()` with the partition name as a parameter, `LOS_PART` is a
compile-time define today) and `axon7-bootmenu` learns entry 3. Alternative
without the wipe: keep time-sharing `system`/`vendor` with 22.2 (restored
after each test: several GB per test, slow) — not recommended past M1.

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

Test loop: reuse `axon7-los-test.sh` (unattended, pstore console, testlog on
the metadata partition), with an `L24` mode that writes `l24_boot`/`l24_super`
and selects menu entry 3 (IMEM/misc mark as today).

## 6. Milestones

| # | Goal | Exit criterion | Needs phone | Estimate |
| --- | --- | --- | --- | --- |
| M0a | Kernel with Android config builds; boot image v2 builds | Image < 48 MiB, config check clean | no | 2-3 d (**in progress**) |
| M0a' | **Boot path test without Android**: Android-config kernel + Nura's storage-safe test initramfs (busybox, USB NCM 172.16.42.1 + telnet) as a header-v2 image in `los_boot` | telnet works; `dmesg` shows binder/SELinux/erofs/f2fs, rmtfs address, UDC `6a00000.usb`; pstore console after a crash | yes (1 test, ~20 min) | 1 d |
| M0b | Mainline kernel + Android first-stage init from `los_boot` | pstore shows init's first stage; adb in a ramdisk-only (recovery-mode) boot | yes (2-4 tests) | 3-5 d |
| M1a | Full Android boot with SwiftShader | `sys.boot_completed=1`, adb, boot animation then launcher (slow) | yes, + new slot | 1-2 wk |
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
- `ios/` is a submodule (ios-sailfish): the fourth menu entry is prepared as
  `shim/0001-boot-menu-fourth-entry-l24_boot.patch` (host test builds with
  `-Werror`, aarch64 syntax check clean), not applied.

## 9. What is implemented, running jobs (2026-11-10)

| What | Where | State |
| --- | --- | --- |
| Plan, scripts, device tree skeleton, shim patch | branch `lineageos-24-mainline` of the zte-axon7 repo (local only, not pushed) | committed |
| LineageOS 24.0 source | `/srv/los24/lineage-24.0` (`repo init -b lineage-24.0 --depth=1 --git-lfs -g default,-darwin,-mips`) | syncing, tmux `los24sync` (user `build`), `/srv/los24/sync.sh` retries 4x; try 1 ended with googlesource "Broken pipe" errors on ~20 projects, retries resume incrementally. ~80 GB so far, about 1-2 h to go |
| Kernel | `/srv/los24/kernel/linux` (v7.3.1 shallow + Nura 0001-0018, branch `axon7-android`) | config check clean (0 differences); compiling in tmux `los24kernel`, log `/srv/los24/logs/kernel-build.log` (`kernel-exit 0` + `staged ...` when done; slow while the sync owns the disk: 30-90 min) |
| First Android build (M0b: `recoveryimage bootimage`) | tmux `los24build`, log `/srv/los24/logs/build-latest.log` | queued: starts by itself when sync and kernel are done; first build 2-4 h, low priority (nice/ionice) so 22.2 builds come first. Expect build errors from the untested skeleton |
| Reference trees | `/srv/los24/ref` (dragonboard, AOSPM qrild/libqril/tinyhal/vibrator-ff/lights/device_generic_sdm845) | cloned |

Check from the PC: `ssh root@compiler 'su - build -c "tmux ls"; tail -3 /srv/los24/logs/kernel-build.log /srv/los24/logs/build-latest.log'`.
If the sync gives up after 4 tries: `su - build -c "tmux new -d -s los24sync /srv/los24/sync.sh"` (incremental), then restart the build job the same way with `los24-build.sh`.

Next steps without the phone: make the device tree build (`m recoveryimage`),
verify the [A] items in the synced tree (fs_mgr `super_partition`, release
config name for lunch, minigbm mapper vs. AIDL mapper in Android 17), Mesa
NDK build for freedreno, port dragonboard's `bdaddr` for the BT address.

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
