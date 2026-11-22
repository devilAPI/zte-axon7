#!/bin/bash
# Full IPA probe on MAIN phone (QMI enabled). No reboot, no partition writes.
set -u
export ANDROID_SERIAL=7e15695a
OUT="/media/devilapi/Secondary HDD 2TB/ai-worker/axon7/ipa-phone-evidence"
mkdir -p "$OUT"
LOG="$OUT/full-$(date +%Y%m%d-%H%M%S).log"
log() { echo "$(date -Is) $*" | tee -a "$LOG"; }
die() { log "FAIL: $*"; exit 1; }
sh() { adb shell "$@" | tr -d '\r'; }

[ "$(adb get-state 2>/dev/null)" = device ] || die "phone not in adb device state"
[ "$(sh getprop sys.boot_completed)" = 1 ] || die "boot_completed != 1"
[ "$(sh id -u)" = 0 ] || die "no adb root"
batt=$(sh cat /sys/class/power_supply/qcom-battery/capacity)
[ "$batt" -ge 30 ] || die "battery $batt below 30"
mss=$(sh 'cat /sys/class/remoteproc/remoteproc0/state')
[ "$mss" = running ] || die "modem not running"
log "preconditions OK: kernel=$(sh uname -r) battery=$batt modem=$mss"

log "unload test-mode module and overlay"
sh 'rmmod ipa2_lite' 2>&1 | tee -a "$LOG"
sleep 2
sh 'rmmod ipa_dt_test' 2>&1 | tee -a "$LOG"
sleep 1
sh 'cat /proc/modules | grep -E "ipa2|ipa_dt" || echo "test modules unloaded"' | tee -a "$LOG"
log "modem after test-mode unload: $(sh 'cat /sys/class/remoteproc/remoteproc0/state')"

log "apply overlay and load full driver"
sh 'insmod /data/local/tmp/ipa-dt-test.ko' 2>&1 | tee -a "$LOG"
sleep 2
sh 'insmod /data/local/tmp/ipa2-lite.ko' 2>&1 | tee -a "$LOG"
sleep 10
sh dmesg > "$OUT/dmesg-full.txt"
sh 'ip -o link' > "$OUT/links-full.txt"
sh 'cat /proc/modules' > "$OUT/modules-full.txt"
for f in feature/rx_offload feature/tx_offload; do echo "$f=$(sh cat /sys/bus/platform/devices/680000.ipa/$f 2>/dev/null)"; done | tee -a "$LOG"
cat "$OUT/links-full.txt" | tee -a "$LOG"
grep -iE 'ipa|qmi|rmnet|panic|call trace|reset' "$OUT/dmesg-full.txt" | tail -40 | tee -a "$LOG"
grep -E 'ipa2_lite|qmi_helpers|qcom_common|rmnet' "$OUT/modules-full.txt" | tee -a "$LOG"
log "post: boot_completed=$(sh getprop sys.boot_completed) kernel=$(sh uname -r) battery=$(sh cat /sys/class/power_supply/qcom-battery/capacity) adb=$(adb get-state 2>/dev/null)"
log "modem: $(sh 'cat /sys/class/remoteproc/remoteproc0/state')"
sh 'svc power stayon false' 2>/dev/null || true
log "done"
