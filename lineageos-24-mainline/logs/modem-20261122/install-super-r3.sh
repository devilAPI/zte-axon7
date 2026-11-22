#!/bin/bash
# Install a LineageOS 24 build that only changes the dynamic partitions
# (system/vendor) on the MAIN phone, without touching the boot image.
# Run under the shared main-phone lock:
#   flock -w 7200 ~/.cache/axon7-phone-7e15695a.lock \
#     lineageos-24-mainline/logs/modem-20261122/install-super-r3.sh 7e15695a 52
#
# The boot partition is only READ and its sha1 recorded; if LineageOS does not
# boot within 8 min the saved los_boot is restored from TWRP (byte-identical)
# and the script stops. No modem/SLPI restart, no sound or vibration.
set -uo pipefail
S=${1:?phone serial}; N=${2:?build number}
R=$(cd "$(dirname "$0")/../../.." && pwd)
IOS=$(realpath "$R/ios")
SRC=$IOS/research/los24-build-$N
OLD=$IOS/research/los24-build-51/super.img
SUPER=$SRC/super.img
OUT=$R/lineageos-24-mainline/logs/modem-20261122/install-$N-$(date +%Y%m%d-%H%M)
mkdir -p "$OUT"
A() { adb -s "$S" "$@"; }
rsh() { A shell "$@"; }
say() { echo "[$(date +%T)] $*" | tee -a "$OUT/host.log"; }
dev() { rsh "for b in /sys/class/block/*; do grep -q '^PARTNAME=$1\$' \$b/uevent 2>/dev/null && echo /dev/block/\${b##*/}; done; true" | tr -d '\r' | head -1; }
state() { A get-state 2>/dev/null || true; }
waitstate() { local want=$1 secs=$2 i; for i in $(seq 1 "$secs"); do [ "$(state)" = "$want" ] && return 0; sleep 2; done; return 1; }

say "serial=$S build=$N src=$SRC out=$OUT"
[ -f "$SUPER" ] || { say "no $SUPER"; exit 1; }
[ -f "$OLD" ] || { say "no delta base $OLD"; exit 1; }
[ "$(sha256sum < "$OLD" | cut -d' ' -f1)" = "$(awk '{print $2}' "$IOS/research/axon7/super-on-phone" | head -1)" ] ||
  { say "the phone does not hold the expected delta base (super-on-phone mismatch)"; exit 1; }

case $(state) in
  device)
    say "LineageOS: rebooting to TWRP"
    A root >/dev/null 2>&1; sleep 3
    A reboot recovery >/dev/null || { say "adb reboot recovery failed"; exit 1; }
    waitstate recovery 180 || { say "no TWRP after 6 min"; exit 1; }
    ;;
  recovery) say "already in TWRP" ;;
  *) say "phone not on adb (state $(state)); abort"; exit 1 ;;
esac

lb=$(dev los_boot); sd=$(dev system)
[ -n "$lb" ] && [ -n "$sd" ] || { say "no los_boot/system by-name partition (lb=$lb sd=$sd)"; exit 1; }
say "los_boot=$lb system=$sd"
# Save the boot image before any write, and verify the copy by sha1.
A exec-out "dd if=$lb bs=1M 2>/dev/null" > "$OUT/los-before.img" || { say "los_boot read failed"; exit 1; }
boot_sha=$(sha1sum < "$OUT/los-before.img" | cut -d' ' -f1)
# TWRP has no sha1sum on this build: read the partition back and hash locally.
read_sha=$(A exec-out "dd if=$lb bs=1M 2>/dev/null" | sha1sum | cut -d' ' -f1)
[ "$boot_sha" = "$read_sha" ] || { say "los_boot copy sha1 mismatch ($boot_sha vs $read_sha)"; exit 1; }
printf '%s  %s\n' "$boot_sha" "$lb" > "$OUT/los-before.sha1"
say "los_boot saved: sha1=$boot_sha size=$(stat -c %s "$OUT/los-before.img")"

say "writing super.img (system=$sd) with $OLD as delta base"
python3 -I "$IOS/tools/axon7-simg-put.py" "$SUPER" "$sd" --adb "adb -s $S" --base "$OLD" 2>&1 | tee "$OUT/simg-put.log" ||
  { say "super image write failed; boot image was NOT touched"; exit 1; }
printf '%s %s\n' "$SUPER" "$(sha256sum < "$SUPER" | cut -d' ' -f1)" > "$IOS/research/axon7/super-on-phone"

say "rebooting into LineageOS (boot image unchanged)"
A reboot >/dev/null || { say "adb reboot failed"; exit 1; }
ok=0
for i in $(seq 1 240); do   # 8 min
  if [ "$(state)" = device ]; then
    A root >/dev/null 2>&1; sleep 2; A wait-for-device >/dev/null 2>&1 || true
    if [ "$(rsh getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; then ok=1; break; fi
  fi
  sleep 2
done
if [ $ok != 1 ]; then
  say "boot_completed was not 1 within 8 min (state $(state)); restoring saved los_boot from TWRP"
  if [ "$(state)" != recovery ]; then say "phone is not in TWRP; no kernel was written, stopping"; exit 2; fi
  A push "$OUT/los-before.img" /tmp/los-before.img >/dev/null 2>&1 || { say "push of saved boot failed"; exit 2; }
  A shell "dd if=/tmp/los-before.img of=$lb bs=1M 2>/dev/null; sync" >/dev/null
  back=$(A exec-out "dd if=$lb bs=1M 2>/dev/null" | sha1sum | cut -d' ' -f1)
  say "restored los_boot sha1=$back (expected $boot_sha)"
  [ "$back" = "$boot_sha" ] && A reboot >/dev/null
  exit 2
fi

say "boot completed; verifying the new rmtfs service"
{
  echo "boot_completed=$(rsh getprop sys.boot_completed | tr -d '\r')"
  echo "battery=$(rsh cat /sys/class/power_supply/qcom-battery/capacity | tr -d '\r')%"
  echo "uptime=$(rsh cut -d. -f1 /proc/uptime | tr -d '\r')s"
  echo "rmtfs: $(rsh pgrep -a rmtfs | tr '\n' ' ' | tr -d '\r')"
  echo "shadow files:"; rsh 'ls -l /data/vendor/axon7m-efs' | tr -d '\r'
  echo "remoteproc0=$(rsh cat /sys/class/remoteproc/remoteproc0/name | tr -d '\r') state=$(rsh cat /sys/class/remoteproc/remoteproc0/state | tr -d '\r')"
  rsh 'dmesg' > "$OUT/dmesg.txt" 2>&1
  echo "fatal errors in dmesg: $(grep -c 'fatal error received' "$OUT/dmesg.txt" || true)"
  echo "SFR Init errors: $(grep -c 'SFR Init' "$OUT/dmesg.txt" || true)"
} 2>&1 | tee "$OUT/verify.txt"
rsh 'svc power stayon false' >/dev/null 2>&1 || true
say "done; phone left in LineageOS with adb"
