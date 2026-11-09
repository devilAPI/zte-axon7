#!/bin/bash
# Build the standalone LineageOS 22.2 TWRP zip on the build server (run by the
# self-hosted GitHub Actions runner, user "build", or by hand).
#
# Release flavour: AXON7_STANDALONE=1 (/data on userdata, microSD for Android,
# no multi-boot), no developer adb keys, no test files. Partition layout: ZTE's
# plus the community vendor partition (512 MiB after system, Oki's PARTY tool).
#
# Output: /srv/aosp/releases/lineage-22.2-DATE-UNOFFICIAL-axon7.zip + .sha256;
# the zip path also goes to $GITHUB_OUTPUT (zip=...).
set -euo pipefail
tree=${AXON7_TREE:-/srv/aosp/lineage-22.2}
dest=${AXON7_RELEASES:-/srv/aosp/releases}
out=$tree/out/target/product/axon7

cd "$tree"
# shellcheck disable=SC1090
. ~/.profile
ulimit -n 65536
export USE_CCACHE=1 CCACHE_EXEC=/usr/bin/ccache CCACHE_DIR=/srv/aosp/.ccache SOONG_GOMEMLIMIT=22GiB
export AXON7_STANDALONE=1 AXON7_ADB_KEYS= AXON7_TEST=

# Files that developer/test builds copied into out/ stay there otherwise.
rm -f "$out"/vendor/etc/init/init.axon7-test.rc "$out"/vendor/etc/axon7-misc-pmos.bin \
	"$out"/vendor/bin/axon7-testguard.sh "$out"/vendor/etc/init/init.axon7-log.rc \
	"$out"/vendor/bin/axon7-testlog.sh "$out"/product/etc/security/adb_keys
rm -f "$out"/lineage-22.2-*-UNOFFICIAL-axon7.zip "$out"/lineage-22.2-*-UNOFFICIAL-axon7.zip.sha256sum

set +u
source build/envsetup.sh >/dev/null
breakfast axon7 >/dev/null
set -u
echo "== $(date) device $(git -c safe.directory='*' -C device/zte/axon7 log --oneline -1)"
echo "== kernel $(git -c safe.directory='*' -C kernel/zte/msm8996 log --oneline -1)"
m -j8 bacon

zip=$(ls -t "$out"/lineage-22.2-*-UNOFFICIAL-axon7.zip | head -1)
mkdir -p "$dest"
cp "$zip" "$dest"/
name=$(basename "$zip")
(cd "$dest" && sha256sum "$name" > "$name.sha256")
echo "== $dest/$name ($(du -h "$dest/$name" | cut -f1))"
echo "zip=$dest/$name" >> "${GITHUB_OUTPUT:-/dev/null}"
