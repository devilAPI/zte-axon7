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
| USB device modes | works (configfs) | UsbDeviceManager without a gadget HAL: kernel 0009 (empty `android_usb` class, "none" unbinds the UDC), `config_enableUdcSysfsUsbStateUpdate`, system/core 0002 (MTP/PTP on FunctionFS), vendor rc for RNDIS/NCM | AOSP | MTP + adb enumerates (build 42 + kfast kernel); tethering configured, not run with the PC (it would change the PC's network) | low |
| Display | works (DRM DPU, dual-DSI cmd mode, fbdev) | drm_hwcomposer (HWC3 AIDL) | AOSP `external/drm_hwcomposer` | 1 wk | medium: command-mode + bonded DSI through HWC3 untested anywhere [A] |
| GPU | A530 enabled in DTS, not used by Nura (console only); other msm8996 phones run Phosh on freedreno [A] | Mesa freedreno (EGL/GLES), minigbm `msm` gralloc + mapper | Mesa upstream (NDK build), AOSP minigbm | 2 wk | medium-high: zap shader load, Mesa Android build, a5xx+Android untested |
| GPU fallback | - | SwiftShader Vulkan (`vulkan.pastel`) + ANGLE | AOSP, dragonboard `swangle` | 2 d | low; slow at 1440x2560 |
| Touch, keys | works (RMI4, gpio-keys) | idc/kl files | - | 1 d | low |
| Wi-Fi | works (ath10k QCA6174, roaming fix 0008) | wpa_supplicant `-Dnl80211`, Wi-Fi AIDL HAL without vendor lib | AOSP, dragonboard | 3-5 d | low-medium (Wi-Fi HAL without a `libwifi-hal` vendor lib [A]) |
| Bluetooth | works, needs BD address (unconfigured until set) | `android.hardware.bluetooth-service.default` (HCI user channel via MGMT) [V], BD-address tool reading persist `.bt_nv.bin` (port of `axon7-btaddr`) | AOSP + dragonboard `bdaddr` | 3-5 d | low-medium |
| Audio out | headphones (AK4490), speakers (AK4961 + 2x TFA9890), earpiece switch; card "ZTE Axon 7", playback hw:0,1, capture hw:0,0 (r10) | AIDL audio HAL: fork of `hardware/interfaces/audio/aidl/default` primary module (`CARD_x_DEV_y` addresses [V]) + mixer routes from Nura's UCM | AOSP | 2 wk | medium |
| Microphone | mic 1 works (r10) | same HAL | | incl. | medium |
| Vibrator | works (ff haptics, `spmi_haptics`, FF_RUMBLE) | own AIDL IVibrator V4 on the FF device: `device/zte/axon7m/vibrator` | own | **works** (2026-11-16: 30 ms oneshot and a CLICK raise `haptics_play_irq`; touch haptics in the vibrator history) | low |
| Torch, LED | works (`white:torch`, RGB LED) | own lights AIDL HAL (`lights/`, multicolour `rgb:status`, software blink); torch through a torch-only camera HAL module (`camera/camera.axon7m` in LineageOS' AIDL camera provider) | own | **LED works** (build 42: HAL drives green/blinking red/off), **torch**: camera service sees camera 0 with flash (build 42), sysfs owner and the flash feature fixed in build 44 | low |
| Battery | FG read-only works | health AIDL default (sysfs power_supply) | AOSP | **works**: level, status, voltage, temperature in `dumpsys battery` and the status bar (example health HAL on `qcom-battery`/`qcom-smbchg-usb`) | low |
| Charging | `qcom-smbchg` from msm8996-mainline is in Nura's series (0024): SDP detected, 4.4 V / 2 A, status Full at 99 % (charges on LineageOS 24 too: `qcom-smbchg-usb`, status charging/full); SMB1351 parallel charger has no driver | - (kernel, shared with Nura) | msm8996-mainline `qcom_smbchg` | done in the kernel; SMB1351 open | medium (no fast charge above 2 A) |
| Suspend | **broken** on msm8996 mainline | keep-awake: `sys.autosuspend.disabled=true` plus an `axon7m-nosuspend` wakelock from init | - | done (keep-awake) | high for battery life |
| Hall sensor | works (SW_LID) | gpio-keys SW_LID read by InputReader; RRO `config_lidControlsSleep` | - | **works** as far as testable: `mLidState=LID_OPEN`, `getLidBehavior=LID_BEHAVIOR_SLEEP`; closing needs a magnet (owner) | low |
| GPS | works via QMI LOC (axon7-gps) | GNSS AIDL HAL over QMI LOC (`gnss/`), test tool `axon7m-gnss-test` | new (small) | **session works** (build 42: 1 position report/s, 6 NMEA/s); indoors no satellites, no fix: needs a test outdoors | medium |
| Sensors | qcom_smgr IIO drivers (Nura 0032-0040) | qcom_smgr IIO port + IIO sensors AIDL HAL | patchew v2 + new HAL | **works** (run 26); SELinux: HAL in `hal_sensors_default` (run 37), registry server in its own `axon7m_sns_reg` domain (build 43) | high |
| Camera | CAMSS upstream, OV8856, S5K2T8 (Nura 0027) and AK7375 probe on LineageOS 24 too (media0, 20 subdevs) | libcamera Android HAL (simple pipeline + SoftISP) | AOSP `external/libcamera` is ChromeOS' fork (mtkisp7) **without SoftISP**: the simple pipeline only gives raw Bayer, so a preview needs upstream libcamera's software ISP ported into the tree | 4-8 wk | high; **blocked** for now (torch-only HAL in place) |
| Modem control | online (rmtfs, qrtr, DMS); restarts itself every 40 s for the first ~5 min after boot (since build 38) | radio AIDL HAL over QRTR/QMI (`radio/`: libminradio + DMS/UIM/NAS) | AOSP libminradio | first step done (identity, SIM state, registration, signal); SIM files, SMS, voice, data open | very high |
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
| Runs 26, 26s (2026-11-12) | `ios/logs/los24-m1a-26*-hw.txt` | Kernel with patch 0003: no panic, wizard. Sensors work through sensorservice (tools/sensread, 2 s each): accel/gyro/mag 49 Hz, phone flat: accel (-1.78, -1.01, 10.40) m/s^2 (|a| 10.6, 8 % high; Nura reads the same raw values, (1.00, 1.77, -10.43) m/s^2: the kernel scale or SMGR calibration, not the HAL; axis mapping matches), gyro z -0.047 rad/s at rest, mag |B| 74 uT (uncalibrated), light 25 lux, proximity 5 cm (far). Open: SELinux domain for the sensors HAL (init: "no domain transition"), accel magnitude (kernel, shared with Nura) |
| M3 audio routing, build 27 (2026-11-12) | `ios/logs/los24-m1a-27-audio.txt` "== HAL routes", "== jack" | hardware/interfaces 0002: StreamPrimary sets the mixer per connected device from `/vendor/etc/audio_routes.conf` (speaker, earpiece, headphones = QUAT_MI2S Hi-Fi DAC, mic, headset-mic; from Nura UCM), wired devices without an address use `ro.vendor.audio.tinyalsa.default_{out,in}_address`, ModulePrimary accepts analog connections; policy: Earpiece, Wired Headset/Headphones/Headset Mic; RRO FrameworksResAxon7m: jack via input events (Nura kernel 0043 "ZTE Axon 7 Headset Jack"). Muted builds install audio_routes_muted.conf. Plug test needs the owner (headphones) |
| Performance, run 27p (2026-11-12) | `ios/logs/los24-m1a-27p-perf.txt`, `-live.txt` | Owner: "performance in LOS is bad". CPU at max (cpufreq-dt/schedutil), GPU freedreno FD530 (no llvmpipe), devfreq up to 624 MHz. SurfaceFlinger: `No Last HW vsync` although the DPU counts TE rd_ptr irqs (drm_hwcomposer delivers no vsync), all frames JANK_COMPOSER. Device composition (2 planes): locked at 30 fps (present2present 33 ms). Client composition (shade, animations): RenderEngine 48-90 ms per composite, 11-20 fps. App GPU frames 22 ms at 1440p (2 ms at 1080p, but `wm size 1080x1920` forces client composition: drm_hwc does not scale, worse). Also: drmhwc cannot set the backlight (EACCES on /sys/class/backlight/994000.dsi.0/brightness, bl_power). Home key: KEY_HOMEPAGE -> HOME works; the setup wizard disables HOME/RECENT (0x3a50000), by design. Next: vsync from drm_hwc, the 30 fps commit path (DPU cmd mode), backlight permissions, UBWC on DPU |
| Run 28 (2026-11-12) | `ios/logs/los24-m1a-28-perf.txt` | ueventd backlight rule works (brightness, bl_power system:system 0664), but changing screen_brightness left the value at 211: the slider still does not reach the panel. The msm GPU tracepoints were missing under events/msm (no GPU job timing). Next: HANDOFF.md 5.1 |
| Run 29 (2026-11-14) | `ios/logs/los24-m1a-29-perf.txt` | Image only (second adb key for the new PC, speaker unmuted), started from TWRP with the phone's own shim (`LOS_SHIM=keep`). The msm trace events exist (systems `drm_msm_gpu`, `drm_msm_atomic`, `dpu`; the probe looked under `msm*`). **30 fps cause:** a command-mode transfer takes 13.4 ms (TE -> pp_tx_done, matches the DSI clock), but the CRTC event and out-fence were sent at pp_done, so drm_hwc's release fences for the previous buffers came a whole transfer late: the app's GPU job (7 ms at 133 MHz) waited for them, SF missed the vsync, every frame took 2 vsyncs. GPU devfreq `performance` and `debug.hwui.render_ahead=1` changed nothing (still 33 ms). Fix: kernel patch 0004 (flip completes at the rd_ptr irq after the kickoff, the start of the transfer). Backlight works now (`cmd display set-brightness` 0.1 -> 138, 0.9 -> 250) but drm_hwc applies the HLG curve because the panel's `scale` is unknown: the low end is far too bright |
| Touch, run 29 hold (2026-11-14) | `ios/logs/los24-touch-getevent*.txt` | Owner: quick taps lost, typing impossible (Nura too). getevent: reports exactly every 156 ms (6.4 Hz), also with a resting finger. Not doze/nosleep, not wakeup-gesture mode (F12 ctrl20 = 0), not the charger bit (all set live with i2cset, no change), IRQ and reports 1:1. ftrace irq + i2c: the IRQ comes at once, then rmi_f12 reads **1658 bytes** of F12 data (153 ms at 100 kHz) though only Data1 (~80 bytes) is used. Fix in Nura's series r24: 0044 (read only up to Data1), 0045 (touch bus 400 kHz as downstream). Also seen: OGG/Vorbis ringtone fails (`Failed to create audio/vorbis decoder`, no sound) |
| Run 31 (2026-11-14) | `ios/logs/los24-m1a-31-*`, `los24-31-touch-getevent.txt` | Kernel 0002-0005 + Nura r24. **Touch fixed**: reports every 9.8 ms (was 156 ms), owner: typing works. **Backlight fixed** (scale linear: 0.1 -> 25, setting 40 -> 39). **Fences**: app dequeueBuffer 0.2 ms (was 20 ms), present2present 62x 16 ms / 71x 33 ms (was all 33 ms); now limited by app DrawFrames 20-30 ms and GPU 9-19 ms per frame (GPU devfreq at 133 MHz idle). Next: GPU clocking, Vorbis decoder |
| kfast tests (2026-11-14 evening) | `ios/logs/los24-kfast-*` | First kernel-only loop runs (scripts/los24-kfast.sh, about 3 min per kernel). **tsens**: CONFIG_QCOM_TSENS was off on Nura and LOS (no thermal zones, no throttling); on: 14 zones, 4 cooling devices. **Reboot reason**: PON 0x88f stayed 0x04 ("recovery") so every plain reboot from LOS went to TWRP; Nura 0046 clears it after boot, plain reboot returns to LOS (tested). **Watchdog**: qcom_wdt was never armed (a hang needed a button); for unattended runs kfast starts a petting loop, an init watchdogd service comes with the next image. Scroll benchmark (fps.sh) too noisy for clock tuning: GPU/CPU `performance` did not help (temperatures 45-48 C, no throttling) |
| Modem by hand on build 31 (2026-11-14) | - | **Modem online on LineageOS 24**: dragonboard's rmtfs (read-only `-r`, starts the remoteproc with `-s`) and a new QMI DMS online tool (axon7m-modem-online), NDK static builds pushed by hand. MBA + MPSS boot in 2 s; QRTR lists DMS (2), LOC (16), NAS, WMS, UIM, VOICE, WDS, PDC, IPA control and more; operating mode 5 -> 0 (online) with one switch, stable. In the device tree for build 33 (init: rmtfs, then axon7m-modem-online). Next: GNSS HAL over QMI LOC (subagent), then RIL (qrild/libqril) |
| Vorbis / Codec2 (2026-11-14) | - | MediaCodecList had only AAC: `media.c2.hal.selection` defaulted to hidl, there is no hwservicemanager, so media.swcodec registered an empty AIDL store. `media.c2.hal.selection?=aidl` (as cuttlefish): Vorbis plays, the microphone hears the speaker at 10-20x silence (first confirmed speaker output on LOS 24) |
| Runs 32-33 (2026-11-14) | `ios/logs/los24-m1a-32-*`, `-33-*` | 32: media.c2.hal.selection=aidl and watchdogd from the image work (Vorbis decoder, watchdog active without help). los24-bench (repeatable, 3 rounds): app frame p50 27 ms, p90 36, 20.6 % janky, SF 82 % of intervals at one vsync, **unchanged with GPU/CPU performance governors**. framestats: RenderThread issuing GL 11 ms, GPU completion 9.7 ms. simpleperf: 28 % of RenderThread in the kernel, IOMMU map/unmap from msm_gem_vma_map (submit) and msm_gem_close: Mesa's Android EGL re-imported the window buffer every frame -> Mesa patch 0001 (keep the DRI image per color_buffers slot). 33: modem and GNSS HAL from the image (rmtfs, DMS/LOC up), but the HAL returned OK + null for Psds and system_server crashed every ~35 s in GnssPsdsAidl::setCallback (phone stayed on adb); fixed for 34 (all extensions unsupported with an error status) |
| Run 34 (2026-11-14) | `ios/logs/los24-m1a-34-*` | GNSS HAL starts without crashing system_server (extensions with error status). QMI UIM card status (qmi-raw 11 0x2f): both slots "card error 3" (no ATR); SIM presence asked in to-test.md. Mesa 0001: kernel share of RenderThread 28 % -> 18 %, IOMMU map/unmap gone, framestats total 38.8 -> 29.6 ms in a good run, but los24-bench is bimodal on this build (passes at p50 26-27 ms and passes at 73-77 ms, independent of the GPU governor). A/B with the debug.mesa.android.nocache switch in build 35. Note: `adb remount` fails (erofs) but remounts persist rw: never use it |
| Run 35 (2026-11-14) | `ios/logs/los24-m1a-35-*`, `ios/logs/los24-run35-outer.txt` | Mesa 0001 A/B with debug.mesa.android.nocache, los24-bench 4 rounds x 3 alternating passes: cache on p50 26-150 ms per round, median of passes 67/73/77 ms, sf 16 ms 22-82 %; cache off p50 27-38 ms, median of passes 27.5/29.5/28.5 ms, sf 16 ms 67-83 %. The cache causes the slow mode (cause not known: candidates are freedreno keeping the resource valid (GMEM restore) or implicit-sync waits on a long-lived BO). 0001 now ships with the cache off by default (setprop debug.mesa.android.nocache false turns it on); mesa-build.sh resets the Mesa tree before applying patches |
| Run 36 (2026-11-14) | `ios/logs/los24-m1a-36-*` | Mesa 0001 with the cache off by default: los24-bench 4 rounds p50 27-28 ms, p90 38-40, p99 48-69 ms, sf 16 ms 80-84 %, no slow rounds. axon7-los-test.sh with LOS_SHIM=keep now reboots a running LineageOS to TWRP first (the first try of run 36 fell through to the postmarketOS path and flashed nothing) |
| Run 37 (2026-11-15) | `ios/logs/los24-37-avc.txt`, `ios/logs/los24-soak-base-36.txt`, `ios/logs/los24-37-sched.txt` | sepolicy: GPU nodes, minigbm, sensors HAL, rmtfs and modem-online in their own domains (still permissive), all services up. Bench p50 23-24 ms, ~18 % janky. HWC layers all DEVICE (no GPU composition). Trace: SurfaceFlinger blocked ~8 ms per frame inside drm_hwcomposer's Commit_nonblock: drm_atomic_helper_swap_state waits for the previous commit's hw_done, which msm signalled only after the ~15 ms command-mode transfer. New tool tools/los24-soak.sh (baseline 20 min on 36: clean) |
| Kernel 0006 (2026-11-15, kfast on build 37) | `ios/logs/los24-0006-perf.txt`, `ios/logs/los24-soak-hwdone-0006.txt` | msm: hw_done right after the flush (as drm_atomic_helper_commit_tail), dpu: kickoff counter so a stale complete_commit leaves the newer flip event alone. SF composite median 13.1 -> 5.7 ms, HwcPresentOrValidateDisplay 10.2 -> 2.9 ms, Commit_nonblock 0.23 ms; bench janky 18.5 -> 13.4 %, p50 23 -> 20 ms. 20 min soak clean. Also for Nura (same driver) |
| Run 38 (2026-11-15) | `ios/logs/los24-m1a-38-*` | Firmware from the phone (AXON7_FIRMWARE=phone, default): modem vfat at /mnt/vendor/firmware_mnt, GPT vendor ext4 ro,noload at /mnt/vendor/fw_vendor, /vendor/firmware links (scripts/gen-firmware-links.py); only linux-firmware files in the image. GPU (a530_zap) and modem fine; ADSP, SLPI and Wi-Fi offline ("Direct firmware load ... failed -2"): ueventd's modalias autoload ran qcom_q6v5_pas/ath10k/venus at coldboot, before the mounts. ADSP by hand later: sound card up |
| Run 39 (2026-11-15) | `ios/logs/los24-m1a-39-*` | configs/modules.blocklist (q6v5_pas, ath10k_pci, venus-core): ueventd skips them, axon7m-modules.sh loads them after mount_all --early. All remoteprocs running, wlan0, card "ZTE Axon 7", 5 sensors, freedreno, modem online. One dpu kickoff timeout at 212 s removed the vblank irq for good (see kernel 0007): bench p50 28 ms first, 70+ ms later, apps in dequeueBuffer ~17 ms. Test zip (ci/make-zip.sh on this output, 1.06 GB): `ios/research/los24-zip/`. **Release builds have no adb key: never install one on the main phone unattended** (adb needs an on-screen confirm after the installer wipes los_data) |
| Kernel 0008 (2026-11-15, kfast on build 39) | `ios/logs/los24-soak-k0008-gpuperf.txt` | **GPU faults and wallpaper band:** on a5xx every process shares the GPU's global VM, and msm_gem_close() unmapped a shared (minigbm/dma-buf) buffer's iova when *one* process closed its handle; the others kept the iova in their command streams (Mesa softpin, no relocs): 178 "gpu fault ... TRANSLATION" lines in an hour of build 39 (also WRITE faults), reads/writes of whatever buffer got the range next. 0008 v1 (skip the teardown while other handles exist): 0 faults in 3.5 h and bench, but a 20 min soak (GPU `performance`) ended after 14 min in an OOM panic, "System is deadlocked on memory", shmem 3.2 GB: the VMA holds a reference to the object, and buffers whose last handle was closed by a context without a GPU VM (drm_hwcomposer's KMS fd) were never unmapped, so never freed. 0008 v2: the global VM's VMA goes in msm_gem_vma_put() when vma_ref (handles + dma-buf exports) drops to zero, as the kms VMA already does. Bench (3 rounds) janky 9.4 % p50 16 p90 24 p99 42 ms (0007: ~12 %, p50 20). framestats: GPU 15 ms per frame (IssueDrawCommands -> GpuCompleted), devfreq simple_ondemand mostly 133-315 MHz; with the GPU governor `performance`: **janky 2.0 %, p50 10, p90 24, p99 36 ms**. init sets `performance` at boot_completed (the GPU still runtime-suspends when idle). Also for Nura (same driver) |
| Web content blank (2026-11-15) | logcat of build 39 | Cromite's renderers (isolated, seccomp: file system calls fail with EPERM) logged ~18000x `readlink(/proc/self/fd/N) failed` + `Unable to stat ashmem device`: libcutils' is_memfd_fd() needs readlink, the fallback needs /dev/ashmem (none on mainline), so every shared memory region was invalid in the renderer and pages stayed blank (also with --disable-gpu). aosp/system/core 0001: when readlink fails with EPERM/EACCES, recognise the memfd by its F_SEAL_GROW/SHRINK seals (F_GET_SEALS is allowed in Chromium's sandbox) |
| Run 40 (2026-11-15) | `ios/logs/los24-m1a-40-*`, `ios/logs/los24-soak-b40-k0008v2.txt` | Build with SELinux round 2 (`m selinux_policy` passes; the kernel's /mnt/vendor search needed `system_writes_mnt_vendor_violators` for the platform neverallow), libcutils memfd patch, GPU `performance` from init, kernel 0008 v1 (leaky; replaced by kfast with v2). Denials in the first boot 442 -> 261. **Web pages render** in the LineageOS browser (WebView) and in Cromite (local test page via adb reverse; no ashmem errors). Kernel 0008 v2 by kfast: bench janky 1.5 %, p50 10 ms; 30 min soak clean (no reboot, no system_server restart, no tombstones/ANR, no kernel warnings, 0 GPU faults, 0 kickoff timeouts, thermal max 61 C; Shmem back to 365 MB after `am kill-all`, no GEM leak). Note: right after a fresh install (first ~10 min, background dexopt and app setup) the bench reads p50 23-24 ms, janky 17-18 %: bench only after the system settled. Tool note: axon7-los-test.sh's postmarketOS probe pings 172.16.42.1, which is now the second phone's USB network (an ssh password prompt hung run 40): pass `PMOS_HOST=user@192.0.2.1` with `LOS_SHIM=keep` |
| Run 41 (2026-11-15) | `ios/logs/los24-m1a-41-*`, `ios/logs/los24-soak-b41.txt` | Full build with kernel 0002-0008 (v2). Bench (settled, Settings/SystemUI/Launcher compiled `speed`): **janky 1.99 %, p50 10, p90 18, p99 38 ms** (3 rounds 1.9/3.2/2.0 %). Cromite renders (`los24-m1a-41-cromite.png`). 0 GPU faults, 0 kickoff timeouts in the boot log. **30 min soak clean**: 30 iterations, no reboot, no system_server restart, no tombstones/ANR, no kernel warnings, 0 GPU faults, 0 kickoff timeouts, thermal max 64.5 C; one app crash (DeskClock under monkey: `IllegalStateException: FragmentManager is already executing transactions`, an app bug). Open: the dpu kickoff timeout of run 39 (one at 212 s) did not come back in ~2.5 h of tests with 0008; with 0007 it costs one frame. Remaining denials (261): kdevtmpfs, memfd MessageQueue (tmpfs), vendor_default_prop reads by apps, /dev/dri/card0 getattr. Bluetooth aborted once at first boot of build 40 (`hci_layer.cc on_hardware_error 0x8e`), came back on |
| Run 42 (2026-11-16) | `ios/logs/los24-m1a-42-*` (`-hwcheck.txt`, `-gnss.txt`) | Lights HAL, torch-only camera HAL, USB device mode, lid RRO, GNSS test tool, kernel 0009 v1. **Lights**: `service call` on ILights drives the LED green, blinking red, off (`multi_intensity`, `brightness` 511/0). **Camera service**: 1 device, back, "Has a flash unit: true"; torch write EACCES (provider runs as user cameraserver, sysfs was system:cameraserver), SystemUI's flashlight tile absent (`mCameraId=null`: no camera flash feature). **USB**: `/sys/class/android_usb` exists, `dumpsys usb` has the device manager (connected, configured from the UDC state file); `svc usb setFunctions mtp` stayed adb: init writes "none" to UDC, mainline answered EBUSY. Kernel 0009 v2 by kfast ("none" unbinds) + ep0 modes by hand: mtp,adb enumerates (18d1:4ee2, MTP + ADB interfaces), MtpService runs; MtpServer could not open the bulk endpoints (fmode 0600, fixed in the mount options). **Lid**: `LID_OPEN`, `LID_BEHAVIOR_SLEEP`. **Battery** in the UI, charging/full. **Vibrator**: `haptics_play_irq` counts each pulse (30 ms). **GNSS**: LOC session gives 1 position report/s and NMEA, no satellites indoors. **Modem**: restarts every 40 s ("fatal error without message") for ~5 min after boot, then stays up (also in runs 38-41; runs 36/37/39 had none); DMS/NAS/UIM/LOC appear after that. Bench (1 round, b42): janky 3.0 %, p50 11, p99 36 ms (41: 2 %, 10, 38). adb note: once the PC's adb server reported "no permissions" for TWRP's 19d2:0306 until `adb kill-server` (only the main phone uses adb) |
| Run 43 (2026-11-16) | `ios/logs/los24-m1a-43-*` | Radio HAL (libminradio + QMI), `axon7m_sns_reg` domain. Sensors fine in the new domain (5 sensors). Telephony features declared: com.android.phone binds the HAL; before the modem is up every request answers MODEM_ERR (phone stays healthy); afterwards `gsm.version.baseband` = `4-M8996FAAAANAZM-2 1 [Nov 02 2017]`, `gsm.sim.state` CARD_IO_ERROR (UIM: card error, no ATR, as on Nura), then the HAL aborted in a loop: libminradio CHECKs a serving cell in makeCellInfo (none while unregistered). Fixed for 44 (no cell info while unregistered; SIM file/APDU requests answer errors instead of libminradio's virtual SIM, whose file system CHECKs real requests) |
| Run 44 (2026-11-16) | `ios/logs/los24-m1a-44-*` (`-drivers.txt`, `-bench.txt`), `ios/logs/los24-soak-b44.txt` | Kernel 0009 v2, MTP/PTP functionfs modes, torch owner, camera flash feature, radio fixes. **Torch from the Quick Settings tile**: on (brightness 16, "Torch for camera id 0 turned on"), off. **MTP**: `svc usb setFunctions mtp` -> mtp,adb, the PC lists "Internal shared storage" and reads a test file (gio). **Radio**: no HAL crash over the modem's restarts and after, `gsm.sim.state` CARD_IO_ERROR via simStatusChanged, OUT_OF_SERVICE (no SIM). First boot: 4 com.android.phone ANRs ("failed to complete startup") while system_server's main thread was busy (AppOps/permission cache, first-boot load) and one Bluetooth HAL abort (`FD_SET: file descriptor -1`, as at build 40's first boot). The radio HAL now answers from a cache (build 45). Bench (3 rounds, settled, apps compiled speed): **janky 1.69 %, p50 10, p90 16, p99 40 ms** (41: 1.99 %, 10, 18, 38). **30 min soak clean**: 30 iterations, no reboot, no system_server restart, tombstones +0, ANR +0, crashes 0, kernel warnings +0, no lmk kills, thermal max 57.5 C |
| Run 45 (2026-11-16) | `ios/logs/los24-m1a-45-*`, `ios/logs/los24-soak-b45.txt` | Radio HAL answering from the polled cache. No HAL crash, SIM CARD_IO_ERROR, registration NOT_REG_MT_SEARCHING_OP (GSM) reported. Modem came up without restarts this time. First boot: still 2 com.android.phone ANRs, the main thread in `RIL.getRadioServiceProxy` -> `ServiceManager.waitForDeclaredService` -> `javaObjectForIBinder` (all five radio services were registered ~1 min earlier; first-boot load, not the HAL's answers); after a reboot none. **Bluetooth** (not changed here, open): in runs 38, 39, 44 and 45 the QCA6174 setup ended with `hci0: Opcode 0x0c03 failed: -110` (HCI reset timeout); the default Bluetooth HAL then waits for hci0 forever in initialize() with no binder thread, `service list` hangs at IBluetoothHci and Bluetooth stays BLE_TURNING_ON until a reboot. Bench (3 rounds): **janky 2.46 %, p50 10, p90 19, p99 48 ms** (41: 1.99 %, 10, 18, 38; 44: 1.69 %, 10, 16, 40). Soak: **kernel panic after 37 min** (iteration 28): a DPU command-mode kickoff timeout (`_dpu_encoder_phys_cmd_wait_for_idle ... kickoff timeout`, as once in run 39) queued the display snapshot, whose worker read the DSI PHY registers unclocked: `SError Interrupt on CPU2 ... msm_disp_snapshot_add_block <- msm_dsi_phy_snapshot`, panic, restart into TWRP (test shim mark; pstore in `ios/logs/los24-soak-b45-panic-ramoops.txt`). Kernel 0010: the snapshot only with `msm.disp_snapshot=1` |
| Kernel 0010 (2026-11-16, kfast on build 45) | `ios/logs/los24-soak-b45k10.txt` | drm/msm: no display snapshot on errors unless `msm.disp_snapshot=1` (`/sys/module/msm/parameters/disp_snapshot` = N). Staged in `/srv/los24/kernel/prebuilt` for the next image build. Soak 1 (`los24-soak-b45k10.txt`): **second SError panic** after 9 min (uptime 554 s), this time inside the DPU interrupt (`msm_mdss_irq -> dpu_core_irq -> dpu_encoder_phys_cmd_te_rd_ptr_irq`, reported at the trace marker after `dpu_encoder_vblank_callback`; pstore `ios/logs/los24-soak-b45k10-panic-ramoops.txt`), restart into TWRP. Control (`los24-soak-b45ctl.txt`, radio/camera provider/lights HAL stopped): no panic in 30 min, but not a clean control: without the lights HAL system_server's LightsService waits for it and the watchdog restarts system_server every ~70 s. Soak 2 with everything running (`los24-soak-b45final.txt`): **clean**: 29 iterations, no reboot, no system_server restart, tombstones +0, ANR +0, kernel warnings +0, thermal max 63.6 C, one app crash (Dialer NPE in DefaultFutureCallback, app bug); one kickoff timeout in dmesg, no panic (snapshot off). So: 2 SError panics in ~70 min of soak on build 45, none in builds 41/44 or in the last 30 min; both in the display path after or around a command-mode kickoff timeout, which the earlier runs also had (39, 44, 45 first boots). Open: the DPU/DSI access that faults (an unclocked INTF/PP/DSI block during a kickoff timeout or screen off) |
| DPU SError analysis 1 (2026-11-16) | `ios/logs/los24-soak-b45k10-panic-ramoops.txt`, `-b45-panic-ramoops.txt` | **Is kernel 0007 (Nura 0047) the cause? No, as far as the dumps show.** 0007 only changes what happens after a pp_done (kickoff) timeout: upstream unregisters the rd_ptr callback there, 0007 keeps it. Panic 2 (uptime 554 s) has no kickoff timeout and no DRM error at all in its ramoops record (275-554 s); the rd_ptr callback was registered because vblank was on (SurfaceFlinger), as upstream does without 0007. Panic 1 followed a kickoff timeout, but crashed in the display snapshot, which upstream queues in the same place before the unregister that 0007 removes. Neither panic depends on 0007 keeping the callback; 0007 does not make it worse. What is known about panic 2: async SError on CPU0 inside the MDSS interrupt (`msm_mdss_irq -> dpu_core_irq -> rd_ptr callback -> dpu_encoder_vblank_callback`, reported at the trace marker after `dpu_crtc_vblank_callback`); in that window the CPU reads the DPU interrupt status and the pingpong line count (`get_scanout_position` for the vblank timestamp). Next: an ftrace record of the display, runtime-PM and clock events dumped into pstore at the panic |
| Crash hunt with ftrace in pstore (2026-11-16, build 45 + kernel #18) | `ios/logs/los24-dpu-stress1-panic-ramoops.txt`, `los24-dpu-stress2-oops-ramoops-*.txt` | Display, runtime-PM, clock, interconnect and IRQ events into a 24 kB ring, dumped (panicking CPU) into pstore at a panic (`trace-setup.sh`: tracefs + `ftrace_dump_on_oops=orig_cpu`), plus a screen off/on + scroll + rotate stress. Two more crashes, neither in the display path: (1) during a libcamera test: SError right after an `a0c000.cci` interrupt (camera I2C) once the client was killed: `cci_isr()` reads the status register even when the interrupt arrives after the runtime suspend switched the CCI clocks off -> **kernel 0011** (no CCI interrupt while suspended). (2) after 15 stress rounds: Oops in `queued_spin_lock_slowpath` from `qcom_slim_ngd_tx_msg_dma_cb()` (SLIMbus to the ADSP codec), right after "QMI TXN wait fail: -110": a TX that timed out left its on-stack completion in the DMA descriptor and the late DMA callback completed freed stack memory -> **kernel 0012** (forget the completion and the transaction id of a timed-out TX). Lock/unlock UI sounds make SLIMbus traffic on every screen toggle; with the soak's screen toggles this can explain random crashes. The rd_ptr SError (panic 2) is still unexplained; the ftrace record will show its context if it comes back |
| Camera: upstream libcamera (2026-11-16) | `scripts/libcamera-build.sh`, `libcamera/patches/`, `tools/lc-snap.cpp` | Upstream libcamera (0.8-dev, da6a6ed) built with the NDK and meson like Mesa: simple pipeline, software ISP (CPU), its IPA (isolated through `softisp_ipa_proxy`), Android HAL (generic platform). Patches: libyuv without system libjpeg (0001), thread affinity on bionic (0002), **NV12 output from the CPU debayer** (0003: Android's YUV/preview/JPEG paths need NV12, the soft ISP only wrote RGB), HAL buffers: minigbm's real NV12 layout from cros_gralloc_handle and dma-heap internal buffers instead of gralloc0 (0004), torch on the back camera's flash LED (0005), NV12 widths only in multiples of 128 (minigbm's Venus stride, 0006). On the phone without Android (`lc-snap`, root, libraries in /data/local/tmp): both sensors enumerate (`/base/soc@0/cci@a0c000/i2c-bus@0/camera@2d` S5K2T8 back, `.../i2c-bus@1/camera@36` OV8856 front) and stream through CAMSS + soft ISP: front 1640x1232 at 13-20 fps, back 1472x836 at 21-25 fps (BGR888). Image content could not be judged: the room was dark (mean 36/255, uniform; the torch raised the back camera's mean only to 39, phone lying on the table). The HAL replaces the torch-only module from build 46 on |
| Camera HAL through cameraserver (2026-11-16, build 46 + bind-mounted HAL) | `tools/cam2test.cpp`, `libcamera/patches/0007-0009`, `ios/logs/los24-m1a-46-camera*.txt` | Build 46 listed both cameras (HAL id 0 front OV8856, id 1 back S5K2T8 with flash) but no frame reached an app. Fixed in order: (a) configureStreams failed with "Camera configuration adjusted" (colour space only) -> 0007; (b) the provider aborted on the first request in the vendored `append_camera_metadata` (Android 17 settings fail the old copy's validation) -> 0008, link the platform `libcamera_metadata`; (c) minigbm's handle has 5 fd slots (DRV_MAX_FDS = planes + 1) and one fd per plane: the magic is at data[26], not 25, and "Discontiguous planes" rejected every buffer -> 0004 fixed; (d) BLOB buffers had 0 planes and the JPEG destination was described as NV12 -> 0004 + 0009. The test tool also needed its own binder thread pool (cameraserver dequeues the ImageReader's buffers over binder; without it the request thread blocked in dequeueBuffer). Result with the NDK Camera2 test (root, `cam2test`): **back 1280x960 NV12 60 frames at 21 fps, front at 27 fps; JPEG 1920x1080 on both, 30 still captures at ~17 fps**, provider without crashes. The first still is black (exposure not settled); the images after it are uniform grey (Y mean 47-49, stddev 1): the phone lies in the dark, image content still unchecked (owner check with light). Open: libcamera ignores `camera_hal.yaml` rotation because the DT gives one (back 270, front 0; check against the sensors' mounting); "Unable to get rectangle" from ov8856 (no selection API, harmless). Build 47 adds the Aperture app |
| Run 47 (2026-11-16) | `ios/logs/los24-m1a-47-*` | libcamera HAL with patches 0004 (fixed), 0007-0009, Aperture, kernel 0002-0012. Boot clean: modem online once (no restart loop), no fatal crash in logcat, Bluetooth setup without reset timeout. The run's own camera step left empty files (provider restart commands of an older test script; cam2test results are in the camera row above) |
| Animations: QSEED2 scaler + GPU DDR votes (2026-11-16, build 47 + kfast #20-#23) | `ios/tools/los24-anim.sh`, `ios/logs/los24-bench-b47k23.txt`, kernel 0013, 0014 | Owner's report: animations 28-41 % janky. Cause (coordinator): any scaled layer (wallpaper at 1.1x zoom, windows in transitions) failed drm_hwcomposer's test commit with -ENODEV because dpu never programmed msm8996's QSEED2 scaler, so SurfaceFlinger composed everything on the GPU. **Kernel 0013** programs QSEED2 on the VIG pipes as MDP5 did (phase steps, bilinear up / PCMN down, one pixel edge repeat by SW pixel extension, YUV always through the scaler); a plane is fetched by one pipe across both mixers (source split), so the 1440 px dual-mixer layout needs no seam handling. Checked with drm.debug=0x12: the scaled wallpaper (1310x2328 -> 1440x2560) commits on sspp 1 (VIG0) next to DMA/RGB pipes, no failed checks during the shade, launcher and app transitions; no new DPU errors (the 3-4 kickoff timeouts around boot were in builds 46/47 too). At rest drm_hwcomposer flattens to one client layer, so `dumpsys SurfaceFlinger` shows CLIENT when idle. Visual seams could not be checked hands-off (screencap shows SurfaceFlinger's output, not the DPU's). **Kernel 0014**: the GPU's OPPs had no bandwidth, the GPU voted no DDR (`mas_oxili 0/0`), DDR ran at the display's 3.4 GB/s; now 1.6-14.4 GB/s by OPP, 1.6 GB/s when idle. A CPU -> DDR vote per CPU OPP was tried and dropped (no measurable gain, raises the DDR floor). janky % (ripple / ripple+open/back / shade / drawer / app open): build 47 8-10 / 31-33 / 31-41 / 35-39 / 28-30; + 0013: 8 / 34 / 21-23 / 7 / 11-14; + 0014: **5-7 / 19 / 17 / 3-5 / 11-12**. Performance governor or uclamp.min 40 on top-app: no further gain. What is left in the shade and Settings open/back is the apps' own frame cost (framestats, shade: input-to-completed median 17.7 ms, GPU 8.8 ms, RenderThread issue 4.5 ms + swap 3.7 ms even in good frames): hwui + freedreno at 1440p, not composition. Bench (scroll, 3 rounds): **janky 0.59 %, p50 9, p90 12, p99 20 ms** (45: 2.46 %). RRO `config_wallpaperMaxScale` 1.0 (no wallpaper zoom) from build 48. 0013 and 0014 apply unchanged to Nura's kernel (same 7.3.1 + Nura series; our other patches do not touch these files) |
| pstore finds (2026-11-16) | `ios/logs/los24-m1a-48-pstore-dmesg-ramoops-*.enc.z.txt` | Two older records collected in run 48: (1) 03:08, the SLIMbus NGD oops (fixed by 0012); (2) 10:27, kernel #19 (build 47), during the coordinator's tests: F2FS checkpoint blocked 12-13 s on sda12, vold SIGKILLed (reboot_on_failure), then expedited RCU stalls and "SMP: failed to stop secondary CPUs 2" while rebooting. CPU 2 stopped answering IPIs; not seen again so far. Open |
| Modem restart loop (2026-11-16) | `ios/logs/los24-m1a-46-dmesg.txt`, `-47-` | Seen once more on build 46's first boot (crashes at 76 s and 118 s), not on later boots of 46 and not in runs 47/48. The MSS coredump (devcoredump) is all zeros: the modem's memory is not readable from Linux, so no crash reason. Not fixed; next: QMI SSCTL/sysmon reason string, rmtfs/tqftp request log at the crash |
| Telephony without SIM (2026-11-16, builds 46-48) | - | Radio HAL crash-free in all runs. Status works: GSM network seen (-81 dBm, level 4), out of service, baseband version. SIM: CARD_IO_ERROR (QMI UIM "no ATR" in both slots). **Blocked:** SIM files and SMS need a SIM in the phone (to-test.md), mobile data needs IPA v2.5 in the kernel |
| Run 48 + soaks (2026-11-16) | `ios/logs/los24-m1a-48-*`, `ios/logs/los24-soak-b48-dpu1.txt`, `-b48-dpu2.txt`, `-b48-dpu2-dmesg.txt` | Build 48: kernel 0002-0014, RRO without wallpaper zoom. **Aperture crashed SurfaceFlinger** at the first preview frame (`Failed to create a valid texture [1280,960] format:34`): Mesa's fallback gralloc needs gralloc0's lock_ycbcr() for YUV/IMPLEMENTATION_DEFINED buffers -> **Mesa patch 0002** reads minigbm's handle; checked with the libraries bind-mounted and HW overlays off (camera SurfaceView composed by RenderEngine, SurfaceFlinger stays up, Aperture shows UI and preview). Soak 1 (30 min, ftrace ring armed): **clean**, 31 iterations, no reboot, no kernel warning (one Dialer NPE). Soak 2 (30 min, same boot 1h20 later): **not clean**: the display's SMMU (`mdp_smmu`, d00000) reported "TLB sync timed out -- SMMU may be deadlocked" 239 times from uptime 4888 s, then DPU frame done timeouts, UFS UIC command timeouts in ufshc devfreq (`dvfs failed -110`), f2fs_discard in D state and RCU stalls; system_server's watchdog killed it twice (WindowManager/display thread, then android.io blocked 68-69 s). No panic, no reboot. The same SMMU message is in this morning's stress2 records and the console log before run 48 (kernels without 0013/0014), and the 10:27 record (kernel #19) had the same I/O + RCU stall picture: an old hang, not from today's patches. So the DPU panic proof is **1 of 2 soaks**. Next: why the MDP SMMU's TLB sync stops completing (MDSS GDSC/AXI clock state at the sync, mmss NoC), with the soak's ftrace ring dumped by sysrq instead of a panic |
| Suspend + SIM pins (2026-11-19, kernels #24-#27, build 50) | `ios/logs/los24-k25-avc-distinct.txt` | **Kernel 0015** (NoC keep_alive) for the run 48 soak hang (soaks pending). **PSCI cpuidle** on (config): psci_idle, cores in standalone power collapse. **s2idle works**: a real cycle woken by the PMIC RTC alarm (pm_wakeup_irq = pm8xxx_rtc_alarm), resumes cleanly; RPM vlow/vmin stay 0 (no cluster/system idle state in the DT; msm8996's PSCI parameters for them are not public, not guessed). A pm_test=devices loop showed USB device mode does not survive a suspend with the gadget connected (re-enumeration fails for ~15 min) -> **kernel 0016**: qcom-smbchg holds a wakeup source while USB is present and wakes on plug-in; build 50 drops the axon7m-nosuspend wakelock (switch `persist.vendor.axon7m.nosuspend=1`). Build 50 on USB: charger wakeup source active, no suspend, adb stable. Current draw on battery: not measured yet (phone always on USB; needs a test without cable). **SIM "no ATR"**: the UIM data/clock/reset pins read GPIO output low; a TLMM hog muxing them to uim1/uim2 (experiment, kfast #27) is applied at boot, but after the modem's card power-up they are back to GPIO low: the modem owns and parks them itself. Not the cause; with no card the modem reports the same. A SIM in the phone (owner, to-test.md) decides. SELinux: 97 distinct denials on kernel #25 (list in the log file) |
| Release path: CI-equivalent test zip on the main phone (2026-11-19) | `ci/build-release.sh` (AXON7_RELEASE_ADB_KEYS), `ios/logs/los24-bench-testzip.txt`, `ios/logs/los24-anim-testzip.txt` | The release flavour (speaker on, firmware=phone, kernel built by kernel-build.sh all) with only the test adb key added, zip `lineage-24-DATE-UNOFFICIAL-axon7m-TESTKEYS-NOT-FOR-RELEASE.zip`, installed like a user: TWRP 3.3.0-0, `adb sideload` (nothing stored on the phone), reboot through the boot menu. Found and fixed: (1) the installer's boot-menu check could not see the LineageOS label in the gzip'd shim kernel and refused to install (nothing written); (2) libperfmgr.so missing from the image (own Soong namespace): power HAL could not link, system_server hung in StartPowerManager, first boot never completed; (3) the HAL's hint looper waits for vendor.powerhal.init (init sets it after boot now). With (1)+(2): install 395-404 s, first boot 325 s to the setup wizard, display/touch/sound card/GPU (freedreno FD530, Mesa 26.2.6)/firmware from the phone (modem vfat, vendor ext4, both ro)/3 remoteprocs/Wi-Fi scan (5 networks)/Bluetooth on, 0 crashes; bench 0.57 % janky p50 10 p90 13 p99 28 ms; anim (first boot, dexopt still running, no boosts yet) ripple 8 %, ripple+open/back 17 %, drawer 7 %, app open 15 %, shade 15 %; reboot back to LineageOS in 81 s. Setup wizard language list (owner: laggy): composition stays DEVICE (2 planes, no failed checks); the CPUs idled at 307 MHz between touches because the old example power HAL ignored INTERACTION: with the libperfmgr boost p50 10 / p90 13-14 ms (was 11-16 / 18-20); the 99th percentile (150 ms) is the first bind of rows in new scripts (font fallback). Final test zip (all three fixes, 2026-11-20): installer clean (RC=0), first boot 231 s to the setup wizard, vendor.powerhal.init set by init, all checks as above, 0 crashes; language list with boosts (load average still 4-5 after first boot): janky 4.4-6.8 %, p50 10-11 ms, p90 15-18 ms. Silence for tests: all streams 0, ringer silent, DND, no touch/lock/charging sounds or haptics (release flavour has the speaker on). CI: los24-build.sh takes /srv/aosp/build.lock (shared with the LineageOS 22.2 builds; the 31 GB container cannot run two Android builds) |
| Stability soaks (2026-11-20, test-key release zip = kernels 0002-0016 incl. 0015 NoC keep_alive, PSCI cpuidle) | `ios/logs/los24-soak-testzip-dpu1.txt`, `-dpu2b.txt`, `-dpu2-console-ramoops-0.txt` | **Two clean 30-min soaks on one full build** (ftrace ring armed): 24 and 25 iterations, no reboot, no system_server restart, no kernel warning, none of the run 48 hang signatures (MDP SMMU TLB sync, UFS UIC timeouts, RCU stalls) and no SError; 1-2 recovered DPU kickoff timeouts per soak (seen since build 39). App crashes only from the setup wizard disabled for the test. An earlier soak-2 run ended in a clean power-off: `/data/system/shutdown-checkpoints` shows a user request through SystemUI's power menu (StatusBarManagerService.shutdown, reason userrequested) while the status bar could not be expanded by the soak's monkey: not a fault, not counted. Separately: a LineageOS "factory reset" request (reboot,factory_reset, trigger unknown) went through TWRP; the iOS userdata partition (TWRP's /data) still holds its HFSX volume, but a user's "Erase all data" in LOS 24 sends TWRP --wipe_data, which targets userdata = iOS in this layout (to handle: make LOS 24's factory reset wipe only los_data/los_metadata) |
| Reference trees | `/srv/los24/ref` (dragonboard, AOSPM qrild/libqril/tinyhal/vibrator-ff/lights/device_generic_sdm845) | cloned |

Check from the PC: `ssh root@compiler 'su - build -c "tmux ls"; tail -3 /srv/los24/logs/build-after.log /srv/los24/logs/build-latest.log'`.
`build-latest.log` points at the queued rebuild once it starts.

Next steps (2026-11-16, after the driver round of builds 42-45):
- Camera preview: AOSP's `external/libcamera` is ChromeOS' fork without
  the software ISP, so the simple pipeline on CAMSS only delivers raw
  Bayer. Port upstream libcamera's `software_isp` (debayer, statistics, the
  simple IPA) into that tree's Android.bp, or build upstream libcamera with
  meson against the NDK as Mesa is built; then replace the torch-only
  `camera.axon7m` by libcamera's HAL with torch support kept. Front OV8856
  first (RAW10 3280x2464 works on Nura).
- Radio step 2 (RIL-PLAN.md): SIM file access over QMI UIM (needs a SIM in
  the phone: both slots report "no ATR"), then SMS (WMS). Voice needs
  q6voice, data needs IPA v2.5 (kernel).
- Modem restarts every 40 s for up to ~9 min after some boots (runs 38-44,
  not in 36/37/39/43/45): find what the modem waits for (TFTP server,
  remote file paths, rmtfs read-only).
- Bluetooth: HCI reset timeout after the QCA rampatch download in some
  boots wedges the default HAL (run 45 row); retry or a timeout in the HAL.
- USB tethering: RNDIS/NCM functions are configured; a test needs a host
  whose network may change (not the developer PC).
- Owner checks: hall sensor with a magnet (screen off/on), GNSS fix outdoors,
  notification LED with a real notification while the screen is off.

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
