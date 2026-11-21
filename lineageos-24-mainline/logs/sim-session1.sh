#!/bin/bash
# One locked phone session, 2026-11-21. Logs to stdout (redirected by caller).
export ANDROID_SERIAL=7e15695a
set -x
adb devices -l
state=$(adb get-state 2>&1)
echo "initial state: $state"
if [ "$state" = recovery ]; then
    adb reboot
    adb wait-for-device
fi
for i in $(seq 1 90); do
    b=$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
    [ "$b" = 1 ] && break
    sleep 2
done
echo "boot_completed=$b after ${i} polls"
adb root
adb wait-for-device
adb shell id
adb shell getprop ro.build.version.release
adb shell getprop gsm.version.baseband
adb shell getprop gsm.sim.state
echo "== battery =="
adb shell cat /sys/class/power_supply/qcom-battery/capacity
echo "== qrtr services =="
adb shell 'qrtr-lookup 2>/dev/null | sort -k1,1n | head -40'
echo "== push qmi-raw =="
adb push "$(dirname "$0")/qmi-raw" /data/local/tmp/qmi-raw
adb shell chmod 755 /data/local/tmp/qmi-raw
echo "== UIM 0x2f GET_CARD_STATUS =="
adb shell 'timeout 12 /data/local/tmp/qmi-raw 11 0x2f'
echo "== UIM 0x47 GET_SLOT_STATUS =="
adb shell 'timeout 12 /data/local/tmp/qmi-raw 11 0x47'
echo "== DMS 0x25 GET_IDS (IMEI TLV 0x11 deleted) =="
adb shell 'timeout 12 /data/local/tmp/qmi-raw 2 0x25' | sed -E '/TLV 0x11/d'
echo "== DMS 0x2e (possible UIM state) =="
adb shell 'timeout 12 /data/local/tmp/qmi-raw 2 0x2e'
echo "== NAS 0x24 serving system =="
adb shell 'timeout 12 /data/local/tmp/qmi-raw 3 0x24'
echo "== regulator summary (uim/sim) =="
adb shell 'cat /sys/kernel/debug/regulator/regulator_summary 2>/dev/null | grep -iE "uim|sim" || cat /sys/kernel/debug/regulator_summary 2>/dev/null | grep -iE "uim|sim" || echo none'
echo "== pinmux (uim) =="
adb shell 'grep -iR uim /sys/kernel/debug/pinctrl/ 2>/dev/null | head -20 || true'
echo "== stayoff =="
adb shell 'svc power stayon false'
adb shell settings get global stay_on_while_plugged_in
echo "== final state =="
adb get-state
