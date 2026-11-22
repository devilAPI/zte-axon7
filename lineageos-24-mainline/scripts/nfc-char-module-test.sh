#!/bin/bash
# Root-only, no-reboot proof of the gated PN5xx raw NFC char driver.
#
#   ./nfc-char-module-test.sh /path/to/pn5xx-raw.ko /path/to/axon7-nfc-char-test
#
# Runs under the main phone's flock session. It only unbinds the running
# nxp-nci_i2c I2C client, inserts the char driver as a module, exercises NCI
# core reset/init through /dev/nq-nci, and rebinds nxp-nci on exit. It never
# writes boot/misc/persist/EFS/modem and needs no test kernel or reboot.
set -uo pipefail
export ANDROID_SERIAL=7e15695a
H="/media/devilapi/Secondary HDD 2TB/ai-worker/axon7"
MOD=${1:?module path}
CLI=${2:?client binary path}
LOG=$H/nfchal-char-module-$(date -u +%Y%m%dT%H%M%SZ).log
mkdir -p "$H/nfchal-logs"
LOG=$H/nfchal-logs/$(basename "$LOG")
exec > >(tee "$LOG") 2>&1
SERIAL=$ANDROID_SERIAL
DEV=3-0028
NXPDRV=nxp-nci_i2c
MODNAME=pn5xx-raw
remote=/data/local/tmp
bound=0 inserted=0

say() { echo "== $(date -u +%FT%TZ) $*"; }
ash() { adb shell "$@" | tr -d '\r'; }

cleanup() {
	local rc=$?
	say "cleanup (rc=$rc)"
	# A timed-out insmod may still have left the module loaded; always try
	# to unload it by name, never by file name (commit dea4b69).
	if ash 'grep -q "^pn5xx_raw " /proc/modules' >/dev/null 2>&1; then
		ash "timeout 20 rmmod pn5xx_raw" || true
	fi
	if [ $bound = 1 ] || ash 'grep -q "^pn5xx_raw " /proc/modules' >/dev/null 2>&1; then
		ash "timeout 20 sh -c 'echo $DEV > /sys/bus/i2c/drivers/$NXPDRV/bind'" || true
	fi
	sleep 2
	say "nfc0 after cleanup: $(ash "test -e /sys/class/nfc/nfc0 && echo present || echo MISSING")"
	say "char device after cleanup: $(ash "test -e /dev/nq-nci && echo PRESENT || echo gone")"
	ash "svc power stayon false" || true
	say "boot_completed=$(ash 'getprop sys.boot_completed') battery=$(ash 'cat /sys/class/power_supply/qcom-battery/capacity')%"
	say "LOG=$LOG"
}
trap cleanup EXIT INT TERM

say "preconditions"
[ "$(adb get-state)" = device ] || { echo "phone not on adb" >&2; exit 2; }
adb root >/dev/null; sleep 3; adb wait-for-device
bc=$(ash 'getprop sys.boot_completed'); bat=$(ash 'cat /sys/class/power_supply/qcom-battery/capacity')
echo "boot_completed=$bc battery=$bat%"
[ "$bc" = 1 ] || { echo "not fully booted" >&2; exit 2; }
[ "$bat" -ge 30 ] || { echo "battery below 30%" >&2; exit 2; }
[ -e "$MOD" ] && [ -e "$CLI" ] || { echo "module/client missing" >&2; exit 2; }
echo "uname: $(ash 'uname -v')"
echo "driver before: $(ash "readlink -f /sys/bus/i2c/devices/$DEV/driver" || true)"
echo "nfc0 before: $(ash 'test -e /sys/class/nfc/nfc0 && echo present || echo MISSING')"

D0=$(adb shell dmesg | wc -l)
echo "DMESG_START=$D0"
adb push "$MOD" "$remote/pn5xx-raw.ko" >/dev/null
adb push "$CLI" "$remote/axon7-nfc-char-test" >/dev/null
ash "chmod 755 $remote/axon7-nfc-char-test"

say "unbind $DEV from $NXPDRV"
ash "echo $DEV > /sys/bus/i2c/drivers/$NXPDRV/unbind"
bound=0
sleep 1
echo "nfc0 after unbind: $(ash 'test -e /sys/class/nfc/nfc0 && echo PRESENT || echo gone')"

say "insert $MODNAME"
ash "timeout 20 rmmod pn5xx_raw 2>/dev/null || true"	# a previous failed attempt may still be loaded
# The level IRQ can be asserted while the old driver is being unbound; bound
# insmod attempts happened on 2026-11-22, so never let one block the test.
if out=$(ash "timeout 30 insmod $remote/pn5xx-raw.ko pn5xx_raw=1 2>&1"); then
	echo "insmod: ok $out"
	inserted=1
else
	echo "insmod FAILED or timed out: $out" >&2
	# Rebind before giving up (cleanup does it through $bound, set it here).
	bound=1
	exit 3
fi
sleep 1
for node in /dev/nq-nci /dev/pn5xx /dev/pn54x; do
	echo "$node: $(ash "test -e $node && echo present || echo MISSING")"
done
echo "driver after: $(ash "readlink -f /sys/bus/i2c/devices/$DEV/driver" || true)"

say "NCI core reset/init through /dev/nq-nci"
ash "timeout 20 $remote/axon7-nfc-char-test /dev/nq-nci"; trc=$?
echo "client exit=$trc"

say "new dmesg"
adb shell dmesg | tail -n +$((D0 + 1)) | grep -i -E 'pn5xx|nq-nci|nfc|i2c|gpio' | tail -80 || true

# Restore the kernel stack before releasing the phone lock.
if [ $inserted = 1 ]; then
	ash "timeout 20 rmmod pn5xx_raw" || true
	inserted=0
fi
ash "timeout 20 sh -c 'echo $DEV > /sys/bus/i2c/drivers/$NXPDRV/bind'" || true
bound=1
sleep 2
echo "nfc0 after rebind: $(ash 'test -e /sys/class/nfc/nfc0 && echo present || echo MISSING')"
exit $trc
