#!/bin/bash
# Locked session 4, 2026-11-21: GET_ATR with a slot TLV (read-only).
export ANDROID_SERIAL=7e15695a
set -x
adb get-state
adb root >/dev/null
adb wait-for-device
echo "== UIM 0x41 GET_ATR slot 1 =="
adb shell 'timeout 12 /data/local/tmp/qmi-raw 11 0x41 01 01 01'
echo "== UIM 0x41 GET_ATR slot 2 =="
adb shell 'timeout 12 /data/local/tmp/qmi-raw 11 0x41 01 01 02'
adb shell 'svc power stayon false'
adb get-state
