#!/bin/bash
# Bind-mount test of the newly built radio HAL on the MAIN phone.
# Does not remount /system or /vendor; restores the original binary and
# service on every exit path. No sound, no vibration, no partition writes.
set -u
export ANDROID_SERIAL=7e15695a
W='/media/devilapi/Secondary HDD 2TB/ai-worker/axon7/radio'
L="$W/lineageos-24-mainline/logs"
BIN="$W/lineageos-24-mainline/tmp-radio-test/radio-axon7m-new"
XML="$W/lineageos-24-mainline/tmp-radio-test/radio-axon7m.xml"
DEST=/vendor/bin/hw/android.hardware.radio-service.axon7m
XMDEST=/vendor/etc/vintf/manifest/radio-axon7m.xml
LOG="$L/radio-bindmount-test.txt"
# The image on the phone predates the messaging/voice V4 NDK libraries that
# the new binary links against; a temporary wrapper sets LD_LIBRARY_PATH to
# the copies pushed to /data/local/tmp (no /vendor remount, no partition write).
LIBS=(android.hardware.radio.messaging-V4-ndk.so android.hardware.radio.voice-V4-ndk.so)
MOUNTED=0; XMLMOUNTED=0; STARTED=0
restore() {
  echo "-- restore $(date -u +%T)" >> "$LOG"
  [ "$STARTED" = 1 ] && adb shell setprop ctl.stop vendor.radio-axon7m >> "$LOG" 2>&1
  [ "$XMLMOUNTED" = 1 ] && adb shell umount "$XMDEST" >> "$LOG" 2>&1
  [ "$MOUNTED" = 1 ] && adb shell umount "$DEST" >> "$LOG" 2>&1
  adb shell setprop ctl.start vendor.radio-axon7m >> "$LOG" 2>&1
  sleep 8
  # Rebind com.android.phone to the original HAL after the new process died.
  adb shell am crash com.android.phone >> "$LOG" 2>&1
  sleep 30
  adb shell svc power stayon false >> "$LOG" 2>&1
  echo "-- restored radio services: $(adb shell 'service list | grep -i radio' | wc -l)" >> "$LOG"
  echo "-- restored: svc=$(adb shell getprop init.svc.vendor.radio-axon7m | tr -d '\r') stay_on=$(adb shell settings get global stay_on_while_plugged_in | tr -d '\r') reach=$(adb shell echo OK | tr -d '\r')" >> "$LOG"
}
trap restore EXIT
{
echo "== $(date -u +%FT%TZ) radio bind-mount test"
echo "-- battery --"; adb shell cat /sys/class/power_supply/qcom-battery/capacity
adb root >/dev/null 2>&1
md5sum "$BIN"
adb push "$BIN" /data/local/tmp/radio-axon7m-test 2>&1 | tail -2
adb shell chmod 755 /data/local/tmp/radio-axon7m-test
for lib in "${LIBS[@]}"; do
  adb push "$W/lineageos-24-mainline/tmp-radio-test/$lib" "/data/local/tmp/$lib" >/dev/null 2>&1
  adb shell chcon u:object_r:vendor_file:s0 "/data/local/tmp/$lib"
done
adb push "$W/lineageos-24-mainline/tmp-radio-test/radio-wrapper.sh" /data/local/tmp/radio-wrapper.sh >/dev/null 2>&1
adb shell chmod 755 /data/local/tmp/radio-wrapper.sh
# Keep the bind-mounted file's label as it would be in a real image (the phone
# is permissive, but a future enforcing build must still work).
adb shell chcon u:object_r:hal_radio_default_exec:s0 /data/local/tmp/radio-wrapper.sh
adb shell "md5sum /data/local/tmp/radio-axon7m-test"
echo "-- stop old HAL --"; adb shell setprop ctl.stop vendor.radio-axon7m; sleep 2
echo "-- bind mount wrapper (LD_LIBRARY_PATH for the two new V4 libs) --"
adb shell "mount --bind /data/local/tmp/radio-wrapper.sh $DEST" && MOUNTED=1
if [ "$MOUNTED" != 1 ]; then echo "BIND MOUNT FAILED"; exit 3; fi
adb shell "md5sum $DEST"
if [ -f "$XML" ]; then
  adb push "$XML" /data/local/tmp/radio-axon7m.xml >/dev/null 2>&1
  adb shell chcon u:object_r:vendor_configs_file:s0 /data/local/tmp/radio-axon7m.xml
  adb shell "mount --bind /data/local/tmp/radio-axon7m.xml $XMDEST" && XMLMOUNTED=1
fi
echo "-- start new HAL --"; adb shell setprop ctl.start vendor.radio-axon7m; STARTED=1
sleep 12
echo "svc=$(adb shell getprop init.svc.vendor.radio-axon7m | tr -d '\r')"
adb shell logcat -b radio -c >/dev/null 2>&1
echo "-- restart phone process to rebind --"; adb shell am crash com.android.phone; sleep 35
echo "-- battery after --"; adb shell cat /sys/class/power_supply/qcom-battery/capacity
echo "-- service list (expect 7 radio services) --"; adb shell 'service list | grep -i radio' || true
echo "-- dumpsys telephony.registry --"
adb shell dumpsys telephony.registry | grep -E -i 'mRadioPowerState|mSignalStrength|mServiceState=|mDataConnectionState|mBasebandVersion' | head -10 | sed -E 's/[0-9]{10,}/[REDACTED]/g'
echo "-- identity fields present (count only, values never printed) --"
adb shell dumpsys telephony.registry | grep -c 'mDeviceId'
echo "-- HAL process --"
adb shell ps -A | grep radio-axon7m || true
echo "-- HAL log (redacted) --"
adb shell 'logcat -b radio -d -t 600' 2>/dev/null | grep -aE 'radio-axon7m|RILJ.*(radioStateChanged|SIM|signal|REGISTRATION)' | sed -E 's/[0-9]{10,}/[REDACTED]/g' | tail -60
echo "-- phone-process crashes --"
adb shell 'logcat -b events -d -t 300' 2>/dev/null | grep -aE 'am_crash|am_anr' | grep -a com.android.phone | tail -5 || true
echo "-- DMS operating mode --"; adb shell /data/local/tmp/qmi-raw 2 0x2d 2>&1 | grep -E 'result|TLV 0x01' | head -3
} > "$LOG" 2>&1
