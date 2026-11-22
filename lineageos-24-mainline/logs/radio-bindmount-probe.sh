#!/bin/bash
# Re-run the new HAL with the extended VINTF fragment and inspect identity
# fields / declarations. Bind-mount only; restore the original HAL on exit.
set -u
export ANDROID_SERIAL=7e15695a
W='/media/devilapi/Secondary HDD 2TB/ai-worker/axon7/radio'
L="$W/lineageos-24-mainline/logs"
T="$W/lineageos-24-mainline/tmp-radio-test"
DEST=/vendor/bin/hw/android.hardware.radio-service.axon7m
XMDEST=/vendor/etc/vintf/manifest/radio-axon7m.xml
LOG="$L/radio-bindmount-probe.txt"
RAW="$L/radio-dumpsys-active.raw"
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
echo "== $(date -u +%FT%TZ) radio HAL active-state probe"
adb root >/dev/null 2>&1
for f in radio-axon7m-new android.hardware.radio.messaging-V4-ndk.so android.hardware.radio.voice-V4-ndk.so radio-axon7m.xml; do
  adb push "$T/$f" "/data/local/tmp/$f" >/dev/null 2>&1 || echo "PUSH FAILED $f"
done
adb push "$L/radio-test-wrapper.sh" /data/local/tmp/radio-wrapper.sh >/dev/null 2>&1 || echo "PUSH FAILED wrapper"
adb shell chmod 755 /data/local/tmp/radio-axon7m-test /data/local/tmp/radio-wrapper.sh
adb shell chcon u:object_r:hal_radio_default_exec:s0 /data/local/tmp/radio-wrapper.sh
adb shell chcon u:object_r:vendor_configs_file:s0 /data/local/tmp/radio-axon7m.xml
adb shell setprop ctl.stop vendor.radio-axon7m; sleep 2
adb shell "mount --bind /data/local/tmp/radio-wrapper.sh $DEST" && MOUNTED=1
adb shell "mount --bind /data/local/tmp/radio-axon7m.xml $XMDEST" && XMLMOUNTED=1
echo "-- mounted VINTF fragment: $(adb shell 'grep -c "<hal format" /vendor/etc/vintf/manifest/radio-axon7m.xml' | tr -d '\r') hal entries"
echo "-- mounts --"; adb shell 'mount | grep -E "radio-axon7m|radio-axon7m.xml"' | head -5
adb shell logcat -b radio -c >/dev/null 2>&1
adb shell setprop ctl.start vendor.radio-axon7m; STARTED=1
sleep 8
echo "svc=$(adb shell getprop init.svc.vendor.radio-axon7m | tr -d '\r')"
echo "process:"; adb shell ps -A | grep radio-axon7m || true
echo "services:"; adb shell 'service list | grep -i radio' || true
adb shell am crash com.android.phone
sleep 35
echo "-- HAL log --"
adb shell 'logcat -b radio -d -t 1000' 2>/dev/null | grep -a 'radio-axon7m' | tail -40
echo "-- framework identity / SIM requests (values redacted) --"
adb shell 'logcat -b radio -d -t 2000' 2>/dev/null | grep -aiE 'GET_IMEI|GET_BASEBAND_VERSION|GET_DEVICE_IDENTITY|GET_IMSI|ICC_CARD_STATUS|SIGNAL_STRENGTH' | sed -E 's/[0-9]{10,}/[REDACTED]/g' | tail -40
echo "-- telephony dump (raw, kept local only) --"
adb shell dumpsys telephony.registry > "$RAW" 2>&1
echo "dumpsys bytes $(wc -c < "$RAW")"
} > "$LOG" 2>&1
