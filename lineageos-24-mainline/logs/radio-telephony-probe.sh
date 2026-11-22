#!/bin/bash
# Read-only telephony evidence on the main phone (no partition writes, no sound).
set -u
export ANDROID_SERIAL=7e15695a
cd "/media/devilapi/Secondary HDD 2TB/ai-worker/axon7/radio/lineageos-24-mainline/logs"
{
echo "== $(date -u +%FT%TZ) telephony probe"
echo "-- battery --"; adb shell cat /sys/class/power_supply/qcom-battery/capacity
echo "-- radio service state --"; adb shell getprop init.svc.vendor.radio-axon7m
echo "-- declared radio services --"; adb shell 'service list | grep -i radio' || true
echo "-- telephony registry (filtered) --"
adb shell dumpsys telephony.registry | grep -E -i 'mSignalStrength|CellSignalStrength|mRegistrationState|mRegState|mSimState|mCardState|mBasebandVersion|mRadioPowerState|mDataConnectionState|mNetworkType|mServiceState|voiceCapable|smsCapable' | head -80
echo "-- HAL radio log (personal data redacted) --"
adb shell 'logcat -b radio -d -t 1200' 2>/dev/null | grep -aE 'radio-axon7m|radioHAL|RILJ|AndroidRuntime' | grep -avE 'FATAL EXCEPTION|Process: com.android.phone' | sed -E 's/[0-9]{15,}/[REDACTED]/g' | tail -80
echo "-- phone process crashes --"
adb shell 'logcat -b events -d -t 300' 2>/dev/null | grep -aE 'am_crash|am_anr' | grep -a com.android.phone | tail -10 || true
adb shell svc power stayon false
echo "stay_on=$(adb shell settings get global stay_on_while_plugged_in | tr -d '\r')"
echo "== end $(date -u +%FT%TZ)"
} > radio-telephony-probe.txt 2>&1
