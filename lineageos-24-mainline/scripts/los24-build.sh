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

# 2. device tree + kernel prebuilts into the tree (by checksum, without the
# source file times: a changed file must be newer than its copy in out/)
mkdir -p "$T/device/zte" "$T/.repo/local_manifests"
rsync -rlpgoD --checksum --delete "$REPO/lineageos-24-mainline/device/zte/axon7m/" "$T/device/zte/axon7m/"
cp "$REPO/lineageos-24-mainline/manifest/axon7m.xml" "$T/.repo/local_manifests/"
[ -f /srv/los24/kernel/prebuilt/Image ] || { echo "no kernel in /srv/los24/kernel/prebuilt: run kernel-build.sh first"; exit 1; }
rsync -rlpgoD --checksum --delete /srv/los24/kernel/prebuilt/ "$T/device/zte/axon7m-kernel/"
echo "kernel $(cat "$T/device/zte/axon7m-kernel/version")"
# Mesa freedreno prebuilts (scripts/mesa-build.sh), used with AXON7_GPU=mesa
if [ -f /srv/los24/mesa/out/Android.bp ]; then
	rsync -rlpgoD --checksum --delete /srv/los24/mesa/out/ "$T/device/zte/axon7m-mesa/"
	echo "$(cat "$T/device/zte/axon7m-mesa/version")"
fi

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
# developer builds (default): adb for the key in test-keys/adbkey.pub (the same
# PC key as LineageOS 22.2's test-keys); AXON7_ADB_KEYS= for a normal build
export AXON7_ADB_KEYS=${AXON7_ADB_KEYS-test-keys/adbkey.pub}
export AXON7_GPU=${AXON7_GPU:-swiftshader}
echo "AXON7_GPU=$AXON7_GPU AXON7_ADB_KEYS=$AXON7_ADB_KEYS"
[ -z "$AXON7_ADB_KEYS" ] || [ -r "$T/$AXON7_ADB_KEYS" ] || { echo "missing $T/$AXON7_ADB_KEYS"; exit 1; }
export USE_CCACHE=1 CCACHE_EXEC=/usr/bin/ccache CCACHE_DIR=$(readlink -f /srv/los24/ccache)  # real path: nsjail cannot bind-mount a symlink
mkdir -p "$CCACHE_DIR"; ccache -M 15G >/dev/null 2>&1 || true
source build/envsetup.sh >/dev/null
breakfast axon7m || lunch lineage_axon7m-userdebug || { echo "lunch failed"; exit 1; }
echo "== build $(date -u +%FT%TZ)"
# Disk watchdog: /srv also holds LineageOS 22.2; stop this build (only this
# tree's soong_ui/ninja/siso) before /srv drops under MIN_FREE_GB
MIN_FREE_GB=${MIN_FREE_GB:-15}
(
	while sleep 60; do
		avail=$(df --output=avail -k /srv | tail -1)
		if [ "$avail" -lt $((MIN_FREE_GB * 1024 * 1024)) ]; then
			echo "DISK WATCHDOG: under $MIN_FREE_GB GB free on /srv, stopping the build $(date -u +%T)"
			pkill -u build -f "$T/out/soong_ui"
			pkill -u build -f "$T/prebuilts/build-tools/linux-x86/bin/(ninja|siso)"
			pkill -u build -f "$T/out/.*/(ninja|siso)"
			break
		fi
	done
) &
WD=$!
# Priority: normal by default. The idle I/O class (ionice -c3) on this HDD
# pool starved the build for hours whenever anything else touched the disk,
# and the container cannot raise a running build's priority afterwards (no
# CAP_SYS_NICE). Only when a LineageOS 22.2 build must come first:
# LOS24_PRIO="nice -n 15 ionice -c3". Jobs: all 8 threads of the i7-6700
# (7 in the container plus one to cover I/O waits on the HDD).
LOS24_PRIO=${LOS24_PRIO-}
LOS24_JOBS=${LOS24_JOBS:-8}
echo "priority: ${LOS24_PRIO:-normal}, jobs: $LOS24_JOBS"
$LOS24_PRIO bash -c "source build/envsetup.sh >/dev/null; breakfast axon7m >/dev/null 2>&1 || lunch lineage_axon7m-userdebug >/dev/null; m -j$LOS24_JOBS ${*:-recoveryimage bootimage}"
rc=$?
kill "$WD" 2>/dev/null
echo "build-exit $rc $(date -u +%FT%TZ)"
ls -la "$OUT"/*.img 2>/dev/null
df -h /srv | tail -1
exit $rc
