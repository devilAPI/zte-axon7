#!/bin/bash
# LineageOS 24 build for the Axon 7 mainline port (axon7m), on the build server.
#
#   tmux new -d -s los24build "/srv/los24/axon7/repo/lineageos-24-mainline/scripts/los24-build.sh [TARGET...]"
#   log: /srv/los24/logs/build-<date>.log  (latest also as /srv/los24/logs/build-latest.log)
#
# Default targets: recoveryimage bootimage (milestone M0b: a recovery-mode image
# with the mainline kernel, adbd and no system partition). Full M1 build: "m"
# targets superimage etc. (pass them).
#
# Waits for a running repo sync (sync.sh writes "sync-exit 0") and kernel
# build (tmux session los24kernel) to finish, then
# copies the device tree from /srv/los24/axon7/repo and the kernel prebuilts
# from /srv/los24/kernel/prebuilt into the tree.
# Time: the first build takes about 2-4 h for recovery/boot images (Soong
# bootstrap, host tools), 5-8 h for everything on 7 threads; later builds
# 10-60 min.
set -uo pipefail
T=/srv/los24/lineage-24.0
REPO=/srv/los24/axon7/repo
LOGDIR=/srv/los24/logs
LOG=$LOGDIR/build-$(date -u +%Y%m%d-%H%M).log
ln -sfn "$LOG" "$LOGDIR/build-latest.log"
exec >"$LOG" 2>&1
echo "== $(date -u +%FT%TZ) los24-build.sh ${*:-recoveryimage bootimage}"

# 1. sync and kernel build finished?
while pgrep -u build -f "repo/main.py.*sync" >/dev/null || tmux has-session -t los24kernel 2>/dev/null; do sleep 60; done
# Soong analysis needs nearly all of the container's 31 GB: never next to a
# LineageOS 22.2 build (/srv/aosp) or another Android build
while pgrep -f "/srv/aosp/lineage-22.2/out/(soong_ui|host/linux-x86/bin/soong_build)" >/dev/null; do
	echo "waiting: a LineageOS 22.2 build is running ($(date -u +%T))"; sleep 120
done
grep -q "sync-exit 0" "$LOGDIR/repo-sync.log" || { echo "repo sync did not finish cleanly, see $LOGDIR/repo-sync.log"; exit 1; }
df -h /srv | tail -1

# 2. device tree + kernel prebuilts into the tree
mkdir -p "$T/device/zte" "$T/.repo/local_manifests"
rsync -a --delete "$REPO/lineageos-24-mainline/device/zte/axon7m/" "$T/device/zte/axon7m/"
cp "$REPO/lineageos-24-mainline/manifest/axon7m.xml" "$T/.repo/local_manifests/"
[ -f /srv/los24/kernel/prebuilt/Image ] || { echo "no kernel in /srv/los24/kernel/prebuilt: run kernel-build.sh first"; exit 1; }
rsync -a --delete /srv/los24/kernel/prebuilt/ "$T/device/zte/axon7m-kernel/"
echo "kernel $(cat "$T/device/zte/axon7m-kernel/version")"

# 3. local patches to the Android tree: lineageos-24-mainline/aosp/<project
#    path>/*.patch (-p1 inside that project), each applied once
A=$REPO/lineageos-24-mainline/aosp
while IFS= read -r p; do
	proj=$(dirname "${p#$A/}")
	if patch -d "$T/$proj" -p1 -R -s -f --dry-run < "$p" >/dev/null 2>&1; then
		echo "patch already in $proj: $(basename "$p")"
	else
		patch -d "$T/$proj" -p1 -N -s < "$p" || { echo "patch failed: $p"; exit 1; }
		echo "applied to $proj: $(basename "$p")"
	fi
done < <(find "$A" -name '*.patch' 2>/dev/null | sort)

# 4. build
cd "$T" && . ~/.profile && ulimit -n 65536
# (SOONG_GOMEMLIMIT is gone in Android 17: aosp/build/blueprint patch instead)
export USE_CCACHE=1 CCACHE_EXEC=/usr/bin/ccache CCACHE_DIR=/srv/los24/ccache
mkdir -p "$CCACHE_DIR"; ccache -M 15G >/dev/null 2>&1 || true
source build/envsetup.sh >/dev/null
breakfast axon7m || lunch lineage_axon7m-userdebug || { echo "lunch failed"; exit 1; }
echo "== build $(date -u +%FT%TZ)"
# nice: the LineageOS 22.2 builds in /srv/aosp share this machine and come first
nice -n 15 ionice -c3 bash -c "source build/envsetup.sh >/dev/null; breakfast axon7m >/dev/null 2>&1 || lunch lineage_axon7m-userdebug >/dev/null; m -j7 ${*:-recoveryimage bootimage}"
rc=$?
echo "build-exit $rc $(date -u +%FT%TZ)"
ls -la "$OUT"/*.img 2>/dev/null
df -h /srv | tail -1
exit $rc
