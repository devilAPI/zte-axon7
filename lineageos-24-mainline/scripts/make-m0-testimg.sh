#!/bin/bash
# Milestone M0a': boot-path test image without any Android build.
#
# The Android-config mainline kernel (scripts/kernel-build.sh, staged in
# /srv/los24/kernel/prebuilt) plus Nura's bring-up initramfs
# (postmarketos/test-initramfs/initramfs-test.cpio.gz: busybox, USB NCM
# 172.16.42.1 + telnet, never mounts UFS/SD) as a boot image header v2 with a
# raw Image and the DTB in the dtb section: what the shim's LineageOS entry
# boots from los_boot (ios/shim/android.c).
#
# Then checks the image offline twice: ios/tools/axon7-androidimg.py check,
# and the shim's own android.c built for the host (host_android_test.c in a
# temporary copy, expected entry from the Image's text_offset)
# against a stand-in LK DTB (memory + ids + LK-style bootargs).
#
# Usage (PC, from the repository root or worktree; needs mkbootimg, dtc, cc, gzip):
#   [PAD_MB=N] lineageos-24-mainline/scripts/make-m0-testimg.sh [OUTDIR]     (default /tmp/axon7m-m0)
# Fetches Image and DTB from the build server (AXON7_BUILD_HOST, root@compiler).
set -euo pipefail
R=$(git rev-parse --show-toplevel)
# ios/ (submodule) and the test initramfs (not in git) come from a full
# checkout; in a bare worktree point AXON7_SRC at the main checkout (read only).
S=${AXON7_SRC:-$R}
O=${1:-/tmp/axon7m-m0}
H=${AXON7_BUILD_HOST:-root@compiler}
mkdir -p "$O"
scp -q "$H:/srv/los24/kernel/prebuilt/Image" "$H:/srv/los24/kernel/prebuilt/dtb/msm8996-zte-axon7.dtb" \
	"$H:/srv/los24/kernel/prebuilt/version" "$O/"
# Initramfs: Nura's test initramfs (sources in postmarketos/test-initramfs,
# busybox not in git), plus a heartbeat: the watchdog state once, then the
# uptime in the kernel log every 5 s, so a reset shows up in pstore with its
# time. Nura's own files stay as they are.
TI=$S/postmarketos/test-initramfs
[ -x "$TI/gen_init_cpio" ] && [ -r "$TI/root/bin/busybox" ] || { echo "missing $TI (busybox, gen_init_cpio)" >&2; exit 1; }
rm -rf "$O/initramfs"; mkdir -p "$O/initramfs"
cp -a "$TI/root" "$O/initramfs/root"
python3 -I - "$O/initramfs/root/init" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
hb = """# axon7m heartbeat (lineageos-24-mainline/scripts/make-m0-testimg.sh)
( for w in /sys/class/watchdog/watchdog*; do
	[ -d "$w" ] && log "watchdog $w: $(cat $w/identity 2>/dev/null) state=$(cat $w/state 2>/dev/null) timeout=$(cat $w/timeout 2>/dev/null)"
  done
  [ -e /sys/class/watchdog/watchdog0 ] || log "no watchdog device"
  while true; do
	echo "axon7-test: alive $(cut -d' ' -f1 /proc/uptime)" > /dev/kmsg
	sleep 5
  done ) &

"""
anchor = "# Keep PID 1 alive"
assert anchor in s
open(p, "w").write(s.replace(anchor, hb + anchor, 1))
PYEOF
# PAD_MB=N: add N MiB of incompressible data (/pad.bin) to the initramfs, to
# test the shim with an image as large as a LineageOS recovery image
cp "$TI/list.txt" "$O/initramfs/list.txt"
if [ "${PAD_MB:-0}" -gt 0 ]; then
	head -c $((PAD_MB * 1048576)) /dev/urandom > "$O/initramfs/pad.bin"
	echo "file /pad.bin pad.bin 0644 0 0" >> "$O/initramfs/list.txt"
fi
(cd "$O/initramfs" && "$TI/gen_init_cpio" list.txt | gzip -9 > initramfs-test-hb.cpio.gz)
INITRD=$O/initramfs/initramfs-test-hb.cpio.gz

# Command line: the shim puts the DTB's bootargs first, then this, then LK's
# tokens. No androidboot.*: there is no Android here.
CMDLINE="console=ttyMSM0,115200 console=tty0 clk_ignore_unused pd_ignore_unused msm.prefer_mdp5=0 panic=10 loglevel=7"
mkbootimg --header_version 2 --kernel "$O/Image" --ramdisk "$INITRD" --dtb "$O/msm8996-zte-axon7.dtb" \
	--base 0x80000000 --kernel_offset 0x00008000 --ramdisk_offset 0x01000000 \
	--tags_offset 0x00000100 --dtb_offset 0x01f00000 --pagesize 4096 \
	--os_version 17.0.0 --os_patch_level 2026-10 --cmdline "$CMDLINE" -o "$O/m0-test-boot.img"
python3 -I "$S/ios/tools/axon7-androidimg.py" check "$O/m0-test-boot.img"

# Shim host test: android.c exactly as the phone runs it
AXON7_SRC=$S "$R/lineageos-24-mainline/scripts/shim-hostcheck.sh" "$O/m0-test-boot.img" "$O/shim-test"
echo "kernel: $(cat "$O/version")"
ls -l "$O/m0-test-boot.img"
sha256sum "$O/m0-test-boot.img"
