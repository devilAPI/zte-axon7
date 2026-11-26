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
