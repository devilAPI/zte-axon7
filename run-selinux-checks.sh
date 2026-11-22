#!/bin/bash
# Unattended feature + AVC check on the main phone after a LineageOS 24 boot.
# Must be run while holding ~/.cache/axon7-phone-7e15695a.lock with
# ANDROID_SERIAL=7e15695a.  No playback, no vibrator, no torch.
set -u
N=${1:?usage: run-selinux-checks.sh RUNNAME [LOGFILE]}
LOG=${2:-"$HOME/Documents/GitHub/zte-axon7/ios/logs/selinux-$N-checks.txt"}
IOS=${IOS_DIR:-$HOME/Documents/GitHub/zte-axon7/ios}
S=${ANDROID_SERIAL:?set ANDROID_SERIAL}
mkdir -p "$(dirname "$LOG")"
exec >"$LOG" 2>&1

say() { echo "== $* ($(date +%FT%T))"; }
adb() { command adb -s "$S" "$@"; }
shell() { timeout 60 adb shell "$@" 2>&1 | tr -d '\r'; }
waitboot() {
	local i
	for i in $(seq 1 180); do
		[ "$(shell getprop sys.boot_completed)" = 1 ] && return 0
		[ "$(adb get-state 2>/dev/null)" = device ] || return 1
		sleep 5
	done
	return 1
}

say "waiting for LineageOS"
waitboot || { echo "NO ADB/BOOT_COMPLETED"; exit 2; }
timeout 30 adb root >/dev/null 2>&1 || true
sleep 4
adb wait-for-device || true
timeout 30 adb shell svc power stayon true >/dev/null 2>&1 || true
sleep 5

say "SELinux state"
shell 'cat /sys/fs/selinux/enforce; getprop | grep -i selinux; cat /proc/cmdline'
say "dmesg and logcat"
timeout 120 adb shell dmesg > "${LOG%.txt}-dmesg.txt" 2>&1 || true
timeout 300 adb logcat -d -b all > "${LOG%.txt}-logcat.txt" 2>&1 || true
wc -l "${LOG%.txt}-dmesg.txt" "${LOG%.txt}-logcat.txt"
say "AVC counts and distinct denied tuples"
for f in "${LOG%.txt}-dmesg.txt" "${LOG%.txt}-logcat.txt"; do
	echo "-- $f: $(grep -ac 'avc:' "$f") AVC lines"
done
cat "${LOG%.txt}-dmesg.txt" "${LOG%.txt}-logcat.txt" | grep -a 'avc:' |
	sed -E 's/.*avc:  denied  \{ ([^}]*) \} for .* scontext=u:r:([^:]+):s0 tcontext=u:object_r:([^:]+):s0 tclass=([^ ]+).*/\1 | \2 -> \3:\4/' |
	sort | uniq -c | sort -rn | head -80
say "display, touch, battery"
shell 'dumpsys display | grep -iE "DisplayDeviceInfo|mDisplayEnabled|state=" | head -8; dumpsys SurfaceFlinger --display-id 2>/dev/null | head -4; getevent -il 2>/dev/null | grep -i -A3 "synaptics\|rmi" | head -12; dumpsys battery | head -8; cat /sys/class/leds/lcd-backlight/brightness'
timeout 60 adb exec-out screencap -p > "${LOG%.txt}-screen.png" 2>/dev/null || true
say "Wi-Fi scan"
shell 'cmd wifi set-wifi-enabled enabled 2>&1; sleep 6; cmd wifi status 2>&1 | head -4; cmd wifi start-scan 2>&1; sleep 10; cmd wifi list-scan-results 2>&1 | head -12'
say "Bluetooth"
shell 'svc bluetooth enable 2>&1; sleep 6; dumpsys bluetooth_manager | grep -iE "enabled|state:|name:" | head -6'
say "Sensors"
[ -x "$IOS/research/axon7/bin/sensread" ] && timeout 30 adb push "$IOS/research/axon7/bin/sensread" /data/local/tmp/ >/dev/null 2>&1 || true
shell 'dumpsys sensorservice | grep -E "^[0-9a-fx]+\)|Total [0-9]+ h/w sensors" | head -12; [ -x /data/local/tmp/sensread ] && timeout 20 /data/local/tmp/sensread 2 2>&1'
say "Audio capture (no playback)"
shell 'rm -f /data/local/tmp/selinux-mic.wav; timeout 20 tinycap /data/local/tmp/selinux-mic.wav -D 0 -d 0 -c 2 -r 48000 -b 16 -p 960 -n 4 -T 3 2>&1 | tail -3; ls -l /data/local/tmp/selinux-mic.wav 2>&1'
say "Modem, camera, LED"
shell 'for s in /sys/bus/msm_subsys/devices/*; do echo "$(cat $s/name 2>/dev/null) $(cat $s/state 2>/dev/null)"; done; getprop gsm.version.baseband; dumpsys media.camera | grep -iE "Number of camera|Camera [0-9]|facing" | head -12; ls -l /sys/class/leds/ | head -20'
say "finishing"
shell 'svc power stayon false; cat /sys/class/power_supply/qcom-battery/capacity; getprop sys.boot_completed'
echo "checks done ($(date +%FT%T))"
