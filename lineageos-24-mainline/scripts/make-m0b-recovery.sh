#!/bin/bash
# Milestone M0b test image without a new Android build: the LineageOS 24
# recovery.img from the build server, repacked with
#   - the current kernel + DTB from /srv/los24/kernel/prebuilt (e.g. with the
#     APSS watchdog node, kernel/patches/0001), and
#   - the developer's adb key as /adb_keys in the ramdisk (recovery adbd has
#     ro.adb.secure=1 and its /adb_keys points into /product, absent there).
# Header (v2, offsets, cmdline) is taken over from the original image; the
# result is checked like the M0 image (axon7-androidimg.py, shim android.c).
#
# Usage (PC, repository root or worktree; AXON7_SRC = full checkout for ios/):
#   lineageos-24-mainline/scripts/make-m0b-recovery.sh [OUTDIR]   (default /tmp/axon7m-m0b-rec)
set -euo pipefail
R=$(git rev-parse --show-toplevel)
S=${AXON7_SRC:-$R}
O=${1:-/tmp/axon7m-m0b-rec}
H=${AXON7_BUILD_HOST:-root@compiler}
P=/srv/los24/lineage-24.0/out/target/product/axon7m
mkdir -p "$O"
scp -q "$H:$P/recovery.img" "$O/recovery-orig.img"
scp -q "$H:/srv/los24/kernel/prebuilt/Image" "$H:/srv/los24/kernel/prebuilt/dtb/msm8996-zte-axon7.dtb" \
	"$H:/srv/los24/kernel/prebuilt/version" "$H:/srv/los24/lineage-24.0/test-keys/adbkey.pub" "$O/"
rm -rf "$O/u"
mkbootargs=$(unpack_bootimg --boot_img "$O/recovery-orig.img" --out "$O/u" --format=mkbootimg)
gzip -dc "$O/u/ramdisk" > "$O/ramdisk.cpio"
python3 -I "$R/lineageos-24-mainline/scripts/cpio-replace.py" "$O/ramdisk.cpio" "$O/ramdisk-new.cpio" adb_keys "$O/adbkey.pub" 0644
gzip -9n < "$O/ramdisk-new.cpio" > "$O/ramdisk-new.cpio.gz"
# same header arguments, new kernel/DTB/ramdisk
eval "set -- $mkbootargs"
args=()
while [ $# -gt 0 ]; do
	case "$1" in
	--kernel) args+=("$1" "$O/Image"); shift 2 ;;
	--ramdisk) args+=("$1" "$O/ramdisk-new.cpio.gz"); shift 2 ;;
	--dtb) args+=("$1" "$O/msm8996-zte-axon7.dtb"); shift 2 ;;
	*) args+=("$1"); shift ;;
	esac
done
mkbootimg "${args[@]}" -o "$O/m0b-recovery.img"
python3 -I "$S/ios/tools/axon7-androidimg.py" check "$O/m0b-recovery.img"
echo "kernel: $(cat "$O/version")"
ls -l "$O/m0b-recovery.img"; sha256sum "$O/m0b-recovery.img"
