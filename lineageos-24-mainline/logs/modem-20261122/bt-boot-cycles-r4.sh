#!/bin/bash
# 15 consecutive LineageOS 24 boots of build 52 (EFS shadow), with a
# Bluetooth on/off cycle and modem fatal-error check after every boot.
# Run under the main-phone lock:
#   flock -w 21600 ~/.cache/axon7-phone-7e15695a.lock \
#     lineageos-24-mainline/logs/modem-20261122/bt-boot-cycles-r4.sh 7e15695a 15
#
# Read-only on all phone partitions (including EFS and los_boot). Only modem
# remoteproc0 is started by the image's own rmtfs service (we never stop or
# restart it by hand); the SLPI is never touched. No sound, no vibration.
# Raw dmesg copies stay in this untracked log directory (they may contain
# Wi-Fi scan names); only sanitised counts go into PLAN.md.
set -uo pipefail
S=${1:?phone serial}
N=${2:-15}
BASE=$(cd "$(dirname "$0")" && pwd)
OUT=$BASE/bt-cycles-r4-$(date +%Y%m%d-%H%M)
mkdir -p "$OUT"
A() { adb -s "$S" "$@"; }
rsh() { A shell "$@"; }
say() { echo "[$(date +%T)] $*" | tee -a "$OUT/host.log"; }

wait_los() {
  local st=none i j booted=0
  for i in $(seq 1 72); do                      # up to 12 min for adb
    st=$(A get-state 2>/dev/null || true)
    case $st in
      device) booted=1; break ;;
      recovery) if [ "$i" -le 3 ]; then say "TWRP: rebooting to LineageOS"; A reboot >/dev/null 2>&1 || true; fi ;;
    esac
    sleep 10
  done
  [ "$booted" = 1 ] || { say "no adb device after 12 min (state=$st); abort"; return 1; }
  A root >/dev/null 2>&1; sleep 3
  timeout 30 A wait-for-device >/dev/null 2>&1 || true
  for j in $(seq 1 96); do                      # up to 8 min for boot_completed
    [ "$(rsh getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] && return 0
    sleep 5
  done
  say "boot_completed was not 1 within 8 min; abort"; return 1
}

say "serial=$S cycles=$N out=$OUT"
wait_los || exit 1
boot_sha=$(A exec-out 'sha1sum /dev/block/bootdevice/by-name/los_boot' 2>/dev/null | tr -d '\r' | cut -d' ' -f1)
say "los_boot sha1 (read only)=$boot_sha"
bat=$(rsh cat /sys/class/power_supply/qcom-battery/capacity | tr -d '\r')
say "battery=$bat%"
[ "$bat" -ge 30 ] || { say "battery below 30%; abort"; exit 1; }

for c in $(seq 1 "$N"); do
  before_up=$(rsh cut -d. -f1 /proc/uptime | tr -d '\r')
  say "=== cycle $c/$N: uptime=${before_up}s ==="
  bat=$(rsh cat /sys/class/power_supply/qcom-battery/capacity | tr -d '\r')
  [ "$bat" -ge 30 ] || { say "battery=$bat% below 30%; abort"; exit 1; }
  name=$(rsh cat /sys/class/remoteproc/remoteproc0/name | tr -d '\r')
  rpstate=$(rsh cat /sys/class/remoteproc/remoteproc0/state | tr -d '\r')
  case "$name" in *2080000*) ;; *) say "remoteproc0 is not the modem ($name); abort"; exit 1 ;; esac
  rmtfs=$(rsh pgrep -a rmtfs | tr '\n' ';' | tr -d '\r')
  case "$rmtfs" in *'/data/vendor/axon7m-efs'*) shadow=1 ;; *) shadow=0 ;; esac
  files=$(rsh 'ls /data/vendor/axon7m-efs 2>/dev/null | wc -l' | tr -d '\r')
  {
    echo "battery=$bat% remoteproc0=$name state=$rpstate rmtfs=$rmtfs shadow_files=$files"
    echo "$(rsh uname -v | tr -d '\r')"
  } > "$OUT/cycle-$c-info.txt"
  rsh 'dmesg > /data/local/tmp/modem-r4-dmesg.txt'
  A pull /data/local/tmp/modem-r4-dmesg.txt "$OUT/cycle-$c-dmesg.txt" >/dev/null 2>&1 || { say "dmesg pull failed"; exit 1; }
  fatals=$(grep -c 'fatal error received' "$OUT/cycle-$c-dmesg.txt" || true)
  sfr=$(grep -c 'SFR Init' "$OUT/cycle-$c-dmesg.txt" || true)
  qca=$(grep -c 'QCA reset after the address change' "$OUT/cycle-$c-dmesg.txt" || true)
  bt_fail=$(grep -c -E 'Opcode 0x0c03 failed|hci0:.*-110|QCA no reset answer' "$OUT/cycle-$c-dmesg.txt" || true)
  rsh 'dmesg -C' >/dev/null 2>&1

  timeout 25 rsh 'svc bluetooth enable' 2>&1 | tr -d '\r' | sed "s/^/[$(date +%T)] BT-enable /" | tee -a "$OUT/host.log"
  on=0; d=none
  for i in $(seq 1 12); do
    d=$(timeout 20 rsh dumpsys bluetooth_manager 2>/dev/null | grep -m1 -i '^  State:' | tr -d '\r')
    case "$d" in *ON*) on=1; break ;; esac
    sleep 3
  done
  rsh 'dmesg > /data/local/tmp/modem-r4-dmesg-after.txt'
  A pull /data/local/tmp/modem-r4-dmesg-after.txt "$OUT/cycle-$c-dmesg-after.txt" >/dev/null 2>&1 || true
  fatals2=$(grep -c 'fatal error received' "$OUT/cycle-$c-dmesg-after.txt" || true)
  qca2=$(grep -c 'QCA reset after the address change' "$OUT/cycle-$c-dmesg-after.txt" || true)
  bt_fail2=$(grep -c -E 'Opcode 0x0c03 failed|hci0:.*-110|QCA no reset answer' "$OUT/cycle-$c-dmesg-after.txt" || true)
  detail="cycle=$c boot_completed=1 battery=$bat% shadow=$shadow files=$files modem=$rpstate fatals=$fatals sfr=$sfr qca_reset=$qca bt_fail=$bt_fail bt_on=$on fatals_after_bt=$fatals2 qca_after_bt=$qca2 bt_fail_after_bt=$bt_fail2 state=${d:-none}"
  say "$detail"
  echo "$detail" >> "$OUT/summary.txt"
  timeout 25 rsh 'svc bluetooth disable' >/dev/null 2>&1 || true
  rsh 'svc power stayon false' >/dev/null 2>&1 || true
  [ "$shadow" = 1 ] && [ "$files" -ge 4 ] || { say "EFS shadow missing in cycle $c"; exit 1; }
  [ "$fatals" = 0 ] && [ "$fatals2" = 0 ] || { say "modem fatal in cycle $c"; exit 1; }
  [ "$bt_fail" = 0 ] && [ "$bt_fail2" = 0 ] || { say "Bluetooth HCI failure in cycle $c"; exit 1; }
  [ "$on" = 1 ] || { say "Bluetooth did not turn on in cycle $c"; exit 1; }
  [ "$c" = "$N" ] && break
  say "rebooting for cycle $((c+1))"
  A reboot >/dev/null 2>&1 || { say "adb reboot failed"; exit 1; }
  # Do not let a still-connected pre-reboot adbd count as the next boot.
  for k in $(seq 1 30); do
    st=$(A get-state 2>/dev/null || true)
    case $st in device) sleep 2 ;; *) break ;; esac
  done
  wait_los || exit 1
  after_up=$(rsh cut -d. -f1 /proc/uptime | tr -d '\r')
  if [ "$after_up" -ge "$before_up" ] 2>/dev/null; then
    say "uptime did not reset (${before_up}s -> ${after_up}s): the reboot did not happen; abort"
    exit 1
  fi
done

end_sha=$(A exec-out 'sha1sum /dev/block/bootdevice/by-name/los_boot' 2>/dev/null | tr -d '\r' | cut -d' ' -f1)
{
  echo "boot_sha_start=$boot_sha"
  echo "boot_sha_end=$end_sha"
  rsh 'dumpsys bluetooth_manager 2>/dev/null | grep -m1 -i "^  State:"; cat /sys/class/remoteproc/remoteproc0/state; cat /sys/class/power_supply/qcom-battery/capacity; getprop sys.boot_completed; pgrep -a rmtfs' | tr -d '\r'
} | tee "$OUT/final.txt"
say "=== summary ($(wc -l < "$OUT/summary.txt") cycles) ==="
cat "$OUT/summary.txt"
say "done; phone left in LineageOS with adb"
