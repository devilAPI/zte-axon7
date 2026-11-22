#!/bin/bash
# 15 consecutive LineageOS 24 boots of build 52 (EFS shadow), with a
# Bluetooth on/off cycle and modem fatal-error check after every boot.
# Run under the main-phone lock:
#   flock -w 21600 ~/.cache/axon7-phone-7e15695a.lock \
#     lineageos-24-mainline/logs/modem-20261122/bt-boot-cycles-r5.sh 7e15695a 15
#
# Fixes over r4: the Bluetooth state must be exactly ON (BLE_TURNING_ON is
# not ON), and a new boot is identified by /proc/sys/kernel/random/boot_id,
# not by adb get-state (which can stay "device" across an adb reboot).
#
# Read-only on all phone partitions (including EFS and los_boot). Only the
# image's own rmtfs service starts modem remoteproc0; SLPI is never touched.
# No sound, no vibration. Raw dmesg stays in this untracked log directory.
set -uo pipefail
S=${1:?phone serial}
N=${2:-15}
BASE=$(cd "$(dirname "$0")" && pwd)
OUT=$BASE/bt-cycles-r5-$(date +%Y%m%d-%H%M)
mkdir -p "$OUT"
A() { adb -s "$S" "$@"; }
rsh() { A shell "$@" 2>&1 | tr -d '\r'; }
say() { echo "[$(date +%T)] $*" | tee -a "$OUT/host.log"; }
bootid() { A exec-out cat /proc/sys/kernel/random/boot_id 2>/dev/null | tr -d '\r'; }
btstate() { rsh 'dumpsys bluetooth_manager' | grep -m1 -i '^ *State:' | sed -E 's/^ *State: *//I' | head -1; }

say "serial=$S cycles=$N out=$OUT"
[ "$(A get-state 2>/dev/null)" = device ] || { say "phone not on adb"; exit 1; }
A root >/dev/null 2>&1; sleep 3
[ "$(rsh getprop sys.boot_completed)" = 1 ] || { say "boot not completed"; exit 1; }
boot_sha=$(A exec-out 'sha1sum /dev/block/bootdevice/by-name/los_boot' 2>/dev/null | tr -d '\r' | cut -d' ' -f1)
say "los_boot sha1 (read only)=$boot_sha"
bat0=$(rsh cat /sys/class/power_supply/qcom-battery/capacity)
say "battery=$bat0% bootid=$(bootid)"
[ "$bat0" -ge 30 ] || { say "battery below 30%; abort"; exit 1; }

wait_new_boot() {
  local old=$1 i bid bc st
  for i in $(seq 1 120); do          # up to 10 min
    st=$(A get-state 2>/dev/null || true)
    if [ "$st" = device ]; then
      A root >/dev/null 2>&1; sleep 1
      bid=$(bootid); bc=$(rsh getprop sys.boot_completed)
      if [ -n "$bid" ] && [ "$bid" != "$old" ] && [ "$bc" = 1 ]; then return 0; fi
    fi
    sleep 5
  done
  say "no new boot_id with boot_completed=1 within 10 min (state=$st, bootid=$(bootid))"
  return 1
}

for c in $(seq 1 "$N"); do
  bid=$(bootid)
  up=$(rsh cut -d. -f1 /proc/uptime)
  say "=== cycle $c/$N: bootid=$bid uptime=${up}s ==="
  bat=$(rsh cat /sys/class/power_supply/qcom-battery/capacity)
  [ "$bat" -ge 30 ] || { say "battery=$bat% below 30%; abort"; exit 1; }
  name=$(rsh cat /sys/class/remoteproc/remoteproc0/name)
  rpstate=$(rsh cat /sys/class/remoteproc/remoteproc0/state)
  case "$name" in *2080000*) ;; *) say "remoteproc0 is not the modem ($name); abort"; exit 1 ;; esac
  rmtfs=$(rsh pgrep -a rmtfs | tr '\n' ';')
  case "$rmtfs" in *'/data/vendor/axon7m-efs'*) shadow=1 ;; *) shadow=0 ;; esac
  files=$(rsh 'ls /data/vendor/axon7m-efs 2>/dev/null | wc -l')
  {
    echo "battery=$bat% remoteproc0=$name state=$rpstate rmtfs=$rmtfs shadow_files=$files bootid=$bid"
    echo "$(rsh uname -v)"
  } > "$OUT/cycle-$c-info.txt"
  rsh 'dmesg > /data/local/tmp/modem-r5-dmesg.txt'
  A pull /data/local/tmp/modem-r5-dmesg.txt "$OUT/cycle-$c-dmesg.txt" >/dev/null 2>&1 || { say "dmesg pull failed"; exit 1; }
  fatals=$(grep -c 'fatal error received' "$OUT/cycle-$c-dmesg.txt" || true)
  sfr=$(grep -c 'SFR Init' "$OUT/cycle-$c-dmesg.txt" || true)
  qca=$(grep -c 'QCA reset after the address change' "$OUT/cycle-$c-dmesg.txt" || true)
  bt_fail=$(grep -c -E 'Opcode 0x0c03 failed|hci0:.*-110|QCA no reset answer' "$OUT/cycle-$c-dmesg.txt" || true)
  rsh 'dmesg -C' >/dev/null 2>&1

  timeout 40 adb -s "$S" shell 'svc bluetooth enable' 2>&1 | tr -d '\r' | sed "s/^/[$(date +%T)] BT-enable /" | tee -a "$OUT/host.log"
  on=0; st=none
  for i in $(seq 1 40); do
    st=$(btstate)
    case "$st" in
      ON) on=1; break ;;
      *) say "cycle $c BT state after ${i}x2s: ${st:-none}" ;;
    esac
    sleep 2
  done
  rsh 'dmesg > /data/local/tmp/modem-r5-dmesg-after.txt'
  A pull /data/local/tmp/modem-r5-dmesg-after.txt "$OUT/cycle-$c-dmesg-after.txt" >/dev/null 2>&1 || true
  fatals2=$(grep -c 'fatal error received' "$OUT/cycle-$c-dmesg-after.txt" || true)
  qca2=$(grep -c 'QCA reset after the address change' "$OUT/cycle-$c-dmesg-after.txt" || true)
  bt_fail2=$(grep -c -E 'Opcode 0x0c03 failed|hci0:.*-110|QCA no reset answer' "$OUT/cycle-$c-dmesg-after.txt" || true)
  detail="cycle=$c bootid=$bid battery=$bat% shadow=$shadow files=$files modem=$rpstate fatals=$fatals sfr=$sfr qca_reset=$qca bt_fail=$bt_fail bt_on=$on bt_state=${st:-none} settings_on=$(rsh 'settings get global bluetooth_on') fatals_after_bt=$fatals2 qca_after_bt=$qca2 bt_fail_after_bt=$bt_fail2"
  say "$detail"
  echo "$detail" >> "$OUT/summary.txt"
  timeout 30 adb -s "$S" shell 'svc bluetooth disable' >/dev/null 2>&1 || true
  rsh 'svc power stayon false' >/dev/null 2>&1 || true
  [ "$shadow" = 1 ] && [ "$files" -ge 4 ] || { say "EFS shadow missing in cycle $c"; exit 1; }
  [ "$fatals" = 0 ] && [ "$fatals2" = 0 ] || { say "modem fatal in cycle $c"; exit 1; }
  [ "$bt_fail" = 0 ] && [ "$bt_fail2" = 0 ] || { say "Bluetooth HCI failure in cycle $c"; exit 1; }
  [ "$on" = 1 ] || { say "Bluetooth did not reach ON in cycle $c"; exit 1; }
  [ "$c" = "$N" ] && break
  say "rebooting for cycle $((c+1))"
  A reboot >/dev/null 2>&1 || { say "adb reboot failed"; exit 1; }
  wait_new_boot "$bid" || exit 1
done

end_sha=$(A exec-out 'sha1sum /dev/block/bootdevice/by-name/los_boot' 2>/dev/null | tr -d '\r' | cut -d' ' -f1)
{
  echo "boot_sha_start=$boot_sha"
  echo "boot_sha_end=$end_sha"
  rsh 'dumpsys bluetooth_manager 2>/dev/null | grep -m1 -i "^ *State:"; cat /sys/class/remoteproc/remoteproc0/state; cat /sys/class/power_supply/qcom-battery/capacity; getprop sys.boot_completed; pgrep -a rmtfs'
} | tee "$OUT/final.txt"
say "=== summary ($(wc -l < "$OUT/summary.txt") cycles) ==="
cat "$OUT/summary.txt"
say "done; phone left in LineageOS with adb"
