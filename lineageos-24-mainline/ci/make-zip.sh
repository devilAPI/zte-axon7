#!/bin/bash
# Pack a LineageOS 24 build into the TWRP zip (ci/zip/META-INF: installer).
#   ci/make-zip.sh OUT_DIR DEST_DIR      (OUT_DIR: out/target/product/axon7m)
# Output: DEST_DIR/lineage-24-DATE-UNOFFICIAL-axon7m.zip + .sha256; the zip
# path also goes to $GITHUB_OUTPUT (zip=...). super.img is stored as a raw
# image, gzip-compressed (TWRP has gunzip, not simg2img), inside an
# uncompressed zip entry.
set -euo pipefail
out=$(realpath "$1"); dest=$2
here=$(cd "$(dirname "$0")" && pwd)
host=${AXON7_HOST_BIN:-/srv/los24/lineage-24.0/out/host/linux-x86/bin}
[ -f "$out/boot.img" ] && [ -f "$out/super.img" ] || { echo "no boot.img/super.img in $out" >&2; exit 1; }
tmp=${TMPDIR:-/srv/los24/tmp}; mkdir -p "$tmp"
w=$(mktemp -d "$tmp/los24zip.XXXXXX")
trap 'rm -rf "$w"' EXIT
cp -r "$here/zip/META-INF" "$w/"
python3 -I "$here/../scripts/axon7-androidimg.py" check "$out/boot.img" >/dev/null 2>&1 &&
	cp "$out/boot.img" "$w/los-boot.img" ||
	python3 -I "$here/../scripts/axon7-androidimg.py" convert "$out/boot.img" -o "$w/los-boot.img"
python3 -I "$here/../scripts/axon7-androidimg.py" check "$w/los-boot.img"
"$host/simg2img" "$out/super.img" "$w/super.raw"
super_size=$(stat -c %s "$w/super.raw"); boot_size=$(stat -c %s "$w/los-boot.img")
[ $((super_size % 1048576)) = 0 ] || { echo "super size not a MiB multiple" >&2; exit 1; }
sha1sum < "$w/super.raw" | cut -d' ' -f1 > "$w/super.raw.sha1"
sha1sum < "$w/los-boot.img" | cut -d' ' -f1 > "$w/los-boot.img.sha1"
echo "$super_size $boot_size" > "$w/sizes"
gzip -1 -c "$w/super.raw" > "$w/super.raw.gz"; rm "$w/super.raw"
date=$(date -u +%Y%m%d)
name=lineage-24-$date-UNOFFICIAL-axon7m.zip
mkdir -p "$dest"; rm -f "$dest/$name"
(cd "$w" && zip -0 -q -r "$dest/$name" META-INF sizes los-boot.img los-boot.img.sha1 super.raw.sha1 super.raw.gz)
(cd "$dest" && sha256sum "$name" > "$name.sha256")
echo "== $dest/$name ($(du -h "$dest/$name" | cut -f1))"
echo "zip=$dest/$name" >> "${GITHUB_OUTPUT:-/dev/null}"
