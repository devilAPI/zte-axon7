#!/bin/bash
# Diagnose why the new radio HAL does not stay up under init. Bind-mount only
# (no /system or /vendor remount), restore the original HAL on every path.
set -u
export ANDROID_SERIAL=7e15695a
W='/media/devilapi/Secondary HDD 2TB/ai-worker/axon7/radio'
L="$W/lineageos-24-mainline/logs"
BIN="$W/lineageos-24-mainline/tmp-radio-test/radio-axon7m-new"
XML="$W/lineageos-24-mainline/tmp-radio-test/radio-axon7m.xml"
DEST=/vendor/bin/hw/android.hardware.radio-service.axon7m
XMDEST=/vendor/etc/vintf/manifest/radio-axon7m.xml
LOG="$L/radio-bindmount-diag.txt"
MOUNTED=0; XMLMOUNTED=0; STARTED=0
restore() {
  echo "-- restore $(date -u +%T)" >> "$LOG"
  [ "$STARTED" = 1 ] && adb shell setprop ctl.stop vendor.radio-axon7m >> "$LOG" 2>&1
  [ "$XMLMOUNTED" = 1 ] && adb shell umount "$XMDEST" >> "$LOG" 2>&1
  [ "$MOUNTED" = 1 ] && adb shell umount "$DEST" >> "$LOG" 2>&1
  adb shell setprop ctl.start vendor.radio-axon7m >> "$LOG" 2>&1
  sleep 8
  adb shell am crash com.android.phone >> "$LOG" 2>&1
  sleep 30
  adb shell svc power stayon false >> "$LOG" 2>&1
  echo "-- restored svc=$(adb shell getprop init.svc.vendor.radio-axon7m | tr -d '\r') services=$(adb shell 'service list | grep -i radio' | wc -l) stay_on=$(adb shell settings get global stay_on_while_plugged_in | tr -d '\r') reach=$(adb shell echo OK | tr -d '\r')" >> "$LOG"
}
trap restore EXIT
{
echo "== $(date -u +%FT%TZ) radio HAL startup diagnostic"
adb root >/dev/null 2>&1
adb push "$BIN" /data/local/tmp/radio-axon7m-test 2>&1 | tail -1
adb shell chcon u:object_r:hal_radio_default_exec:s0 /data/local/tmp/radio-axon7m-test
adb push "$XML" /data/local/tmp/radio-axon7m.xml >/dev/null 2>&1
adb shell chcon u:object_r:vendor_configs_file:s0 /data/local/tmp/radio-axon7m.xml
echo "-- V4 NDK libs on device --"
adb shell 'ls -l /vendor/lib64/android.hardware.radio.*-V4-ndk.so /system/lib64/android.hardware.radio.*-V4-ndk.so /apex/com.android.art/lib64/android.hardware.radio.*-V4-ndk.so 2>&1' | head -30
echo "-- stop old HAL --"; adb shell setprop ctl.stop vendor.radio-axon7m; sleep 2
adb shell "mount --bind /data/local/tmp/radio-axon7m-test $DEST" && MOUNTED=1
adb shell "mount --bind /data/local/tmp/radio-axon7m.xml $XMDEST" && XMLMOUNTED=1
adb shell logcat -b radio -c >/dev/null 2>&1
echo "-- start new HAL --"; adb shell setprop ctl.start vendor.radio-axon7m; STARTED=1
sleep 5
echo "svc=$(adb shell getprop init.svc.vendor.radio-axon7m | tr -d '\r')"
echo "ps:"; adb shell ps -A | grep radio || true
echo "services:"; adb shell 'service list | grep -i radio' || true
echo "-- radio logcat --"
adb shell 'logcat -b radio -d -t 400' 2>/dev/null | tail -80 | sed -E 's/[0-9]{10,}/[REDACTED]/g'
echo "-- main logcat (radio/debug) --"
adb shell 'logcat -b main -d -t 400' 2>/dev/null | grep -aiE 'radio-axon7m|DEBUG|fatal|abort|linker' | tail -40 | sed -E 's/[0-9]{10,}/[REDACTED]/g'
echo "-- direct foreground run (8s) --"
adb shell setprop ctl.stop vendor.radio-axon7m
adb shell 'timeout 8 /data/local/tmp/radio-axon7m-test' 2>&1 | tail -50 | sed -E 's/[0-9]{10,}/[REDACTED]/g'
echo "-- tombstones --"
adb shell 'ls -lt /data/tombstones/tombstone_* 2>/dev/null | head -3' || true
T=$(adb shell 'ls -t /data/tombstones/tombstone_* 2>/dev/null | head -1' | tr -d '\r')
if [ -n "$T" ]; then adb shell "head -45 $T" 2>&1 | sed -E 's/[0-9]{10,}/[REDACTED]/g'; fi
} > "$LOG" 2>&1
