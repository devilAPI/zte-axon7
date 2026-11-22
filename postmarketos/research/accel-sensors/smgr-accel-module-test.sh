#!/bin/bash
# Verify the patched smgr_accel.ko (scale 9.81/690310) on the MAIN phone in
# LineageOS 24 without a new kernel or a reboot.
#
#   ./smgr-accel-module-test.sh [patched.ko] [sensread-binary]
#
# Runs under the main phone's flock (re-execs itself once to take it).
# It saves the original /vendor module on the HDD, stops the sensors HAL,
# unbinds qcom-smgr-accel, swaps the module, measures, and ALWAYS restores the
# original module and HAL before releasing the lock. No writes to boot, misc,
# persist, EFS or modem; no SLPI restart; no sound, no vibration.
set -uo pipefail
export ANDROID_SERIAL=7e15695a
LOCK=$HOME/.cache/axon7-phone-7e15695a.lock
if [ "${ACCEL_LOCKED:-0}" != 1 ]; then
	ACCEL_LOCKED=1 exec flock -w 7200 "$LOCK" "$0" "$@"
fi

H="/media/devilapi/Secondary HDD 2TB/ai-worker/axon7"
MOD=${1:-$H/accel-build/smgr_accel-fixed.ko}
SENSREAD=${2:-$H/accel-build/sensread}
LOGDIR=$H/accel-build/logs-$(date -u +%Y%m%dT%H%M%SZ)
mkdir -p "$LOGDIR"
exec > >(tee "$LOGDIR/test.log") 2>&1
say() { echo "== $(date -u +%FT%TZ) $*"; }
ash() { adb shell "$@" | tr -d '\r'; }
DEV=qcom-smgr-accel
DRV=smgr_accel
HAL=vendor.sensors-axon7m
remote=/data/local/tmp
hal_stopped=0 unbound=0 removed=0 inserted=0

# sysfs reading helper: find the IIO device whose name is qcom-smgr-accel
accel_dir() {
	ash "for d in /sys/bus/iio/devices/iio:device*; do [ \"\$(cat \$d/name 2>/dev/null)\" = qcom-smgr-accel ] && echo \$d; done" | head -1
}

measure() {
	local tag=$1 d r n
	d=$(accel_dir)
	echo "--- $tag: IIO device $d ---"
	[ -n "$d" ] || { echo "no accel IIO device"; return 1; }
	ash "cat $d/in_accel_scale" | sed 's/^/  in_accel_scale = /'
	for i in 1 2 3; do
		r=$(ash "cat $d/in_accel_x_raw; cat $d/in_accel_y_raw; cat $d/in_accel_z_raw" | tr '\n' ' ')
		n=$(python3 -c "import math,sys; v=[int(x) for x in sys.argv[1:]]; print(math.sqrt(sum(x*x for x in v)))" $r)
		echo "  raw[$i] = $r  norm = $n"
		sleep 1
	done
	if [ -x "$SENSREAD" ]; then
		adb push "$SENSREAD" "$remote/sensread" >/dev/null
		ash "chmod 755 $remote/sensread && timeout 20 $remote/sensread 2"
	fi
}

cleanup() {
	local rc=$?
	say "cleanup (rc=$rc)"
	if [ $inserted = 1 ]; then
		ash "timeout 20 rmmod $DRV" || echo "WARN: rmmod patched module failed"
		inserted=0
	fi
	if [ $removed = 1 ] || ash "grep -q \"^${DRV} \" /proc/modules" >/dev/null 2>&1; then
		ash "timeout 20 rmmod $DRV" || true
	fi
	# always restore the exact module that came with the image
	if [ -f "$LOGDIR/smgr_accel-orig.ko" ]; then
		adb push "$LOGDIR/smgr_accel-orig.ko" "$remote/smgr_accel-orig.ko" >/dev/null 2>&1 || true
		ash "timeout 20 insmod $remote/smgr_accel-orig.ko" || echo "WARN: restoring original module failed"
	fi
	if [ $unbound = 1 ]; then
		ash "echo $DEV > /sys/bus/platform/drivers/$DRV/bind" || echo "WARN: rebind failed"
	fi
	if [ $hal_stopped = 1 ]; then
		ash "setprop ctl.start $HAL" || true
	fi
	sleep 3
	say "after restore: module=$(ash "grep -c \"^${DRV} \" /proc/modules") device=$(accel_dir) scale=$(ash "cat $(accel_dir)/in_accel_scale 2>/dev/null")"
	ash "svc power stayon false" || true
	say "boot_completed=$(ash 'getprop sys.boot_completed') battery=$(ash 'cat /sys/class/power_supply/qcom-battery/capacity')%"
	say "LOGDIR=$LOGDIR"
}
trap cleanup EXIT INT TERM

say "preconditions"
[ "$(adb get-state)" = device ] || { echo "phone not in LineageOS on adb" >&2; exit 2; }
adb root >/dev/null 2>&1; sleep 3; timeout 30 adb wait-for-device
bc=$(ash 'getprop sys.boot_completed'); bat=$(ash 'cat /sys/class/power_supply/qcom-battery/capacity')
echo "boot_completed=$bc battery=$bat% uname=$(ash 'uname -v')"
[ "$bc" = 1 ] || { echo "not fully booted" >&2; exit 2; }
[ "$bat" -ge 30 ] || { echo "battery below 30%" >&2; exit 2; }
[ -f "$MOD" ] || { echo "patched module missing: $MOD" >&2; exit 2; }
echo "patched module sha256: $(sha256sum "$MOD")"
echo "original module (phone): $(ash 'ls -l /vendor/lib/modules/smgr_accel.ko')"

say "save the original module (read-only)"
adb exec-out cat /vendor/lib/modules/smgr_accel.ko > "$LOGDIR/smgr_accel-orig.ko"
osz=$(stat -c %s "$LOGDIR/smgr_accel-orig.ko")
echo "saved $osz bytes, sha256: $(sha256sum "$LOGDIR/smgr_accel-orig.ko")"
[ "$osz" -gt 1000 ] || { echo "could not save the original module" >&2; exit 2; }

measure before
D0=$(adb shell dmesg | wc -l)
echo "DMESG_START=$D0"

say "stop HAL, unbind $DEV, swap module"
ash "setprop ctl.stop $HAL"; hal_stopped=1; sleep 2
ash "echo $DEV > /sys/bus/platform/drivers/$DRV/unbind"; unbound=1; sleep 1
ash "timeout 20 rmmod $DRV"; removed=1
adb push "$MOD" "$remote/smgr_accel-fixed.ko" >/dev/null
out=$(ash "timeout 30 insmod $remote/smgr_accel-fixed.ko 2>&1") || { echo "insmod FAILED: $out" >&2; exit 3; }
echo "insmod: $out"; inserted=1
ash "echo $DEV > /sys/bus/platform/drivers/$DRV/bind"; unbound=0
ash "setprop ctl.start $HAL"; hal_stopped=0
sleep 5

say "after the swap"
echo "loaded: $(ash "grep \"^${DRV} \" /proc/modules")"
measure after
say "new dmesg"
adb shell dmesg | tail -n +$((D0 + 1)) | grep -iE 'smgr|iio|sensor|error|warn' | tail -60 || true
exit 0
