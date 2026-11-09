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
# Usage (PC, from the repository root or worktree; needs mkbootimg, dtc, cc):
#   lineageos-24-mainline/scripts/make-m0-testimg.sh [OUTDIR]     (default /tmp/axon7m-m0)
# Fetches Image and DTB from the build server (AXON7_BUILD_HOST, root@compiler).
set -euo pipefail
R=$(git rev-parse --show-toplevel)
O=${1:-/tmp/axon7m-m0}
H=${AXON7_BUILD_HOST:-root@compiler}
mkdir -p "$O"
scp -q "$H:/srv/los24/kernel/prebuilt/Image" "$H:/srv/los24/kernel/prebuilt/dtb/msm8996-zte-axon7.dtb" \
	"$H:/srv/los24/kernel/prebuilt/version" "$O/"
INITRD=$R/postmarketos/test-initramfs/initramfs-test.cpio.gz
[ -r "$INITRD" ] || { echo "missing $INITRD (built by postmarketos/scripts, not in git)" >&2; exit 1; }

# Command line: the shim puts the DTB's bootargs first, then this, then LK's
# tokens. No androidboot.*: there is no Android here.
CMDLINE="console=ttyMSM0,115200 console=tty0 clk_ignore_unused pd_ignore_unused msm.prefer_mdp5=0 panic=10 loglevel=7"
mkbootimg --header_version 2 --kernel "$O/Image" --ramdisk "$INITRD" --dtb "$O/msm8996-zte-axon7.dtb" \
	--base 0x80000000 --kernel_offset 0x00008000 --ramdisk_offset 0x01000000 \
	--tags_offset 0x00000100 --dtb_offset 0x01f00000 --pagesize 4096 \
	--os_version 17.0.0 --os_patch_level 2026-10 --cmdline "$CMDLINE" -o "$O/m0-test-boot.img"
python3 -I "$R/ios/tools/axon7-androidimg.py" check "$O/m0-test-boot.img"

# Shim host test: android.c exactly as the phone runs it (+ our patch)
W=$O/shim-test
rm -rf "$W"; mkdir -p "$W"
cp "$R"/ios/shim/*.[ch] "$W/"
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
