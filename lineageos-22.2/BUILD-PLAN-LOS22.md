# Plan: LineageOS 22.2 (Android 15) for the ZTE Axon 7

Status 2026-11-05: **no LineageOS 19.1+ build or source exists for axon7.** The newest is
18.1 (Android 11) by blueyfish/rcky844. LineageOS 22.2 means a real port, not just a rebuild.

## Why it's a port and not a rebuild
- Official LineageOS axon7 stops at `lineage-15.1` (device and kernel repos). The proprietary repo (`LineageOS/proprietary_vendor_zte`) doesn't exist; TheMuppets only has cm-14.1/lineage-15.1.
- blueyfish has `lineage-16.0` through `lineage-18.1` branches for device, kernel and vendor:
  - https://github.com/blueyfish/android_device_zte_axon7 (branches: lineage-16.0, 17.1, 18.0, 18.1)
  - https://github.com/blueyfish/android_kernel_zte_msm8996 (to lineage-18.1, **kernel 3.18.140**)
  - https://github.com/blueyfish/proprietary_vendor_zte (to lineage-18.1, `vendor/zte/axon7`)
- **The key fact:** gemini (Mi 5) and the LG G5/V20/G6 did *not* get Android 12 to 15 on 3.18. In lineage-19.1 LineageOS moved `android_kernel_xiaomi_msm8996` and `android_kernel_lge_msm8996` from 3.18 to **4.4.302**: a CAF msm-4.4 / `lineage-18.1-caf-msm8998` base merged with android-4.4-p, about 147k commits apart. The LineageOS wiki now lists gemini's kernel as 4.4. Even blueyfish's own OPPO msm8937 ports moved from 3.18 to 4.9 for lineage-21/22. Android 12+ netd/BPF, pidfd, cgroup and ext4 project-quota needs are met by the 4.4 trees plus LineageOS backports (BPF cgroup sock attach, pidfd_open/CLONE_PIDFD, ext4 project quota, LLVM/clang kbuild, CFI-type fixes, and others).
- So the axon7 needs: **(A) a 4.4 kernel port**, **(B) a device tree forward-port 18.1 → 22.2**, **(C) the blob/shim updates** gemini needed.

## A. Kernel (the largest job)
Base: `LineageOS/android_kernel_xiaomi_msm8996` @ `lineage-22.2` (4.4.302). It already has all the Android 15 backports. The alternative is `LineageOS/android_kernel_lge_msm8996` @ `lineage-22.2`.
Port from the 3.18 axon7 kernel (`blueyfish/android_kernel_zte_msm8996` lineage-18.1):
- DTS: `zte-msm8996-v3-pmi8996-ailsa_ii.dts/.dtsi`, `dsi-panel-zte-samsung-s6e3ha3-5p5-wqhd-dualmipi-cmd.dtsi` (Samsung AMOLED, dual-DSI command mode), `zte-camera-sensor-mtp.dtsi`, `zte-usb-type-c.dtsi`, `touch-key-backlight-ailsa_ii.dtsi`, `zte_p996a01_3250mah.dtsi` (battery profile). Place them under `arch/arm64/boot/dts/qcom/` in the 4.4 layout and add a `vendor/zte/axon7.config` defconfig fragment, the way gemini uses `vendor/xiaomi/gemini.config`.
- Drivers: `drivers/input/touchscreen/synaptics_dsx_zte/` + `gen_vkeys_zte.c`; `drivers/input/fingerprint/goodix` (GF3118M); audio `sound/soc/codecs/ak4961*` (AKM AK4961 codec alongside WCD9335) + `sound/soc/codecs/ak4490/` (AK4490 DAC, AK8157, ISL98608) and the ZTE changes in the msm8996 machine driver; camera `camera_v2/sensor/zte_io/` + `eeprom/zte_eeprom.c` (OIS/actuator utilities); `drivers/power/zte-hall.c`, `zte_misc.c`, the ZTE qpnp-smbcharger/qpnp-fg/qpnp-power-on changes (C457's "Import ZTE A2017G Oreo release changes" commits); NFC PN5xx (4.4 has NQ-NCI); hall sensor AH1898.
- Wi-Fi is QCA6174 via qcacld (CNSS PCI). Bluetooth is the same as gemini. Both are already in the 4.4 tree.
- Hardest parts: the AK4961/AK4490 audio path, the camera sensor/OIS drivers, and the panel. Gemini is LCD; the axon7 AMOLED dual-DSI cmd panel needs proper ESD/backlight handling in the 4.4 mdss.

## B. Device tree 18.1 → 22.2
Use `LineageOS/android_device_xiaomi_msm8996-common` (lineage-19.1 → 22.2 history) as the step-by-step recipe:
- Kernel: `TARGET_KERNEL_SOURCE := kernel/zte/msm8996`, `TARGET_KERNEL_CONFIG := vendor/zte/axon7_defconfig` (or `msm8996_defconfig vendor/zte/axon7.config`), plus `androidboot.boot_devices=soc/624000.ufshc` in the cmdline.
- `include device/qcom/sepolicy-legacy-um/SEPolicy.mk` (branch lineage-22.2-legacy-um), and move to `BOARD_VENDOR_SEPOLICY_DIRS`.
- Raise the VINTF target level to 4+, add `updatable_apex.mk`, `non_ab_device.mk`, and "Ship full recovery image".
- HALs: AIDL Wi-Fi vendor HAL or "legacy WiFi HIDL HAL" as gemini does; QTI health AIDL + Lineage Health; `android.frameworks.sensorservice@1.0.vendor`; `android.hardware.bluetooth@1.0`; `ENABLE_VENDOR_RIL_SERVICE := true`; QCamera2 in tree with gemini's HAL3 fixes.
- Old-blob compatibility shims: `libhidlbase-v32(.vendor)`, `libutils-v33`, `libprotobuf-cpp-{full,lite}-vendorcompat`, `libstdc++.vendor`, `BUILD_BROKEN_ELF_PREBUILT_PRODUCT_COPY_FILES := true`.
- releasetools: keep the `axon7.verify_trustzone` recovery-updater (`TARGET_RECOVERY_UPDATER_LIBS`) and `TZ.BF.4.0.1-00353`, or switch to gemini's `android-info-extra.txt` style.
- Partitions: system 5,905,580,032 B and vendor 536,870,912 B (ext4, already on the phone). Gemini's vendor is 832 MiB, so check that the 22.2 vendor image fits in 512 MiB. If not, `BOARD_VENDORIMAGE` can be dropped and vendor kept in /system like LG msm8996 22.2 does (that config has no vendor partition).
- Overlays: rework for 22.2 (status_bar_padding, rounded corners, etc.). Rebuild FlipFlap (lineage-22.2 exists).

## C. Blobs
Start from `blueyfish/proprietary_vendor_zte` lineage-18.1 (A2017G Oreo blobs). Re-run `extract-files.py` (22.2 uses the Python extract-utils) with the 22.2 `proprietary-files.txt` and add `blob_fixup` entries like gemini's (libhidlbase-v32 replacement, `libutils` → `libutils-v33`, protobuf vendorcompat, etc.). Source for extraction: the phone's Oreo B10/B12 firmware or the 18.1 vendor image.

## Effort estimate
Experienced porter, part-time:
- 4.4 kernel bring-up to boot plus display: 2 to 4 weeks.
- Touch, fingerprint, charging, sensors, Wi-Fi, BT and RIL: 1 to 3 weeks.
- Audio (AK4961/AK4490) and camera: 2 to 6 weeks; these are the main risk.
- Userspace/device tree/sepolicy for 22.2: 1 to 3 weeks in parallel.

**Total: about 1.5 to 4 months for a daily-driver-quality build.** One option is to step through lineage-19.1/20 first on the same 4.4 kernel; blueyfish's history suggests he may do this himself. Watch https://sourceforge.net/projects/tipzbuilds/files/ROMs/ZTE%20Axon%207/ and https://github.com/blueyfish?tab=repositories.

---

## Build server (LXC, i7-6700 4c/8t, 31 GB RAM, 400 GB ZFS mirror on HDD)

### Container
- **Ubuntu 22.04 LTS** template. LineageOS's package list targets it, and `libncurses5`/`lib32ncurses5-dev` still exist there; 24.04 and Debian 12 dropped them, so you'd have to side-load them.
- Unprivileged is fine. Set `features: nesting=1,keyctl=1`. Nesting lets soong_ui's nsjail sandbox create namespaces; if nsjail still fails, soong prints a warning and builds unsandboxed. No `/dev/fuse`, loop devices, overlayfs or privileged mode are needed: non-A/B ext4 images are built in userspace with mke2fs/e2fsdroid, and the kernel is built inline.
- `cores: 8`, `memory: 31744`, `swap: 32768` (the Proxmox container swap allowance). The allowance only helps if the **host** actually has swap or zram; LXC has no swap of its own.
- Raise the file limit in the container (`ulimit -n 65536`, or `lxc.prlimit.nofile: 65536`).
- Unprivileged + host bind mount: container uid 1000 is host uid 101000, so `chown -R 101000:101000 /tank/aosp /tank/aosp-ccache` on the host. Otherwise use Proxmox-managed mount points (`pct set <CTID> -mp0 <zfs-storage>:300,mp=/srv/aosp`), which are created with the right ownership, and set the ZFS properties below on the resulting `.../subvol-<CTID>-disk-N` dataset.
- Example host config, in `/etc/pve/lxc/<CTID>.conf` or via `pct set`:
  ```
  arch: amd64
  cores: 8
  memory: 31744
  swap: 32768
  features: nesting=1,keyctl=1
  unprivileged: 1
  mp0: /tank/aosp,mp=/srv/aosp
  mp1: /tank/aosp-ccache,mp=/srv/ccache
  lxc.prlimit.nofile: 65536
  ```

### Memory, swap and zram
LineageOS recommends 64 GB RAM for lineage-21+. With 31 GB, give the container **about 32 GB of swap allowance** and back it on the host with **zram** (`zram-tools`/`systemd-zram-generator`, zstd, 16 to 24 GB). An optional swap file/partition can sit on a **non-ZFS** device. **Never put swap on a ZFS zvol**, because it can deadlock under memory pressure. Peaks come from kati/soong analysis (about 20 to 25 GB), metalava/doclava, R8 and lld links.
Host zram example (Debian/Proxmox host, as root): `apt install systemd-zram-generator`, then `/etc/systemd/zram-generator.conf` = `[zram0]` / `zram-size = 24576` / `compression-algorithm = zstd` / `swap-priority = 100`, then `systemctl daemon-reload && systemctl start systemd-zram-setup@zram0`. zstd zram typically holds 2.5 to 3.5x, so 24 GB of zram costs about 7 to 9 GB of real RAM only when it's in use.
**Cap the host's ZFS ARC** (for example `options zfs zfs_arc_max=6442450944` = 6 GiB, if the host's RAM is tight) so the ARC and the container don't fight.

### ZFS datasets (run on the host as root)
```sh
zfs create -o compression=lz4 -o atime=off -o xattr=sa -o dnodesize=auto \
           -o recordsize=128K -o logbias=throughput -o sync=disabled tank/aosp
zfs create -o compression=off  -o atime=off -o recordsize=128K tank/aosp-ccache
# bind-mount into the container, e.g. mp0: /tank/aosp,mp=/srv/aosp ; mp1: /tank/aosp-ccache,mp=/srv/ccache
```
- lz4 on source + out typically saves about 30 to 45%. Keep the default 128K recordsize (lots of small files; larger records don't help here).
- `sync=disabled` **is sensible for this dataset only**: it is a rebuildable cache, and a host crash loses at most a few seconds of writes (worst case `repo sync --force-sync` / `m clean`). It speeds up git/ninja fsync-heavy work on HDDs a lot. Don't set it on datasets holding anything you can't regenerate, such as your own git repos with the port work. Keep those on a normal dataset and push often.
- ccache already compresses (zstd), so its dataset uses compression=off.
- A mirror of HDDs is seek-bound. An SSD as a `special` vdev or L2ARC would help the most. Without one, expect the times below.

### Pre-flight checklist (inside the container)
```sh
nproc                                  # expect 8
free -g                                # Mem ~31, Swap >= 24 (if Swap shows 0, the host has no swap/zram)
df -h /srv/aosp /srv/ccache            # >= 300 GB free for aosp, 30-40 GB for ccache
zfs get compression,atime,sync,recordsize,xattr tank/aosp   # on the host
ulimit -n                              # >= 65536
cat /proc/sys/kernel/unprivileged_userns_clone 2>/dev/null; unshare -Ur true && echo userns-ok   # nsjail sandbox
git lfs version && repo version && python3 --version
```

### Packages (in the container)
```sh
sudo apt update && sudo apt install -y bc bison build-essential ccache curl flex g++-multilib gcc-multilib \
  git git-lfs gnupg gperf imagemagick lib32readline-dev lib32z1-dev libelf-dev liblz4-tool \
  lib32ncurses5-dev libncurses5 libncurses5-dev libsdl1.2-dev libssl-dev libxml2 libxml2-utils \
  lzop pngcrush rsync schedtool squashfs-tools xsltproc zip zlib1g-dev python3 python-is-python3 unzip
mkdir -p ~/bin && curl -o ~/bin/repo https://storage.googleapis.com/git-repo-downloads/repo && chmod a+x ~/bin/repo
git lfs install
git config --global user.name "you"; git config --global user.email "you@example.com"
```

### Sync (disk-saving)
```sh
cd /srv/aosp && mkdir lineage-22.2 && cd lineage-22.2
repo init -u https://github.com/LineageOS/android.git -b lineage-22.2 --git-lfs --no-clone-bundle --depth=1
mkdir -p .repo/local_manifests && cp /path/to/axon7.xml .repo/local_manifests/
repo sync -c -j6 --no-tags --no-clone-bundle --optimized-fetch --prune
```
(`axon7.xml` is in `lineageos-22.2/build/local_manifests/axon7.xml`. It sets `clone-depth="0"` on the device and kernel repos so you get their full history for porting.)
Clone the reference trees **outside** `lineage-22.2/`: gemini, msm8996-common, lge msm8996-common, and the 3.18 axon7 kernel.

### Disk budget (approx., with --depth=1 and lz4)
Source checkout plus .repo: 110 to 140 GB raw, about 80 to 100 GB on disk. `out/` for one device: 120 to 160 GB raw, about 80 to 110 GB on disk. ccache: 30 GB. Reference repos and kernel history: 10 GB. **Total about 200 to 250 GB**, which fits in 400 GB with headroom. Run `m installclean` between builds.

### Build
```sh
export USE_CCACHE=1 CCACHE_EXEC=/usr/bin/ccache CCACHE_DIR=/srv/ccache
ccache -M 30G ; ccache -o compression=true
source build/envsetup.sh
breakfast axon7          # after the device tree is ported (lineage_axon7.mk, AndroidProducts.mk)
m -j6 bacon              # start with -j6; go to -j8 once a build has passed without OOM; use -j4 if OOM kills hit
```
Optional time/RAM saver: `export WITHOUT_CHECK_API=true` (skips the metalava API checks). If the OOM killer hits during soong/kati analysis, -j doesn't help (analysis is mostly single-process). The fix there is more swap/zram.

### Time estimates (i7-6700, HDD mirror)
- `repo sync` (about 60 to 80 GB download): 2 to 4 h at 100 Mbit/s.
- First full `m bacon`: **about 8 to 12 h**. The soong/kati analysis phase alone takes 30 to 60 min, and the HDD seeks plus the 4 physical cores dominate.
- Incremental rebuilds with warm ccache after small device/kernel changes: 30 to 90 min. Kernel-only (`m bootimage`): 10 to 20 min.

Expect many iterations during the port. The kernel can be built standalone (outside the Android tree, with LineageOS's prebuilt clang) for much faster cycles.
