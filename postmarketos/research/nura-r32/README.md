# Nura r32 (2026-11-26): package sync evidence

The r32 packages bring the Nura kernel and device package in line with the
work that went into LineageOS 24 build 58 / kernel #1. No sleep draft patches
(kernel 0080-0083 on agent/sleep) are present in either package.

## Local package build: blocked before abuild

`/usr/bin/pmbootstrap` on this PC is 3.10.3 and refuses the tree with
"version 3.11.0 is required", so the build was run from a local clone of
pmbootstrap 3.12.1. `pmbootstrap config jobs 4` was set. Both attempts stopped
before any package was compiled; logs are in `nurasync-build/linux-build.log`
and `nurasync-build/linux-build-lax.log`:

```
$ python3 .../pmbootstrap/pmbootstrap.py build --arch aarch64 --force \
      linux-zte-axon7 device-zte-axon7
ERROR: Command failed (exit code 1): % sudo losetup --json --list

$ python3 .../pmbootstrap/pmbootstrap.py --lax build --arch aarch64 --force \
      linux-zte-axon7 device-zte-axon7
Update package index for aarch64 (4 file(s))
ERROR: Command failed (exit code 1): % sudo cp .../APKINDEX_... \
      /home/devilapi/.local/var/pmbootstrap/cache_apk_aarch64/APKINDEX...tar.gz
```

`/home/devilapi/.local/var/pmbootstrap/log.txt` gives the reason for both:

```
sudo: a terminal is required to read the password; either use the -S option
      to read from standard input or configure an askpass helper
sudo: a password is required
```

No noninteractive PC root authorization was available, so there is no built
`linux-zte-axon7-7.3.1-r32` or `device-zte-axon7-1-r27` package yet. No phone
was connected or touched.

## Kernel base: 7.3.1-axon7m aae3898ef

`linux-zte-axon7` keeps the pmbootstrap layout (kernel.org `linux-7.3.1.tar.xz`
plus the numbered patches in the package directory). The LOS kernel #1 is
built from the same source: `scripts/kernel-build.sh setup` applies the Nura
patches from this package to v7.3.1, and the kernel tree
`~/axon7-kbuild/losfast/linux` is at `aae3898efa01da06a3fe6443b63d7bff59c87498`
(`iio: accel: smgr_accel: correct scale to match SLPI factory calibration`).

Check run on 2026-11-26 (subjects folded the way `git am` records them):

```
patches: 63, commits v7.3.1..aae3898ef: 63, exact subject match: True
aae3898ef
```

So the r32 patch list 0001-0063 is exactly the Nura series in the LOS kernel
base; 0063 is the accelerometer scale fix. The LOS kernel build log
(`loskernel/logs/loskernel-2026-11-23/kfast-build.log`) records the staged
kernel as `7.3.1-axon7m aae3898ef +patches 0002 ... 0022`, i.e. the same Nura
base plus the Android-only patches and config fragment.

## Patch identity: the LOS scaler/DDR patches are already in the series

The resume note asked to add LineageOS 24 kernel 0013 (DPU QSEED2 scaler)
and 0014 (GPU DDR bandwidth per OPP) as new Nura patches. They are already
in the series as 0052/0053, taken over in r27 (commit 82a7953,
2026-11-19); `git patch-id --stable` gives the same id for the Nura file
and the LOS file:

| LOS 24 | Nura r32 | patch-id |
| --- | --- | --- |
| `0013-drm-msm-dpu-qseed2-scaler-for-vig-pipes.patch` | `0052-drm-msm-dpu-QSEED2-scaler-for-VIG-pipes.patch` | `a4d9d5064b5e767da03f9483aaa3ab9206a1b592` |
| `0014-arm64-dts-qcom-msm8996-gpu-ddr-bandwidth-per-opp.patch` | `0053-arm64-dts-qcom-msm8996-DDR-bandwidth-for-the-GPU-OPP.patch` | `b1165a05b038421aa3867e64f07758543451c76d` |

So no 0064/0065 were added: they would not apply on top of 0052/0053. The
APKBUILD header now maps 0052/0053 to LOS 0013/0014.

## Apply test 0001-0063 (2026-11-26)

Clean `v7.3.1` worktree (`79a907609`) from `~/axon7-kbuild/linux`; all 63
patch files applied in order with `git am` (63/63, no rejects). The result
has the same tree as the LOS kernel base `aae3898ef`:

```
HEAD tree: cf97ccf6e99fc1cb170d1e21b57f2055b8f2cb15
base tree: cf97ccf6e99fc1cb170d1e21b57f2055b8f2cb15
git diff --quiet aae3898ef HEAD -> 0
```

In addition, every patch's `git patch-id` equals the corresponding commit's
in `v7.3.1..aae3898ef` (63/63, 0 mismatches).

## Stale config checksum fixed

Commit 182a21d added `CONFIG_QCOM_IPA2_LITE=m` to
`config-zte-axon7.aarch64` without updating the APKBUILD `sha512sums`, so
`abuild` would have rejected the package with a checksum error. The entry
now matches the file (`51b50838...`; `sha512sum -c` OK for every locally
present file, the kernel.org tarball is not kept in the repo).

## Local kernel Image + dtbs build (2026-11-26)

`make -j4 Image dtbs`, `ARCH=arm64 LLVM=1` with clang r536225, the applied
tree and the repo `config-zte-axon7.aarch64` as input
(`CONFIG_DEBUG_INFO_BTF=y`, pahole 1.25), inside
`systemd-run --user --scope --slice=ios3ds.slice`: **build-exit 0,
2026-11-26T15:41:32+01:00 -> 15:51:44+01:00 (10 min 12 s), 0 compiler
warnings, 0 errors**. `olddefconfig` only rewrote compiler/pahole
capability symbols (local clang 19 and pahole 1.25 against the file's
clang 23 and pahole 1.32) and the feature defaults that follow from them
(e.g. `ARM64_BTI_KERNEL`); no device-driver option changed, and the repo
config file was not edited.

```
arch/arm64/boot/Image                              31,605,248 B  sha256 ca684e56...
arch/arm64/boot/dts/qcom/msm8996-zte-axon7.dtb          86,296 B  sha256 6156a23e...
```

Artifacts, the config used and the full log are on the HDD in
`nurasync-build/artifacts-20261126/`. Host extras (pahole 1.25, libelf
headers) came from user-space Ubuntu `.deb` extractions because the PC has
no root; the repo config was not changed for the build.

## Kernel config

The Nura config is deliberately not the Android config (no SELinux, no EROFS
as built-in, etc.). What has to match is the device-driver configuration that
both kernels use, and the LOS config check after merging the Nura config with
`kernel/android-axon7m.config`:

```
$ bash scripts/kernel-config-check.sh ~/axon7-kbuild/losfast/prebuilt/config \
      lineageos-24-mainline/kernel/android-axon7m.config
config check: 0 option(s) differ from android-axon7m.config

$ grep -E '^CONFIG_(ATH10K_PCI|IIO_QCOM_SMGR_ACCEL|QCOM_IPA2_LITE|DRM_PANEL_SAMSUNG_S6E3HA3)=' \
      postmarketos/pmaports-local/device/testing/linux-zte-axon7/config-zte-axon7.aarch64
CONFIG_QCOM_IPA2_LITE=m
CONFIG_ATH10K_PCI=m
CONFIG_DRM_PANEL_SAMSUNG_S6E3HA3=m
CONFIG_IIO_QCOM_SMGR_ACCEL=m
```

No config change was needed for r32. The config check is a report (exit 0),
so the number has to be read, not just the exit status.

## Wi-Fi firmware and late PCIe rescan

- Nura has read Wi-Fi board data from the phone's own partitions since the
  first release: `axon7-firmware` mounts `modem` read-only and copies
  `image/bdwlan30.bin` to
  `/usr/lib/firmware/postmarketos/ath10k/QCA6174/hw3.0/board.bin`.
- wifi24 found that a PCIe rescan can find the QCA6174 after ueventd skipped
  `ath10k_pci` (its firmware is only available once the modem partition is
  mounted). `axon7-wifi-rescan` now loads the module after a successful
  rescan and checks the sysfs symlink with `-L`. Nura has no SELinux policy
  for this path, but the symlink check avoids following the device directory
  and matches the LOS helper.
- The firmware side of wifi24 (`/mnt/vendor/firmware_mnt` root-owned mount,
  fstab and sepolicy) is Android-specific and does not apply to Nura.

## Accelerometer

Patch 0063 (`9.81 / 690310`) was measured at 9.84 m/s² lying flat in
LineageOS 24 build 58 on kernel #1 (`XDA-POST-LINEAGEOS-24.md`, 2026-11-26).
Earlier module-swap evidence is in `research/accel-sensors/RESULTS-2026-11-22.md`.
A Nura-side reading still needs a person at the phone; the steps are in
`to-test.md` and in the final NEEDS HUMAN section.
