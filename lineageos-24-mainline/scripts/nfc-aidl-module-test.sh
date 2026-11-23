#!/bin/bash
# Bind-mount test of the Axon 7 PN548 AIDL NFC HAL on the MAIN phone.
#
#   scripts/nfc-aidl-module-test.sh HAL_BINARY [NFC_AIDL_LIB] [PN5XX_MODULE] [STUB_LIB]
#
# No reboot, no boot/misc/persist/EFS writes and no adb remount: the char
# driver is inserted as a module into the running kernel, the HAL runs from
# /data/local/tmp, and /vendor/etc/permissions is bind-mounted from a copy
# with android.hardware.nfc.xml added so the NFC app starts. A framework
# restart (not a reboot) makes PackageManager see the new feature.
#
# STUB_LIB is a test-only LD_PRELOAD shim that interposes
# AIBinder_markVintfStability() so servicemanager accepts the AIDL service on
# a build without AXON7_NFC=1 (no VINTF entry). Real images install the
# manifest fragment from device/zte/axon7m/nfc/ and need no shim. Do NOT
# restart servicemanager here: its onrestart restarts all HAL/main classes
# and can reboot the phone (seen 2026-11-23).
#
# Run under the main phone's flock session. On exit the script restores the
# permissions mount, stops the HAL, removes the module and rebinds nxp-nci.
set -uo pipefail
export ANDROID_SERIAL=7e15695a
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
H=$ROOT
HAL=${1:?HAL binary path}
LIB=${2:-}   # optional when the AIDL generated code is linked into the binary
MOD=${3:-$HOME/axon7-kbuild/nfchal-mod/pn5xx-raw.ko}
STUB=${4:-}   # test-only VINTF-stability interposer, see header
LOG=$H/logs/nfc-aidl-$(date -u +%Y%m%dT%H%M%SZ).log
DETAIL=$(dirname "$LOG")/$(basename "$LOG" .log)
mkdir -p "$(dirname "$LOG")" "$DETAIL"
exec > >(tee "$LOG") 2>&1

SERIAL=$ANDROID_SERIAL
DEV=3-0028
NXPDRV=nxp-nci_i2c
REMOTE=/data/local/tmp/nfcaidl
HALNAME=android.hardware.nfc-service.axon7m
LIBNAME=android.hardware.nfc-V2-ndk.so
STUBNAME=nfc-no-vintf-stub.so
STUBENV=
[ -n "$STUB" ] && STUBENV=$REMOTE/$STUBNAME
MODNAME=pn5xx_raw
PERMS=/vendor/etc/permissions
bound=0 inserted=0 mounted=0 hal_pid= logcat_pid= framework_restarted=0
sound_effects= vibrate_on=

say() { echo "== $(date -u +%FT%TZ) $*"; }
ash() { adb shell "$@" | tr -d '\r'; }
run() { echo "+ $*"; adb shell "$@"; }

save_settings() {
	sound_effects=$(ash 'settings get system sound_effects_enabled')
	vibrate_on=$(ash 'settings get system vibrate_on')
	ash 'settings put system sound_effects_enabled 0'
	ash 'settings put system vibrate_on 0'
}

cleanup() {
	local rc=$?
	say "cleanup (rc=$rc)"
	[ -n "$logcat_pid" ] && kill "$logcat_pid" 2>/dev/null || true
	if [ -n "$hal_pid" ]; then
		ash "kill $hal_pid 2>/dev/null || true"
	fi
	if [ $mounted = 1 ]; then
		ash "umount $PERMS" || echo "umount $PERMS FAILED" >&2
	fi
	# Restore the original (silent) settings if we changed them.
	[ -n "$sound_effects" ] && [ "$sound_effects" != null ] && \
		ash "settings put system sound_effects_enabled $sound_effects" || true
	[ -n "$vibrate_on" ] && [ "$vibrate_on" != null ] && \
		ash "settings put system vibrate_on $vibrate_on" || true
	if [ $inserted = 1 ] || ash 'grep -q "^pn5xx_raw " /proc/modules' >/dev/null 2>&1; then
		ash "timeout 20 rmmod $MODNAME" || {
			# An open fd in the HAL keeps the module busy: kill it and retry.
			[ -n "$hal_pid" ] && ash "kill -9 $hal_pid 2>/dev/null || true"
			sleep 1
			ash "timeout 20 rmmod $MODNAME" || echo "rmmod failed" >&2
		}
	fi
	if [ $bound = 1 ] || ash 'grep -q "^pn5xx_raw " /proc/modules' >/dev/null 2>&1; then
		# Binding can race with the module's own unbind work; wait for nfc0.
		for i in $(seq 1 10); do
			ash "echo $DEV > /sys/bus/i2c/drivers/$NXPDRV/bind" >/dev/null 2>&1 || true
			[ "$(ash "test -e /sys/class/nfc/nfc0 && echo present || echo MISSING")" = present ] && break
			sleep 2
		done
	fi
	say "after cleanup: boot_completed=$(ash 'getprop sys.boot_completed') battery=$(ash 'cat /sys/class/power_supply/qcom-battery/capacity')%"
	say "nfc0=$(ash "test -e /sys/class/nfc/nfc0 && echo present || echo MISSING") char=$(ash 'test -e /dev/nq-nci && echo PRESENT || echo gone')"
	ash 'svc power stayon false' || true
	say "LOG=$LOG DETAIL=$DETAIL"
	exit "$rc"
}
trap cleanup EXIT INT TERM

say "preconditions"
[ "$(adb get-state)" = device ] || { echo "phone not on adb" >&2; exit 2; }
adb root >/dev/null; sleep 3; adb wait-for-device
bc=$(ash 'getprop sys.boot_completed'); bat=$(ash 'cat /sys/class/power_supply/qcom-battery/capacity')
echo "boot_completed=$bc battery=$bat% uname=$(ash 'uname -v')"
[ "$bc" = 1 ] || { echo "not fully booted" >&2; exit 2; }
[ "$bat" -ge 30 ] || { echo "battery below 30%" >&2; exit 2; }
[ -e "$HAL" ] && [ -e "$MOD" ] && { [ -z "$LIB" ] || [ -e "$LIB" ]; } && \
	{ [ -z "$STUB" ] || [ -e "$STUB" ]; } || { echo "HAL/module/lib/stub missing" >&2; exit 2; }
echo "nfc0 before: $(ash 'test -e /sys/class/nfc/nfc0 && echo present || echo MISSING')"
echo "driver before: $(ash "readlink -f /sys/bus/i2c/devices/$DEV/driver" || true)"
echo "nci config files:"
ash 'ls -l /system/etc/libnfc* /vendor/etc/libnfc* 2>&1' | tr '\n' ';'
save_settings

# 1. char driver into the running kernel (nfchal's proven procedure)
say "insert pn5xx-raw module"
run "mkdir -p $REMOTE"
adb push "$MOD" "$REMOTE/pn5xx-raw.ko" >/dev/null
adb push "$HAL" "$REMOTE/$HALNAME" >/dev/null
[ -z "$LIB" ] || adb push "$LIB" "$REMOTE/$LIBNAME" >/dev/null
run "chmod 755 $REMOTE/$HALNAME"
ash "echo $DEV > /sys/bus/i2c/drivers/$NXPDRV/unbind"
bound=0
sleep 1
if out=$(ash "timeout 30 insmod $REMOTE/pn5xx-raw.ko pn5xx_raw=1 2>&1"); then
	echo "insmod: ok $out"
	inserted=1
else
	echo "insmod FAILED or timed out: $out" >&2
	bound=1
	exit 3
fi
sleep 1
for node in /dev/nq-nci /dev/pn5xx /dev/pn54x; do
	echo "$node: $(ash "test -e $node && echo present || echo MISSING")"
done
echo "driver after: $(ash "readlink -f /sys/bus/i2c/devices/$DEV/driver" || true)"

# 2. make the NFC feature visible to PackageManager without remounting
say "bind-mount /vendor/etc/permissions with android.hardware.nfc.xml"
ash "rm -rf $REMOTE/permissions; mkdir -p $REMOTE/permissions"
ash "cp -a $PERMS/. $REMOTE/permissions/"
adb push "$ROOT/lineageos-24-mainline/device/zte/axon7m/nfc/feature-android.hardware.nfc.xml" \
	"$REMOTE/permissions/android.hardware.nfc.xml" >/dev/null
ash "mount -o bind $REMOTE/permissions $PERMS" || { echo "bind mount failed" >&2; exit 4; }
mounted=1
echo "feature file: $(ash "ls -l $PERMS/android.hardware.nfc.xml")"

# 3. start our HAL by hand (an init rc for real builds is in nfc/)
say "start $HALNAME"
if [ -n "$STUB" ]; then
	adb push "$STUB" "$REMOTE/$STUBNAME" >/dev/null
	echo "test-only VINTF shim: $(sha256sum "$STUB" | awk '{print $1}')"
fi
ash "rm -f $REMOTE/hal.log $REMOTE/hal.pid"
ash "export LD_LIBRARY_PATH=$REMOTE; export LD_PRELOAD=$STUBENV; nohup $REMOTE/$HALNAME >$REMOTE/hal.log 2>&1 & echo \$! >$REMOTE/hal.pid"
sleep 2
hal_pid=$(ash "cat $REMOTE/hal.pid")
echo "HAL pid=$hal_pid"
for i in $(seq 1 10); do
	ash 'service list' | grep -i 'android.hardware.nfc' && break
	sleep 1
done
ash 'service list' | grep -i 'android.hardware.nfc' || echo "NO NFC SERVICE registered" >&2
say "HAL log at start"
ash "cat $REMOTE/hal.log" > "$DETAIL/hal-start.txt" || true
cat "$DETAIL/hal-start.txt"

# 4. restart framework so PackageManager rescans the feature and NfcService
#    connects to the HAL. This is a soft restart: adb stays up.
say "restart system_server (no reboot)"
ss_pid=$(ash 'pidof system_server' | awk '{print $1}')
echo "system_server pid=$ss_pid"
[ -n "$ss_pid" ] || { echo "no system_server" >&2; exit 5; }
framework_restarted=1
adb logcat -b all -v threadtime > "$DETAIL/logcat-all.txt" &
logcat_pid=$!
ash "kill -9 $ss_pid"
for i in $(seq 1 120); do
	sleep 2
	bc=$(ash 'getprop sys.boot_completed' 2>/dev/null)
	[ "$bc" = 1 ] && break
done
echo "boot_completed after framework restart=$bc (waited $((i*2))s)"
[ "$bc" = 1 ] || { echo "framework did not come back" >&2; exit 6; }
adb root >/dev/null 2>&1; sleep 2; adb wait-for-device
sleep 10

say "dumpsys nfc (before enable)"
ash 'dumpsys nfc' > "$DETAIL/dumpsys-before.txt" || true
head -60 "$DETAIL/dumpsys-before.txt"

say "svc nfc enable"
run 'svc nfc enable'
sleep 20
ash 'dumpsys nfc' > "$DETAIL/dumpsys-enabled.txt" || true
head -80 "$DETAIL/dumpsys-enabled.txt"
echo "settings nfc_on=$(ash 'settings get global nfc_on')"

say "NFC logcat"
grep -i -E 'NfcService|NfcAdaptation|NfcApplication|nfc-service.axon7m|NFC-HAL|pn5xx|nq-nci' \
	"$DETAIL/logcat-all.txt" | tail -200 > "$DETAIL/logcat-nfc.txt" || true
cat "$DETAIL/logcat-nfc.txt"

say "svc nfc disable"
run 'svc nfc disable'
sleep 8
ash 'dumpsys nfc' > "$DETAIL/dumpsys-disabled.txt" || true
head -60 "$DETAIL/dumpsys-disabled.txt"

say "HAL log at end"
ash "cat $REMOTE/hal.log" > "$DETAIL/hal-end.txt" || true
cat "$DETAIL/hal-end.txt"
say "kernel dmesg"
adb shell dmesg | grep -i -E 'pn5xx|nq-nci|nfc' | tail -60 > "$DETAIL/dmesg.txt" || true
cat "$DETAIL/dmesg.txt"
exit 0
