#!/bin/bash
# Build the standalone LineageOS 22.2 TWRP zip on the build server (run by the
# self-hosted GitHub Actions runner, user "build", or by hand).
#
# Release flavour (/data on userdata, microSD for Android, no multi-boot), no
# developer adb keys, no test files. TWO builds of the same tree, then combined
# (combine-zip.py) into one zip that detects the layout at install time:
#   AXON7_STANDALONE=1        community layout: vendor partition (512 MiB after system)
#   AXON7_STANDALONE=novendor ZTE's original layout: vendor files inside system
# Set AXON7_LAYOUTS=vendor to build only the first (the old single-layout zip).
#
# Output: /srv/aosp/releases/lineage-22.2-DATE-UNOFFICIAL-axon7.zip + .sha256;
# the zip path also goes to $GITHUB_OUTPUT (zip=...).
set -euo pipefail
tree=${AXON7_TREE:-/srv/aosp/lineage-22.2}
dest=${AXON7_RELEASES:-/srv/aosp/releases}
out=$tree/out/target/product/axon7

# one build at a time in this tree (manual builds use the same lock)
exec 9>/srv/aosp/build.lock
echo "== waiting for the build lock $(date +%T)"; flock 9; echo "== got it $(date +%T)"

cd "$tree"
# shellcheck disable=SC1090
. ~/.profile
ulimit -n 65536
export USE_CCACHE=1 CCACHE_EXEC=/usr/bin/ccache CCACHE_DIR=/srv/aosp/.ccache SOONG_GOMEMLIMIT=22GiB
export AXON7_ADB_KEYS= AXON7_TEST=
layouts=${AXON7_LAYOUTS:-both}
parts=$dest/parts
mkdir -p "$parts"

build_one() {	# $1 = vendor|stock
	local flavour
	[ "$1" = vendor ] && flavour=1 || flavour=novendor
	export AXON7_STANDALONE=$flavour
	# Files that developer/test builds copied into out/ stay there otherwise.
	rm -f "$out"/vendor/etc/init/init.axon7-test.rc "$out"/vendor/etc/axon7-misc-pmos.bin \
		"$out"/vendor/bin/axon7-testguard.sh "$out"/vendor/etc/init/init.axon7-log.rc \
		"$out"/vendor/bin/axon7-testlog.sh "$out"/product/etc/security/adb_keys
	rm -f "$out"/lineage-22.2-*-UNOFFICIAL-axon7.zip "$out"/lineage-22.2-*-UNOFFICIAL-axon7.zip.sha256sum
	set +u
	source build/envsetup.sh >/dev/null
	breakfast axon7 >/dev/null
	set -u
	echo "== $1 layout $(date) device $(git -c safe.directory='*' -C device/zte/axon7 log --oneline -1)"
	echo "== kernel $(git -c safe.directory='*' -C kernel/zte/msm8996 log --oneline -1)"
	m -j4 bacon
	cp "$(ls -t "$out"/lineage-22.2-*-UNOFFICIAL-axon7.zip | head -1)" "$parts/$1.zip"
}

case $layouts in
	vendor) build_one vendor ;;
	both) build_one vendor; build_one stock ;;
	*) echo "AXON7_LAYOUTS must be vendor or both" >&2; exit 2 ;;
esac

name=$(basename "$(ls -t "$out"/lineage-22.2-*-UNOFFICIAL-axon7.zip | head -1)")
mkdir -p "$dest"
if [ "$layouts" = both ]; then
	here=$(cd "$(dirname "$0")" && pwd)
	sec=build/make/target/product/security
	python3 "$here/combine-zip.py" --vendor-zip "$parts/vendor.zip" --stock-zip "$parts/stock.zip" \
		--out "$dest/$name" \
		--sign-cmd "java -Djava.library.path=$tree/out/host/linux-x86/lib64 -jar $tree/out/host/linux-x86/framework/signapk.jar -w $tree/$sec/testkey.x509.pem $tree/$sec/testkey.pk8 {in} {out}"
else
	cp "$parts/vendor.zip" "$dest/$name"
fi
(cd "$dest" && sha256sum "$name" > "$name.sha256")
echo "== $dest/$name ($(du -h "$dest/$name" | cut -f1))"
if [ -n "${GITHUB_OUTPUT:-}" ]; then echo "zip=$dest/$name" >> "$GITHUB_OUTPUT"; fi
