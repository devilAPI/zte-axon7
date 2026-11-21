#!/bin/bash
# Locked session 3, 2026-11-21: read-only QMI probes for physical SIM presence.
export ANDROID_SERIAL=7e15695a
set -x
adb get-state
adb root >/dev/null
adb wait-for-device
for msg in 0x41 0x39 0x36 0x2e; do
  echo "== UIM $msg =="
  adb shell "timeout 12 /data/local/tmp/qmi-raw 11 $msg"
done
echo "== full regulator_summary (first 60 lines) =="
adb shell 'cat /sys/kernel/debug/regulator/regulator_summary 2>/dev/null | head -60 || cat /sys/kernel/debug/regulator_summary 2>/dev/null | head -60'
echo "== stayoff =="
adb shell 'svc power stayon false'
adb get-state
