#!/bin/bash
set -u
export ANDROID_SERIAL=7e15695a
cd "/media/devilapi/Secondary HDD 2TB/ai-worker/axon7/radio/lineageos-24-mainline/logs"
{
echo "== $(date -u +%FT%TZ) telephony identity/state probe (values redacted where personal)"
echo "-- baseband version --"; adb shell getprop gsm.version.baseband
echo "-- SIM state --"; adb shell dumpsys telephony.registry | grep -E -i 'mSimState|mCardState|CardState|simState' | grep -avE 'IccId|iccId' | head -12
echo "-- IMEI field present in framework registry (value not printed) --"
n=$(adb shell dumpsys telephony.registry | grep -c 'mDeviceId=' || true); echo "mDeviceId fields: $n"
echo "-- HAL process uptime --"; adb shell 'ps -A -o pid,etime,comm | grep radio-service' || true
adb shell svc power stayon false
echo "== end $(date -u +%FT%TZ)"
} > radio-telephony-probe2.txt 2>&1
