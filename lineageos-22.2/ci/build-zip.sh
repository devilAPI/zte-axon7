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

# One build at a time in this tree (manual builds use the same lock). The
# monthly updater holds fd 9 already; taking the lock twice would deadlock.
if [[ ${AXON7_BUILD_LOCK_FD:-} != 9 ]]; then
	exec 9>/srv/aosp/build.lock
	echo "== waiting for the build lock $(date +%T)"; flock 9; echo "== got it $(date +%T)"
else
	echo "== build lock held by the monthly updater $(date +%T)"
fi

cd "$tree"
# The monthly updater passes the fork heads it restored. Re-check immediately
# before the build: an untracked port file or a wrong HEAD must abort, not
# produce a zip from a half-restored tree.
if [[ -n ${AXON7_EXPECT_DEVICE_SHA:-} ]]; then
	dev_head=$(git -c safe.directory='*' -C device/zte/axon7 rev-parse HEAD)
	kernel_head=$(git -c safe.directory='*' -C kernel/zte/msm8996 rev-parse HEAD)
	if [[ $dev_head != "$AXON7_EXPECT_DEVICE_SHA" || $kernel_head != "$AXON7_EXPECT_KERNEL_SHA" ]]; then
		echo "ERROR: wrong fork heads: device=$dev_head (want $AXON7_EXPECT_DEVICE_SHA), kernel=$kernel_head (want $AXON7_EXPECT_KERNEL_SHA)" >&2
		exit 1
	fi
	for p in device/zte/axon7 kernel/zte/msm8996 vendor/zte; do
		if [[ -n $(git -c safe.directory='*' -C "$p" status --porcelain) ]]; then
			echo "ERROR: $p is dirty (untracked port files?) before the build" >&2
			exit 1
		fi
	done
	echo "== verified fork heads device=$dev_head kernel=$kernel_head, trees clean $(date +%T)"
fi
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
m -j4 bacon

zip=$(ls -t "$out"/lineage-22.2-*-UNOFFICIAL-axon7.zip | head -1)
mkdir -p "$dest"
cp "$zip" "$dest"/
name=$(basename "$zip")
(cd "$dest" && sha256sum "$name" > "$name.sha256")
echo "== $dest/$name ($(du -h "$dest/$name" | cut -f1))"
echo "zip=$dest/$name" >> "${GITHUB_OUTPUT:-/dev/null}"
