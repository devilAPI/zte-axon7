#!/bin/bash
# Read-only probe of the main phone (radio task). No partition writes.
set -u
export ANDROID_SERIAL=7e15695a
cd "/media/devilapi/Secondary HDD 2TB/ai-worker/axon7/radio/lineageos-24-mainline/logs"
{
echo "== $(date -u +%FT%TZ) radio phone probe"
adb devices -l
echo "-- battery --"; adb shell cat /sys/class/power_supply/qcom-battery/capacity
echo "-- state --"; adb shell getprop sys.boot_completed; adb shell getprop ro.build.version.release
echo "-- radio services --"; adb shell 'service list | grep -i radio' || true
echo "-- qmi-raw on phone --"; adb shell ls -l /data/local/tmp/qmi-raw || true
echo "-- WMS supported messages 0x1e --"
adb shell /data/local/tmp/qmi-raw 5 0x1e 2>&1 | head -12
echo "-- WMS get SMSC 0x34 --"
adb shell /data/local/tmp/qmi-raw 5 0x34 2>&1 | head -12
echo "-- WMS get routes 0x33 --"
adb shell /data/local/tmp/qmi-raw 5 0x33 2>&1 | head -12
echo "-- VINTF radio manifest --"
adb shell 'cat /vendor/etc/vintf/manifest.xml; for f in /vendor/etc/vintf/manifest/*.xml; do echo --- $f; cat $f; done' 2>&1 | grep -E -B2 -A5 'radio|manifest version' | head -100
echo "== end $(date -u +%FT%TZ)"
} > radio-phone-probe.txt 2>&1
