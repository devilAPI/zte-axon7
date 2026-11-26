#!/bin/bash
# Compare the vendor files of the stock-layout system image (system/vendor) with the
# separate vendor image of the vendor-layout build: same paths, modes, owners,
# SELinux labels and capabilities. Run as root on the build server (loop mounts,
# read-only). Usage: verify-stock-image.sh STOCK_system.img VENDOR_vendor.img
# (both from the same source tree; the images are copied out of out/ between the two builds)
set -eu
sys=${1:?stock system.img}; ven=${2:?vendor.img}
w=$(mktemp -d); trap 'umount "$w/s" "$w/v" 2>/dev/null || true; rm -rf "$w"' EXIT
mkdir "$w/s" "$w/v"
for i in sys ven; do
	f=${!i}
	if file -b "$f" | grep -q 'Android sparse'; then simg2img "$f" "$w/$i.raw"; else cp --sparse=always "$f" "$w/$i.raw"; fi
done
mount -o ro,loop "$w/sys.raw" "$w/s"; mount -o ro,loop "$w/ven.raw" "$w/v"
dump() {	# $1 root dir -> "path mode uid gid label caps"
	(cd "$1" && find . -mindepth 1 \( -type f -o -type d -o -type l \) -printf '%p %m %U %G ' -exec sh -c \
		'for f; do printf "%s %s\n" "$(getfattr -h -n security.selinux --only-values "$f" 2>/dev/null | tr -d "\0")" "$(getfattr -h -e hex -n security.capability --only-values "$f" 2>/dev/null | tr -d "\0")"; done' sh {} \; | sort)
}
dump "$w/s/vendor" > "$w/s.txt"
dump "$w/v" > "$w/v.txt"
echo "stock system/vendor: $(wc -l < "$w/s.txt") entries, vendor image: $(wc -l < "$w/v.txt") entries"
if diff "$w/v.txt" "$w/s.txt" > "$w/d.txt"; then echo "IDENTICAL"; else echo "DIFFERENCES: $(grep -c '^[<>]' "$w/d.txt")"; head -40 "$w/d.txt"; exit 1; fi
