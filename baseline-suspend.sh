#!/bin/bash
# Short baseline suspend on the MAIN phone (current LineageOS 24 kernel).
# Run under the main-phone flock only.  Never writes partitions.
set -u
cd "$(dirname "$0")"
S=7e15695a
LOG="baseline-suspend-$(date +%Y%m%d).log"
exec > >(tee -a "$LOG") 2>&1
A() { adb -s "$S" "$@"; }
say() { echo "=== $* $(date +%FT%T%z)"; }
say "start baseline"
A get-state
A root >/dev/null 2>&1; sleep 2; A wait-for-device
A shell 'uname -r; uname -v; cat /sys/class/power_supply/qcom-battery/uevent | grep -E "CAPACITY|CURRENT|STATUS|VOLTAGE"'
A shell 'mount -t debugfs debugfs /sys/kernel/debug 2>/dev/null; ls /sys/kernel/debug/qcom_stats 2>&1; for f in /sys/kernel/debug/qcom_stats/*; do [ -f "$f" ] && echo "$f=$(cat "$f")"; done' || true
A shell 'for c in /sys/devices/system/cpu/cpu0/cpuidle/state*; do echo "$(cat $c/name) use=$(cat $c/usage)"; done'
A shell 'cat /sys/power/suspend_stats/success; cat /sys/power/suspend_stats/fail; cat /sys/class/rtc/rtc0/wakealarm'
say "suspend 30 s"
A shell 'echo 0 > /sys/class/rtc/rtc0/wakealarm; echo +30 > /sys/class/rtc/rtc0/wakealarm; echo mem > /sys/power/state; echo resumed-at=$(date +%s); echo 0 > /sys/class/rtc/rtc0/wakealarm' || echo "suspend command rc=$?"
say "after resume"
A get-state || true
A shell 'cat /sys/power/suspend_stats/success; cat /sys/power/suspend_stats/fail; cat /sys/kernel/debug/suspend_stats/last_success 2>/dev/null; grep -E "\[(0|1)\] " /sys/kernel/debug/suspend_stats/last_success 2>/dev/null | head -20' || true
A shell 'for c in /sys/devices/system/cpu/cpu0/cpuidle/state*; do echo "$(cat $c/name) use=$(cat $c/usage)"; done'
A shell 'for f in /sys/kernel/debug/qcom_stats/*; do [ -f "$f" ] && echo "$f=$(cat "$f")"; done' || true
A shell 'cat /sys/class/power_supply/qcom-battery/uevent | grep -E "CAPACITY|CURRENT|STATUS|VOLTAGE"'
A shell 'svc power stayon false' || true
say "end baseline"
