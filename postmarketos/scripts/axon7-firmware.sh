#!/bin/bash
# Build the firmware-zte-axon7 source tarball from your own phone (phone in
# TWRP, USB connected): GPU zap shader from the vendor partition, ADSP, MBA,
# modem, SLPI and Venus from the modem partition (split .mdt images joined
# into .mbn), Wi-Fi board data (bdwlan30.bin). Writes
# pmaports-local/device/testing/firmware-zte-axon7/firmware-zte-axon7-1.tar.gz
# and puts its sha512 into the APKBUILD next to it.
#
# The files are Qualcomm/ZTE property: keep the tarball to yourself.
#
# Usage: scripts/axon7-firmware.sh            (phone in TWRP)
#        scripts/axon7-firmware.sh --from DIR  (DIR has the .mdt/.bNN/.mbn/bdwlan30.bin files)
set -euo pipefail
cd "$(dirname "$0")/.."
pkg=pmaports-local/device/testing/firmware-zte-axon7
work=$(mktemp -d)
trap 'rm -rf "${work:?}"' EXIT
src=$work/src
mkdir -p "$src"

if [ "${1:-}" = --from ]; then
	cp "${2:?usage: $0 --from DIR}"/* "$src/"
else
	[ "$(adb get-state 2>/dev/null)" = recovery ] || { echo "phone is not in TWRP (adb recovery)" >&2; exit 1; }
	echo "reading the modem and vendor partitions (read-only)"
	adb shell 'mkdir -p /tmp/fwm /tmp/fwv
		mount -o ro -t vfat /dev/block/bootdevice/by-name/modem /tmp/fwm
		mount -o ro /dev/block/bootdevice/by-name/vendor /tmp/fwv 2>/dev/null ||
			mount -o ro /dev/block/bootdevice/by-name/system /tmp/fwv' >/dev/null
	for f in $(adb shell 'cd /tmp/fwm/image && ls adsp.* mba.mbn modem.* slpi.* venus.* bdwlan30.bin 2>/dev/null' | tr -d '\r'); do
		adb pull "/tmp/fwm/image/$f" "$src/" >/dev/null
	done
	for d in /tmp/fwv/firmware /tmp/fwv/vendor/firmware /tmp/fwv/system/vendor/firmware; do
		n=$(adb shell "ls $d/a530_zap.mdt 2>/dev/null" | tr -d '\r')
		[ -n "$n" ] || continue
		for f in $(adb shell "cd $d && ls a530_zap.*" | tr -d '\r'); do adb pull "$d/$f" "$src/" >/dev/null; done
		break
	done
	adb shell 'umount /tmp/fwm /tmp/fwv' >/dev/null 2>&1 || true
fi

out=$work/out
fw=$out/qcom/msm8996/zte/axon7
mkdir -p "$fw" "$out/postmarketos/ath10k/QCA6174/hw3.0"
for n in a530_zap adsp modem slpi venus; do
	[ -f "$src/$n.mdt" ] || { echo "missing $n.mdt (is a ROM with a vendor partition, e.g. LineageOS 16-18.1, installed?)" >&2; exit 1; }
	python3 -I scripts/pil-squasher.py "$fw/$n.mbn" "$src/$n.mdt"
done
[ -f "$src/mba.mbn" ] || { echo "missing mba.mbn" >&2; exit 1; }
cp "$src/mba.mbn" "$fw/"
[ -f "$src/bdwlan30.bin" ] || { echo "missing bdwlan30.bin" >&2; exit 1; }
cp "$src/bdwlan30.bin" "$out/postmarketos/ath10k/QCA6174/hw3.0/board.bin"

tarball=$pkg/firmware-zte-axon7-1.tar.gz
tar -C "$out" --owner=0 --group=0 -czf "$tarball" qcom postmarketos
sum=$(sha512sum "$tarball" | cut -d' ' -f1)
python3 -I - "$pkg/APKBUILD" "$sum" <<'EOF'
import re, sys
p, s = sys.argv[1], sys.argv[2]
t = open(p).read()
t = re.sub(r'[0-9a-f]{128}(  firmware-zte-axon7-1\.tar\.gz)', s + r'\1', t)
open(p, "w").write(t)
EOF
ls -l "$tarball"
echo "sha512 written to $pkg/APKBUILD"
