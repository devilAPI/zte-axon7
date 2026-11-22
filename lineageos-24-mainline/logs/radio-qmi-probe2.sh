#!/bin/bash
set -u
export ANDROID_SERIAL=7e15695a
cd "/media/devilapi/Secondary HDD 2TB/ai-worker/axon7/radio/lineageos-24-mainline/logs"
{
echo "== $(date -u +%FT%TZ) QMI registration probe"
q() { echo "-- $*"; adb shell /data/local/tmp/qmi-raw "$@" 2>&1 | head -8; }
q 2 0x2d
q 1 0x2d 10 04 00 00 00 00 00
q 5 0x01 10 01 00 01
q 11 0x2e 01 04 00 01 00 00 00
q 3 0x03 13 01 00 01 17 01 00 01 18 01 00 01 19 01 00 01
echo "== end"
} > radio-qmi-probe2.txt 2>&1
