#!/bin/bash
# Suspend measurement on the MAIN phone (LineageOS 24).  Run under the
# 7e15695a flock only.  $1 = alarm seconds (default 660 = 11 min).
# Collects RPM sleep stats, cpuidle usage and fuel-gauge state before/after.
set -u
cd "$(dirname "$0")"
S=7e15695a
SECS=${1:-660}
LOG="suspend-measure-$(date +%Y%m%d-%H%M).log"
exec > >(tee -a "$LOG") 2>&1
A() { adb -s "$S" "$@"; }
say() { echo "=== $* $(date +%FT%T%z)"; }
dump() {
	A shell 'mount -t debugfs debugfs /sys/kernel/debug 2>/dev/null
echo "-- uname: $(uname -r) $(uname -v)"
echo "-- uptime: $(cat /proc/uptime)"
echo "-- suspend_stats: success=$(cat /sys/power/suspend_stats/success) fail=$(cat /sys/power/suspend_stats/fail)"
echo "-- last_success:"; cat /sys/kernel/debug/suspend_stats/last_success 2>/dev/null | grep -E "^(freeze|suspend|resume|total|time)" || true
echo "-- sleep states: $(cat /sys/power/mem_sleep)"
echo "-- fg: $(cat /sys/class/power_supply/qcom-battery/uevent | grep -E "POWER_SUPPLY_(CAPACITY|CURRENT_NOW|VOLTAGE_NOW|STATUS|CHARGE_FULL_DESIGN)")"
echo "-- rtc: $(cat /sys/class/rtc/rtc0/since_epoch) alarm=$(cat /sys/class/rtc/rtc0/wakealarm)"
echo "-- qcom_stats:"
for f in /sys/kernel/debug/qcom_stats/*; do [ -f "$f" ] && echo "$(basename $f): $(tr "\n" " " < $f)"; done
echo "-- cpuidle:"
for c in /sys/devices/system/cpu/cpu0/cpuidle/state*; do echo "$(cat $c/name) use=$(cat $c/usage) time=$(cat $c/time)"; done
echo "-- master stats:"
for f in /sys/kernel/debug/qcom_rpm_master_stats/*/*; do [ -f "$f" ] && echo "$f: $(tr "\n" " " < $f)"; done
' 2>&1 || true
}
say "start: alarm ${SECS}s"
A get-state
A root >/dev/null 2>&1; sleep 2; A wait-for-device
dump
say "setting alarm and suspending"
A shell "echo 0 > /sys/class/rtc/rtc0/wakealarm; echo +$SECS > /sys/class/rtc/rtc0/wakealarm; cat /sys/class/rtc/rtc0/wakealarm; echo suspend-issued-at=\$(date +%s); echo mem > /sys/power/state" || echo "adb shell suspend rc=$? (USB drops at suspend entry)"
# adb usually drops when the gadget suspends; watch for offline then back online
gone=0; back=0
for i in $(seq 1 $((SECS / 3 + 60))); do
	st=$(A get-state 2>/dev/null || true)
	[ "$st" = device ] || gone=1
	if [ $gone = 1 ] && [ "$st" = device ]; then back=1; break; fi
	sleep 3
done
say "after suspend: gone=$gone back=$back"
A get-state || true
[ $back = 1 ] || { echo "PHONE NOT REACHABLE after suspend; boot menu must be checked" >&2; }
A root >/dev/null 2>&1; sleep 3; A wait-for-device
dump
say "wake reason / dmesg"
A shell 'dmesg | grep -E "PM: suspend (entry|exit)|rtc.*alarm|wakealarm|Freezing|Restarting" | tail -20' || true
say "post-wake device checks"
A shell 'echo "wifi: $(dumpsys wifi 2>/dev/null | grep -m1 -i "Wi-Fi is")"; echo "sim: $(getprop gsm.sim.state)"; echo "inputs: $(ls /dev/input/ | tr "\n" " ")"; echo "usb: $(getprop sys.usb.state)"; svc power stayon false; echo "wakealarm cleared:"; echo 0 > /sys/class/rtc/rtc0/wakealarm; cat /sys/class/rtc/rtc0/wakealarm' || true
say "end"
