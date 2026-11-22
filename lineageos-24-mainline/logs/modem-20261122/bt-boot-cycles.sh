#!/bin/bash
# 15 consecutive LineageOS 24 boots with a Bluetooth on/off cycle after each.
# Run under the main-phone flock:
#   flock -w 21600 ~/.cache/axon7-phone-7e15695a.lock \
#     lineageos-24-mainline/logs/modem-20261122/bt-boot-cycles.sh 7e15695a 15
#
# Evidence per boot: modem fatal count from dmesg, QCA reset-after-address
# message (kernel 0021), HCI reset failures, and Bluetooth ON state. No sound,
# no vibration. Leaves the phone in LineageOS with adb and the screen timeout
# restored.
set -uo pipefail
S=${1:?phone serial}
N=${2:-15}
OUT=$(cd "$(dirname "$0")" && pwd)/bt-cycles-$(date +%Y%m%d-%H%M)
mkdir -p "$OUT"
A() { adb -s "$S" "$@"; }
say() { echo "[$(date +%T)] $*" | tee -a "$OUT/host.log"; }
rsh() { A shell "$@"; }

wait_los() {
  local tries=$1 ok=0 st
  for i in $(seq 1 "$tries"); do
    st=$(A get-state 2>/dev/null || true)
    case $st in
      device) ok=1; break ;;
      recovery) [ $i -le 2 ] && { say "in TWRP: rebooting to LineageOS"; A reboot >/dev/null 2>&1 || true; } ;;
    esac
    sleep 10
  done
  [ $ok = 1 ] || { say "no adb device after $((tries*10)) s (state $st); abort"; return 1; }
  A root >/dev/null 2>&1; sleep 2; A wait-for-device
  local j
  for j in $(seq 1 60); do
    [ "$(rsh getprop sys.boot_completed | tr -d '\r')" = 1 ] && return 0
    sleep 5
  done
  say "boot not completed after 5 min"; return 1
}

say "serial=$S cycles=$N out=$OUT"
wait_los 60 || exit 1
bat=$(rsh cat /sys/class/power_supply/qcom-battery/capacity | tr -d '\r')
say "battery=$bat%"
[ "$bat" -ge 30 ] || { say "battery below 30%; abort"; exit 1; }

for c in $(seq 1 "$N"); do
  say "=== cycle $c/$N: uptime $(rsh cut -d. -f1 /proc/uptime | tr -d '\r')s ==="
  uname=$(rsh uname -v | tr -d '\r')
  name=$(rsh cat /sys/class/remoteproc/remoteproc0/name | tr -d '\r')
  case "$name" in *2080000*) ;; *) say "remoteproc0 is not the modem ($name); abort"; exit 1 ;; esac
  rsh "dmesg > /data/local/tmp/modem-bt-cycle.txt"
  A pull /data/local/tmp/modem-bt-cycle.txt "$OUT/cycle-$c-dmesg.txt" >/dev/null 2>&1
  fatals=$(grep -c 'fatal error received' "$OUT/cycle-$c-dmesg.txt" || true)
  qca_reset=$(grep -c 'QCA reset after the address change' "$OUT/cycle-$c-dmesg.txt" || true)
  bt_fail=$(grep -c -E 'Opcode 0x0c03 failed|hci0:.*-110|QCA no reset answer' "$OUT/cycle-$c-dmesg.txt" || true)
  rsh dmesg -C >/dev/null 2>&1
  # Turn Bluetooth on, then wait for the AOSP HAL to report ON.
  # timeout needs an executable; rsh is a shell function.
  timeout 20 adb -s "$S" shell 'svc bluetooth enable' >/dev/null 2>&1 || timeout 20 adb -s "$S" shell 'cmd bluetooth_manager enable' >/dev/null 2>&1 || true
  on=0
  for i in $(seq 1 12); do
    d=$(timeout 20 adb -s "$S" shell dumpsys bluetooth_manager 2>/dev/null | grep -m1 -i '^  State:' | tr -d '\r')
    case "$d" in *ON*) on=1; break ;; esac
    sleep 3
  done
  detail="cycle=$c uptime=$uname fatals=$fatals qca_reset_msgs=$qca_reset bt_fail_msgs=$bt_fail bt_on=$on state=${d:-none}"
  say "$detail"
  echo "$detail" >> "$OUT/summary.txt"
  timeout 20 adb -s "$S" shell 'svc bluetooth disable' >/dev/null 2>&1 || timeout 20 adb -s "$S" shell 'cmd bluetooth_manager disable' >/dev/null 2>&1 || true
  rsh 'svc power stayon false' >/dev/null 2>&1 || true
  rsh "dmesg > /data/local/tmp/modem-bt-cycle-after.txt"
  A pull /data/local/tmp/modem-bt-cycle-after.txt "$OUT/cycle-$c-dmesg-after.txt" >/dev/null 2>&1
  [ $on = 1 ] || { say "Bluetooth did not turn on in cycle $c"; break; }
  [ "$c" = "$N" ] && break
  say "rebooting for cycle $((c+1))"
  A reboot >/dev/null 2>&1 || { say "adb reboot failed"; exit 1; }
  wait_los 60 || exit 1
done

say "=== final state ==="
rsh 'dumpsys bluetooth_manager 2>/dev/null | grep -m1 -i "^  State:"; cat /sys/class/remoteproc/remoteproc0/state; cat /sys/class/power_supply/qcom-battery/capacity; getprop sys.boot_completed' | tee "$OUT/final.txt"
say "summary:"
cat "$OUT/summary.txt" | tee -a "$OUT/host.log"
