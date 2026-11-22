#!/bin/bash
# Controlled A/B probe for the LineageOS 24 modem restart loop.
# Run under the main-phone flock, from this worktree:
#   flock -w 21600 ~/.cache/axon7-phone-7e15695a.lock \
#     lineageos-24-mainline/logs/modem-20261122/efs-shadow-ab.sh 7e15695a
#
# Only remoteproc0 (2080000.remoteproc = MODEM) is stopped/started. Never SLPI,
# never ADSP. The real EFS partitions are only ever read (ro-control uses
# rmtfs -r; the writable probe uses COPIES under /data). No sound/vibration.
set -uo pipefail
S=${1:?phone serial}
OUT=$(cd "$(dirname "$0")" && pwd)/results-$(date +%Y%m%d-%H%M)
mkdir -p "$OUT"
A() { adb -s "$S" "$@"; }
say() { echo "[$(date +%T)] $*" | tee -a "$OUT/host.log"; }
rsh() { A shell "$@"; }

say "serial=$S out=$OUT"
st=$(A get-state 2>/dev/null || true)
[ "$st" = device ] || { say "phone is not in LineageOS (adb state $st); abort"; exit 1; }
A root >/dev/null 2>&1; sleep 3; A wait-for-device
[ "$(rsh getprop sys.boot_completed | tr -d '\r')" = 1 ] || { say "boot not completed"; exit 1; }
bat=$(rsh cat /sys/class/power_supply/qcom-battery/capacity | tr -d '\r')
say "battery=$bat%"
[ "$bat" -ge 30 ] || { say "battery below 30%; abort"; exit 1; }
name=$(rsh cat /sys/class/remoteproc/remoteproc0/name | tr -d '\r')
say "remoteproc0=$name"
case "$name" in *2080000*) ;; *) say "remoteproc0 is not the modem; abort"; exit 1 ;; esac
rsh "dmesg > /data/local/tmp/modem-ab-before.txt" || true
A pull /data/local/tmp/modem-ab-before.txt "$OUT/before-dmesg.txt" >/dev/null 2>&1 || true
rsh "pgrep -a rmtfs; cat /sys/class/remoteproc/remoteproc0/state; uptime" >> "$OUT/before.txt" 2>&1

# Start one test rmtfs. $1 = "ro-control" | "rw-shadow" | "ro-shadow"
start_rmtfs() {
  local mode=$1
  rsh "stop rmtfs" >/dev/null 2>&1
  sleep 2
  rsh "kill -9 \$(pgrep -x rmtfs) 2>/dev/null" >/dev/null 2>&1
  sleep 1
  case $mode in
    ro-control)
      rsh "setsid nohup /vendor/bin/rmtfs -o /dev/block/by-name -P -r -s >/data/local/tmp/modem-ab-rmtfs.log 2>&1 </dev/null &"
      ;;
    rw-shadow|ro-shadow)
      # Copies only. The real modemst1/2, fsg and fsc partitions stay untouched.
      rsh "mkdir -p /data/vendor/axon7m-efs; for p in modemst1:modem_fs1 modemst2:modem_fs2 fsg:modem_fsg fsc:modem_fsc; do b=\${p%%:*}; f=\${p#*:}; [ -f /data/vendor/axon7m-efs/\$f ] || dd if=/dev/block/by-name/\$b of=/data/vendor/axon7m-efs/\$f bs=4096 2>/dev/null; chmod 660 /data/vendor/axon7m-efs/\$f; done; ls -l /data/vendor/axon7m-efs > /data/local/tmp/modem-ab-efs-files.txt"
      if [ "$mode" = rw-shadow ]; then
        rsh "setsid nohup /vendor/bin/rmtfs -o /data/vendor/axon7m-efs -s >/data/local/tmp/modem-ab-rmtfs.log 2>&1 </dev/null &"
      else
        rsh "setsid nohup /vendor/bin/rmtfs -o /data/vendor/axon7m-efs -r >/data/local/tmp/modem-ab-rmtfs.log 2>&1 </dev/null &"
      fi
      ;;
  esac
  sleep 4
  rsh "pgrep -a rmtfs" >> "$OUT/$mode.txt" 2>&1
}

restore() {
  say "restoring the image's rmtfs service"
  rsh "kill -9 \$(pgrep -x rmtfs) 2>/dev/null" >/dev/null 2>&1
  sleep 1
  rsh "start rmtfs" >/dev/null 2>&1
  sleep 5
  rsh "pgrep -a rmtfs; cat /sys/class/remoteproc/remoteproc0/state" >> "$OUT/restore.txt" 2>&1
  say "after restore: $(tr '\n' ' ' < "$OUT/restore.txt")"
}

trap restore EXIT

for mode in ro-control rw-shadow ro-shadow; do
  say "=== mode $mode ==="
  start_rmtfs "$mode"
  for round in 1 2 3; do
    name=$(rsh cat /sys/class/remoteproc/remoteproc0/name | tr -d '\r')
    case "$name" in *2080000*) ;; *) say "remoteproc0 is not the modem ($name); abort"; exit 1 ;; esac
    rsh "echo stop > /sys/class/remoteproc/remoteproc0/state" >/dev/null 2>&1
    sleep 4
    rsh "dmesg -C" >/dev/null 2>&1
    t0=$(rsh cut -d. -f1 /proc/uptime | tr -d '\r')
    rsh "echo start > /sys/class/remoteproc/remoteproc0/state" >/dev/null 2>&1
    sleep 75
    t1=$(rsh cut -d. -f1 /proc/uptime | tr -d '\r')
    rsh "dmesg > /data/local/tmp/modem-ab-dmesg.txt"
    A pull /data/local/tmp/modem-ab-dmesg.txt "$OUT/$mode-$round-dmesg.txt" >/dev/null 2>&1
    fatals=$(grep -c 'fatal error received' "$OUT/$mode-$round-dmesg.txt" || true)
    first=$(grep -m1 -o 'fatal error received: .*' "$OUT/$mode-$round-dmesg.txt" || true)
    state=$(rsh cat /sys/class/remoteproc/remoteproc0/state | tr -d '\r')
    line="$mode round $round: fatals=$fatals in $((t1-t0))s state=$state ${first}"
    say "$line"
    echo "$line" >> "$OUT/summary.txt"
    sleep 5
  done
done

say "done; summary:"
cat "$OUT/summary.txt" | tee -a "$OUT/host.log"
