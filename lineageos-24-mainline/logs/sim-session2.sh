#!/bin/bash
# Locked session 2, 2026-11-21: UIM config, DMS UIM state, power-on retry.
export ANDROID_SERIAL=7e15695a
set -x
adb get-state
adb root >/dev/null
adb wait-for-device
echo "== DMS 0x44 UIM GET_STATE =="
adb shell 'timeout 12 /data/local/tmp/qmi-raw 2 0x44'
echo "== UIM 0x3a GET_CONFIGURATION =="
adb shell 'timeout 12 /data/local/tmp/qmi-raw 11 0x3a'
echo "== UIM 0x3a with configuration mask 1 =="
adb shell 'timeout 12 /data/local/tmp/qmi-raw 11 0x3a 10 04 01 00 00 00'
echo "== UIM 0x31 POWER_ON slot 1 (only if card status still error) =="
adb shell 'timeout 12 /data/local/tmp/qmi-raw 11 0x31 01 01 01'
sleep 3
echo "== UIM 0x2f after power-on =="
adb shell 'timeout 12 /data/local/tmp/qmi-raw 11 0x2f'
echo "== DMS 0x44 after power-on =="
adb shell 'timeout 12 /data/local/tmp/qmi-raw 2 0x44'
echo "== stayoff =="
adb shell 'svc power stayon false'
adb get-state
