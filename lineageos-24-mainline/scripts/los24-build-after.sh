#!/bin/bash
# Queue a LineageOS 24 build behind the one that is running: waits until the
# running los24-build.sh (tmux session los24build) has written its
# "build-exit" line and no soong_ui/ninja of this tree is left, then runs
# los24-build.sh with the given targets (which copies the device tree and
# kernel from /srv/los24/axon7/repo and /srv/los24/kernel/prebuilt first, so
# nothing reaches the Android tree while the earlier build still runs).
#
#   tmux new -d -s los24next "/srv/los24/axon7/repo/lineageos-24-mainline/scripts/los24-build-after.sh droid"
#   log of the wait: /srv/los24/logs/build-after.log
set -uo pipefail
T=/srv/los24/lineage-24.0
LOGDIR=/srv/los24/logs
PREV=$(readlink -f "$LOGDIR/build-latest.log")
exec >>"$LOGDIR/build-after.log" 2>&1
echo "== $(date -u +%FT%TZ) waiting for $PREV, then los24-build.sh $*"
while ! grep -q "^build-exit" "$PREV" 2>/dev/null ||
	pgrep -u build -f "$T/out/soong_ui|$T/prebuilts/build-tools/linux-x86/bin/(ninja|siso)" >/dev/null; do
	sleep 120
done
echo "$(date -u +%FT%TZ) previous build done: $(grep "^build-exit" "$PREV")"
exec /srv/los24/axon7/repo/lineageos-24-mainline/scripts/los24-build.sh "$@"
