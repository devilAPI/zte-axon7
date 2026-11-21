#!/bin/bash
set -u
export ANDROID_SERIAL=7e15695a
cd "/media/devilapi/Secondary HDD 2TB/ai-worker/axon7/radio/lineageos-24-mainline/logs"
adb shell dumpsys telephony.registry > radio-dumpsys-raw.tmp
# Redact anything that could be an identifier before keeping the log.
sed -E 's/[0-9]{10,}/[REDACTED]/g; s/[0-9a-fA-F]{12,}/[REDACTED]/g' radio-dumpsys-raw.tmp > radio-dumpsys-redacted.txt
rm -f radio-dumpsys-raw.tmp
{
echo "== $(date -u +%FT%TZ) matching fields (redacted dump)"
grep -aE -i 'baseband|imei|deviceid|simstate|cardstate|uicc|slot' radio-dumpsys-redacted.txt | head -40
echo "-- DMS Get Revision --"
adb shell /data/local/tmp/qmi-raw 2 0x23 2>&1 | head -8
adb shell svc power stayon false
} > radio-dumpsys-probe.txt 2>&1
