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
# and the shim's own android.c built for the host (host_android_test.c,
# with the lineageos-24-mainline/shim patch applied to a temporary copy)
# against a stand-in LK DTB (memory + ids + LK-style bootargs).
#
# Usage (PC, from the repository root or worktree; needs mkbootimg, dtc, cc, gzip):
#   lineageos-24-mainline/scripts/make-m0-testimg.sh [OUTDIR]     (default /tmp/axon7m-m0)
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
(cd "$O/initramfs" && "$TI/gen_init_cpio" "$TI/list.txt" | gzip -9 > initramfs-test-hb.cpio.gz)
INITRD=$O/initramfs/initramfs-test-hb.cpio.gz

# Command line: the shim puts the DTB's bootargs first, then this, then LK's
# tokens. No androidboot.*: there is no Android here.
CMDLINE="console=ttyMSM0,115200 console=tty0 clk_ignore_unused pd_ignore_unused msm.prefer_mdp5=0 panic=10 loglevel=7"
mkbootimg --header_version 2 --kernel "$O/Image" --ramdisk "$INITRD" --dtb "$O/msm8996-zte-axon7.dtb" \
	--base 0x80000000 --kernel_offset 0x00008000 --ramdisk_offset 0x01000000 \
	--tags_offset 0x00000100 --dtb_offset 0x01f00000 --pagesize 4096 \
	--os_version 17.0.0 --os_patch_level 2026-10 --cmdline "$CMDLINE" -o "$O/m0-test-boot.img"
python3 -I "$S/ios/tools/axon7-androidimg.py" check "$O/m0-test-boot.img"

# Shim host test: android.c exactly as the phone runs it (+ our patch)
W=$O/shim-test
rm -rf "$W"; mkdir -p "$W"
cp "$S"/ios/shim/*.[ch] "$W/"
(cd "$W" && sed -n '/^--- a\/shim/,$p' "$R/lineageos-24-mainline/shim/0001-boot-menu-fourth-entry-l24_boot.patch" |
	sed 's#^\(---\|+++\) [ab]/shim/#\1 #' | patch -s -p0)
cc -O1 -Wall -Wextra -Werror -DANDROID_HOST_TEST -I"$W" "$W/host_android_test.c" "$W/android.c" "$W/fdtw.c" -o "$W/ta"
cat > "$W/lk.dts" <<'EOF'
/dts-v1/;
/ {
	#address-cells = <2>;
	#size-cells = <2>;
	model = "stand-in for the DTB ZTE LK patched for the shim";
	qcom,msm-id = <246 0x30001>;
	qcom,board-id = <100 0>;
	memory { device_type = "memory"; reg = <0 0x80000000 0 0x80000000 0x1 0x0 0 0x7e4c0000>; };
	chosen { bootargs = "console=ttyHSL0", "androidboot.serialno=0123abcd androidboot.baseband=msm skip_initramfs rootwait ro init=/init kpti=1"; };
};
EOF
dtc -q -I dts -O dtb -o "$W/lk.dtb" "$W/lk.dts"
"$W/ta" "$O/m0-test-boot.img" "$W/lk.dtb" "$W/out.dtb"
dtc -q -I dtb -O dts "$W/out.dtb" 2>/dev/null | grep -E "bootargs|linux,initrd|reg = <0x00 0x80000000" | head -5
echo "kernel: $(cat "$O/version")"
ls -l "$O/m0-test-boot.img"
sha256sum "$O/m0-test-boot.img"
