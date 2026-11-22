#!/bin/bash
# Runtime IPA test on MAIN phone: no reboot, no partition writes.
# Aborts unless the phone is in LOS 24 with root, modem running, no IPA node.
set -u
export ANDROID_SERIAL=7e15695a
M=/home/devilapi/axon7-kbuild/ipa-modtest
OUT="/media/devilapi/Secondary HDD 2TB/ai-worker/axon7/ipa-phone-evidence"
mkdir -p "$OUT"
LOG="$OUT/test-$(date +%Y%m%d-%H%M%S).log"
log() { echo "$(date -Is) $*" | tee -a "$LOG"; }
die() { log "FAIL: $*"; exit 1; }
sh() { adb shell "$@" | tr -d '\r'; }

log "start; kernel $(sh uname -r); boot_completed=$(sh getprop sys.boot_completed); battery=$(sh cat /sys/class/power_supply/qcom-battery/capacity)"
[ "$(adb get-state 2>/dev/null)" = device ] || die "phone not in adb device state"
[ "$(sh getprop sys.boot_completed)" = 1 ] || die "boot_completed != 1"
[ "$(sh id -u)" = 0 ] || die "no adb root"
batt=$(sh cat /sys/class/power_supply/qcom-battery/capacity)
[ "$batt" -ge 30 ] || die "battery $batt below 30"
case "$(sh uname -r)" in 7.3.1-axon7m*) ;; *) die "unexpected kernel" ;; esac
mss=""
for d in $(sh 'ls -d /sys/class/remoteproc/remoteproc*'); do
  st=$(sh cat "$d/state")
  log "remoteproc $(sh cat "$d/name") = $st"
  [ "$(sh cat "$d/name")" = 2080000.remoteproc ] && mss=$st
done
[ "$mss" = running ] || die "modem remoteproc not running: refusing IPA probe"
[ -z "$(sh 'ls /sys/bus/platform/devices/680000.ipa 2>/dev/null')" ] || die "IPA node already present"
sh dmesg > "$OUT/dmesg-before.txt"

log "push test modules"
adb push "$M/ipa-dt-test.ko" "$M/ipa2-lite.ko" /data/local/tmp/ >/dev/null 2>&1 || adb push "$M/ipa-dt-test.ko" /data/local/tmp/ipa-dt-test.ko >/dev/null || die "push overlay failed"
if [ ! -s "$M/ipa2-lite.ko" ]; then die "no module"; fi
adb push "$M/ipa2-lite.ko" /data/local/tmp/ipa2-lite.ko >/dev/null || die "push ipa failed"

log "apply DT overlay"
sh 'insmod /data/local/tmp/ipa-dt-test.ko' 2>&1 | tee -a "$LOG"
sleep 2
sh dmesg | grep -i 'ipa-dt-test' | tail -5 | tee -a "$LOG"
[ -n "$(sh 'ls /sys/bus/platform/devices/680000.ipa 2>/dev/null')" ] || die "overlay did not create IPA node"
log "IPA node properties: $(sh cat /sys/bus/platform/devices/680000.ipa/compatible 2>/dev/null), bam_remote=$(sh cat /sys/bus/platform/devices/680000.ipa/qcom,bam-remote-mode 2>/dev/null)"

log "probe in test_mode=1 (no QMI/modem handshake)"
sh 'insmod /data/local/tmp/ipa2-lite.ko test_mode=1' 2>&1 | tee -a "$LOG"
sleep 4
sh dmesg > "$OUT/dmesg-testmode.txt"
sh 'ip -o link' > "$OUT/links-testmode.txt"
sh dmesg | tail -30 | tee -a "$LOG"
cat "$OUT/links-testmode.txt" | tee -a "$LOG"
sh 'cat /proc/modules | grep ipa' | tee -a "$LOG"
if ! grep -q 'rmnet_ipa0' "$OUT/links-testmode.txt"; then
  log "test_mode probe did not create rmnet_ipa0; skipping full mode"
else
  log "test_mode probe created rmnet_ipa0"
  log "unload test-mode module (ipa_remove is a no-op when QMI was not set up)"
  sh 'rmmod ipa2_lite' 2>&1 | tee -a "$LOG"
  sleep 2
  sh 'rmmod ipa_dt_test' 2>&1 | tee -a "$LOG"
  sleep 1
  log "re-apply overlay and load full module"
  sh 'insmod /data/local/tmp/ipa-dt-test.ko' 2>&1 | tee -a "$LOG"
  sleep 1
  sh 'insmod /data/local/tmp/ipa2-lite.ko' 2>&1 | tee -a "$LOG"
  sleep 8
  sh dmesg > "$OUT/dmesg-full.txt"
  sh 'ip -o link' > "$OUT/links-full.txt"
  for f in feature/rx_offload feature/tx_offload; do echo "$f=$(sh cat /sys/bus/platform/devices/680000.ipa/$f 2>/dev/null)"; done | tee -a "$LOG"
  cat "$OUT/links-full.txt" | tee -a "$LOG"
  sh dmesg | tail -40 | tee -a "$LOG"
  sh 'cat /proc/modules | grep -E "ipa|qmi|rmnet"' | tee -a "$LOG"
fi

log "final state: boot_completed=$(sh getprop sys.boot_completed) kernel=$(sh uname -r) battery=$(sh cat /sys/class/power_supply/qcom-battery/capacity) adb=$(adb get-state 2>/dev/null)"
sh 'svc power stayon false' 2>/dev/null || true
log "done"
