#!/bin/bash
# LineageOS 24 release build on the build server (self-hosted GitHub Actions
# runner, user "build"; or by hand from a checkout of lineageos-24-mainline):
#   1. the checkout's lineageos-24-mainline/ and Nura's kernel patch series
#      -> /srv/los24/axon7/repo (what server-sync-device.sh does from the PC)
#   2. kernel (scripts/kernel-build.sh all)
#   3. image: los24-build.sh droid as a release flavour: no developer adb key,
#      speaker on, AXON7_FIRMWARE=phone (nothing proprietary in the image)
#   4. TWRP zip (ci/make-zip.sh) -> /srv/los24/releases, zip=... in $GITHUB_OUTPUT
# Waits for a running developer build (tmux los24build / los24kernel) first.
# Note: the release flavour changes product files; the next developer build
# rebuilds those (minutes).
set -euo pipefail
src=$(cd "$(dirname "$0")/../.." && pwd)   # checkout root
repo=/srv/los24/axon7/repo
logs=/srv/los24/logs
while tmux has-session -t los24build 2>/dev/null || tmux has-session -t los24kernel 2>/dev/null; do
	echo "waiting for a running developer build ($(date -u +%T))"; sleep 60
done
echo "== sync $(git -C "$src" log --oneline -1 2>/dev/null || echo '?')"
rsync -a --delete -R -C --exclude=.git \
	"$src/./lineageos-24-mainline" "$src/./postmarketos/pmaports-local/device/testing/linux-zte-axon7" "$repo/"
echo "== kernel $(date -u +%T)"
"$repo/lineageos-24-mainline/scripts/kernel-build.sh" all > "$logs/kernel-latest.log" 2>&1 ||
	{ tail -40 "$logs/kernel-latest.log"; exit 1; }
cat /srv/los24/kernel/prebuilt/version 2>/dev/null || true
echo "== image $(date -u +%T)"
rc=0
AXON7_ADB_KEYS= AXON7_SPEAKER_MUTE=0 AXON7_FIRMWARE=phone \
	"$repo/lineageos-24-mainline/scripts/los24-build.sh" droid || rc=$?
tr '\r' '\n' < "$logs/build-latest.log" | grep -E '####|build-exit|FAILED|error:' | tail -20
[ $rc = 0 ] || exit $rc
echo "== zip $(date -u +%T)"
"$repo/lineageos-24-mainline/ci/make-zip.sh" /srv/los24/lineage-24.0/out/target/product/axon7m /srv/los24/releases
