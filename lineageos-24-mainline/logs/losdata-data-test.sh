#!/bin/bash
# Read-only mobile-data test on the MAIN phone: no boot/misc write, no reboot.
# Requires the main-phone flock, a built HAL in tmp-radio-test/, adb root and
# the running 7.3.1-axon7m (#31) kernel. IPA modules are insmod'ed only if
# rmnet_ipa0 is absent; they are the modules built by research/ipa-modtest on
# main against this exact kernel (vermagic checked before insmod).
set -u
export ANDROID_SERIAL=7e15695a
W=$(cd "$(dirname "$0")/.." && pwd)
T="$W/tmp-radio-test"
M=/home/devilapi/axon7-kbuild/ipa-modtest
L="$W/logs"
LOG="$L/losdata-data-test.txt"
BIN="$T/radio-axon7m-new"
XML="$T/radio-axon7m.xml"
DEST=/vendor/bin/hw/android.hardware.radio-service.axon7m
XMDEST=/vendor/etc/vintf/manifest/radio-axon7m.xml
LIBS=(android.hardware.radio.messaging-V4-ndk.so android.hardware.radio.voice-V4-ndk.so)
MOUNTED=0; XMLMOUNTED=0; STARTED=0
sh() { adb shell "$@" | tr -d '\r'; }
log() { echo "$(date -Is) $*" | tee -a "$LOG"; }
die() { log "FAIL: $*"; exit 1; }
restore() {
  echo "-- restore $(date -u +%T)" >> "$LOG"
  [ "$STARTED" = 1 ] && adb shell setprop ctl.stop vendor.radio-axon7m >> "$LOG" 2>&1
  [ "$XMLMOUNTED" = 1 ] && adb shell umount "$XMDEST" >> "$LOG" 2>&1
  [ "$MOUNTED" = 1 ] && adb shell umount "$DEST" >> "$LOG" 2>&1
  adb shell setprop ctl.start vendor.radio-axon7m >> "$LOG" 2>&1
  sleep 8
  adb shell am crash com.android.phone >> "$LOG" 2>&1
  sleep 25
  adb shell svc power stayon false >> "$LOG" 2>&1
  echo "-- restored: svc=$(sh getprop init.svc.vendor.radio-axon7m) reach=$(sh echo OK) stay_on=$(sh settings get global stay_on_while_plugged_in) radio_services=$(sh 'service list | grep -ci radio')" >> "$LOG"
}
trap restore EXIT
: > "$LOG"
: > "$L/losdata-hal-wds.txt"
: > "$L/losdata-wds-direct.txt"
: > "$L/losdata-dmesg.txt"
{
echo "== $(date -u +%FT%TZ) losdata: IPA + radio HAL data call (no SIM, no flashing)"
echo "-- battery: $(sh cat /sys/class/power_supply/qcom-battery/capacity)%"
[ "$(adb get-state 2>/dev/null)" = device ] || die "phone not in adb device state"
[ "$(sh getprop sys.boot_completed)" = 1 ] || die "boot_completed != 1 (no boot writes to restore)"
adb root >/dev/null 2>&1
[ "$(sh id -u)" = 0 ] || die "no adb root"
K=$(sh uname -r)
[ "$K" = 7.3.1-axon7m ] || die "unexpected kernel $K"
B=$(sh cat /sys/class/power_supply/qcom-battery/capacity)
[ "$B" -ge 30 ] || die "battery $B below 30"
[ "$(sh 'cat /sys/class/remoteproc/remoteproc0/state')" = running ] || die "mss not running"
log "preconditions OK: kernel=$K battery=$B battery-capacity=$B"

# note: sh() pipes through tr, so use adb's own exit status here
if ! adb shell 'ip link show rmnet_ipa0' >/dev/null 2>&1; then
  log "ipa2-lite: rmnet_ipa0 absent, loading test modules"
  for f in ipa-dt-test.ko ipa2-lite.ko; do
    [ -r "$M/$f" ] || die "missing $M/$f"
    v=$(modinfo -F vermagic "$M/$f")
    [ "$v" = "7.3.1-axon7m SMP preempt mod_unload aarch64" ] || die "vermagic $v for $f"
    adb push "$M/$f" "/data/local/tmp/$f" >/dev/null 2>&1 || die "push $f"
  done
  sh 'insmod /data/local/tmp/ipa-dt-test.ko' 2>&1 | tee -a "$LOG"
  sleep 2
  sh 'insmod /data/local/tmp/ipa2-lite.ko' 2>&1 | tee -a "$LOG"
  sleep 8
fi
sh 'ip -o link' | tee -a "$LOG"
[ -n "$(sh 'ip link show rmnet_ipa0' 2>/dev/null)" ] || die "rmnet_ipa0 still absent"
log "IPA module: $(sh 'grep ipa2_lite /proc/modules')"

# HAL under test
[ -r "$BIN" ] || die "missing $BIN (copy from server out/target/product/axon7m)"
md5sum "$BIN" | tee -a "$LOG"
adb push "$BIN" /data/local/tmp/radio-axon7m-test >/dev/null 2>&1 || die "push HAL"
sh chmod 755 /data/local/tmp/radio-axon7m-test
for lib in "${LIBS[@]}"; do
  adb push "$T/$lib" "/data/local/tmp/$lib" >/dev/null 2>&1 || die "push $lib"
  sh chcon u:object_r:vendor_file:s0 "/data/local/tmp/$lib"
done
adb push "$L/radio-test-wrapper.sh" /data/local/tmp/radio-wrapper.sh >/dev/null 2>&1
sh chmod 755 /data/local/tmp/radio-wrapper.sh
sh chcon u:object_r:hal_radio_default_exec:s0 /data/local/tmp/radio-wrapper.sh
if [ -f "$XML" ]; then
  adb push "$XML" /data/local/tmp/radio-axon7m.xml >/dev/null 2>&1
  sh chcon u:object_r:vendor_configs_file:s0 /data/local/tmp/radio-axon7m.xml
fi
log "-- stop stock HAL --"
sh setprop ctl.stop vendor.radio-axon7m
sleep 2
sh "mount --bind /data/local/tmp/radio-wrapper.sh $DEST" && MOUNTED=1
[ "$MOUNTED" = 1 ] || die "bind mount failed"
if [ -f "$XML" ]; then
  sh "mount --bind /data/local/tmp/radio-axon7m.xml $XMDEST" && XMLMOUNTED=1
fi
log "-- start test HAL --"
sh setprop ctl.start vendor.radio-axon7m
STARTED=1
sleep 12
[ "$(sh getprop init.svc.vendor.radio-axon7m)" = running ] || die "test HAL not running"
sh logcat -b radio -c >/dev/null 2>&1
sh am crash com.android.phone
sleep 30
log "-- trigger mobile data --"
sh 'svc data enable' 2>&1 | tee -a "$LOG"
sh 'cmd phone data enable' 2>&1 | tee -a "$LOG"
sleep 4
# RILJ does not place a data call without a SIM; the HAL's one-shot bring-up
# hook exercises the same setupDataCall/QMI WDS path instead.
sh 'setprop debug.axon7m.data_test 1'
sleep 12
sh 'settings get global mobile_data' | tee -a "$LOG"
sh 'dumpsys telephony.registry' | grep -E -i 'mRadioPowerState|mDataConnectionState|mServiceState=' | head -8 | sed -E 's/[0-9]{10,}/[REDACTED]/g' | tee -a "$LOG"
log "-- direct QMI WDS start network (independent of the framework) --"
if [ -r "$T/qmi-raw" ]; then
  adb push "$T/qmi-raw" /data/local/tmp/qmi-raw >/dev/null 2>&1
  sh chmod 755 /data/local/tmp/qmi-raw
fi
sh '/data/local/tmp/qmi-raw 1 0x22' 2>&1 | tee -a "$L/losdata-wds-direct.txt"
sh '/data/local/tmp/qmi-raw 1 0x20 140000190104' 2>&1 | tee -a "$L/losdata-wds-direct.txt"
sleep 2
log "-- HAL QMI WDS exchange --"
sh 'logcat -b radio -d -t 1200' 2>/dev/null | grep -aE 'radio-axon7m|RILJ.*(DATA|DATA_CALL|setupDataCall)' \
  | sed -E 's/[0-9]{10,}/[REDACTED]/g' | tail -120 | tee -a "$L/losdata-hal-wds.txt"
log "-- phone crashes --"
sh 'logcat -b events -d -t 500' 2>/dev/null | grep -aE 'am_crash|am_anr' | grep -a com.android.phone | tail -5 | tee -a "$LOG" || true
log "-- IPA/rmnet kernel log --"
sh dmesg | grep -iE 'ipa2|rmnet|qmi' | tail -30 | tee -a "$L/losdata-dmesg.txt"
log "-- final state --"
log "boot_completed=$(sh getprop sys.boot_completed) kernel=$(sh uname -r) battery=$(sh cat /sys/class/power_supply/qcom-battery/capacity) modem=$(sh 'cat /sys/class/remoteproc/remoteproc0/state')"
} > "$LOG" 2>&1
