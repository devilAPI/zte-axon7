#!/bin/bash
# Pack a LineageOS 24 build into a TWRP zip (ci/zip/META-INF: installer).
#
# Default: a STANDALONE zip for a phone with the stock partition layout:
#   boot        <- boot.img that LK boots directly (raw kernel, DTB, ramdisk)
#   system      <- super.img (system, system_ext, product, vendor)
#   userdata    <- wiped by the installer, /data in the normal partition
#   cache       <- GPU firmware staged here before system is overwritten
# No multi-boot, no boot menu, no los_* partitions, misc untouched.
#
# AXON7_MULTIBOOT=1 builds the developer flavour (for the owner only):
#   los_boot <- the v2 boot image for the boot menu's LineageOS entry,
#   los_metadata/los_data <- wiped, all other partitions untouched.
# Output: DEST_DIR/lineage-24-DATE-UNOFFICIAL-axon7m[-$AXON7_ZIP_TAG].zip + .sha256; the zip
# path also goes to $GITHUB_OUTPUT (zip=...). super.img is stored as a raw
# image, gzip-compressed (TWRP has gunzip, not simg2img), inside an
# uncompressed zip entry.
set -euo pipefail
out=$(realpath "$1"); dest=$2
here=$(cd "$(dirname "$0")" && pwd)
host=${AXON7_HOST_BIN:-/srv/los24/lineage-24.0/out/host/linux-x86/bin}
{ [ -f "$out/boot.img" ] && [ -f "$out/super.img" ]; } || { echo "no boot.img/super.img in $out" >&2; exit 1; }
flavour=standalone
[ "${AXON7_MULTIBOOT:-0}" = 1 ] && flavour=multiboot
tmp=${TMPDIR:-/srv/los24/tmp}; mkdir -p "$tmp"
w=$(mktemp -d "$tmp/los24zip.XXXXXX")
trap 'rm -rf "$w"' EXIT
cp -r "$here/zip/META-INF" "$w/"
echo "$flavour" > "$w/flavour"
bootname=boot.img
if [ "$flavour" = standalone ]; then
	# LK needs header v0, gzip(Image) + appended DTB; the shim's v2 image
	# would not boot directly from the boot partition.
	python3 "$here/make-standalone-boot.py" "$out/boot.img" -o "$w/$bootname"
else
	bootname=los-boot.img
	if python3 -I "$here/../scripts/axon7-androidimg.py" check "$out/boot.img" >/dev/null 2>&1; then
		cp "$out/boot.img" "$w/$bootname"
	else
		python3 -I "$here/../scripts/axon7-androidimg.py" convert "$out/boot.img" -o "$w/$bootname"
	fi
	python3 -I "$here/../scripts/axon7-androidimg.py" check "$w/$bootname"
fi
"$host/simg2img" "$out/super.img" "$w/super.raw" >/dev/null
super_size=$(stat -c %s "$w/super.raw"); boot_size=$(stat -c %s "$w/$bootname")
[ $((super_size % 1048576)) = 0 ] || { echo "super size not a MiB multiple" >&2; exit 1; }
sha1sum < "$w/super.raw" | cut -d' ' -f1 > "$w/super.raw.sha1"
sha1sum < "$w/$bootname" | cut -d' ' -f1 > "$w/$bootname.sha1"
echo "$super_size $boot_size" > "$w/sizes"
gzip -1 -c "$w/super.raw" > "$w/super.raw.gz"; rm "$w/super.raw"
date=$(date -u +%Y%m%d)
tag=${AXON7_ZIP_TAG:-}
[ "$flavour" = multiboot ] && [ -z "$tag" ] && tag=MULTIBOOT
name=lineage-24-$date-UNOFFICIAL-axon7m${tag:+-$tag}.zip
mkdir -p "$dest"; rm -f "$dest/$name"
(cd "$w" && zip -0 -q -r "$dest/$name" META-INF flavour sizes "$bootname" "$bootname.sha1" super.raw.sha1 super.raw.gz)
(cd "$dest" && sha256sum "$name" > "$name.sha256")
echo "== $dest/$name ($flavour, $(du -h "$dest/$name" | cut -f1))"
echo "zip=$dest/$name" >> "${GITHUB_OUTPUT:-/dev/null}"
