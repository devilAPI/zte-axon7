#!/bin/bash
# Kernel-only NFC driver test on the main phone, with automatic rollback.
#
#   ./los24-nfc-kernel-test.sh /path/to/test-los-boot.img
#
# Run from a shell holding ~/.cache/axon7-phone-7e15695a.lock. The input is
# a *converted* (shim v2) boot image built from the current LOS boot.img with
# the test kernel and pn5xx_raw=1 in the kernel command line.
#
# Before writing anything, the phone's current los_boot is copied to the HDD
# and verified by sha1. If boot_completed is not 1 within 8 minutes, or the
# phone reappears in TWRP, that saved image and the original boot-menu block
# are written back automatically and the phone is rebooted into LOS.
set -uo pipefail
export ANDROID_SERIAL=7e15695a
H="/media/devilapi/Secondary HDD 2TB/ai-worker/axon7"
IMG=$(realpath "${1:?test los-boot.img}")
CLIENT=${2:-}	# optional NDK client to run once the test kernel is up
B=$H/nfchal-backups
mkdir -p "$B"
TS=$(date -u +%Y%m%dT%H%M%SZ)
SAVE=$B/los-boot-before-$TS.img
MISC=$B/misc-before-$TS.bin
LOG=$H/nfchal-logs/los24-nfc-kernel-$TS.log
mkdir -p "$(dirname "$LOG")"
exec > >(tee "$LOG") 2>&1
say() { echo "== $(date -u +%FT%TZ) $*"; }
ash() { adb shell "$@" | tr -d '\r'; }
dev() { adb shell "for b in /sys/class/block/*; do grep -q '^PARTNAME=$1\$' \$b/uevent 2>/dev/null && echo /dev/block/\${b##*/}; done; true" | tr -d '\r' | head -1; }
LB= MD= MB= remote=/data/local/tmp restored=0 flashed=0

restore() {
	local why=$1
	say "RESTORE: $why"
	[ -s "$SAVE" ] && [ -s "$MISC" ] || { echo "no verified backup; cannot restore" >&2; return 1; }
	remote=/data/local/tmp
	case $(adb get-state 2>/dev/null) in
		recovery) remote=/tmp ;;
		device) adb root >/dev/null 2>&1; sleep 3 ;;
		*) echo "phone not on adb; waiting for the watchdog/boot menu (up to 4 min)" ;;
	esac
	local i
	for i in $(seq 1 48); do
		case $(adb get-state 2>/dev/null) in
			device|recovery) break ;;
		esac
		sleep 5
	done
	case $(adb get-state 2>/dev/null) in
		device|recovery) ;;
		*) echo "PHONE UNREACHABLE: restore not possible from here" >&2; return 2 ;;
	esac
	if [ "$(adb get-state 2>/dev/null)" = recovery ]; then remote=/tmp; else adb root >/dev/null 2>&1; sleep 3; remote=/data/local/tmp; fi
	adb push "$SAVE" "$remote/los-boot-restore.img" >/dev/null || return 2
	adb push "$MISC" "$remote/misc-restore.bin" >/dev/null || return 2
	ash "dd if=$remote/los-boot-restore.img of=$LB bs=1048576 2>/dev/null; dd if=$remote/misc-restore.bin of=$MD bs=4096 seek=$MB conv=notrunc 2>/dev/null; sync"
	local n; n=$(stat -c %s "$SAVE")
	local got; got=$(adb exec-out "head -c $n $LB | sha1sum" | cut -d' ' -f1)
	[ "$got" = "$(sha1sum < "$SAVE" | cut -d' ' -f1)" ] || { echo "restore sha1 mismatch: $got" >&2; return 2; }
	restored=1
	say "saved image restored and verified; rebooting"
	adb reboot
	sleep 20
	for i in $(seq 1 60); do
		case $(adb get-state 2>/dev/null) in
			device) b=$(ash 'getprop sys.boot_completed'); [ "$b" = 1 ] && { say "LOS after rollback: boot_completed=1"; return 0; } ;;
			recovery) adb reboot; sleep 20 ;;
		esac
		sleep 5
	done
	echo "LOS not reachable after rollback" >&2
	return 2
}

cleanup() {
	local rc=$?
	say "cleanup (rc=$rc, flashed=$flashed, restored=$restored)"
	if [ $flashed = 1 ] && [ $restored = 0 ]; then
		restore "exit from test with the test image still in los_boot" || rc=2
	fi
	say "final state: $(adb get-state 2>/dev/null) boot_completed=$(ash 'getprop sys.boot_completed' 2>/dev/null) battery=$(ash 'cat /sys/class/power_supply/qcom-battery/capacity' 2>/dev/null)%"
	say "LOG=$LOG"
	exit $rc
}
trap cleanup EXIT INT TERM

say "preconditions"
[ -s "$IMG" ] || { echo "missing test image" >&2; exit 2; }
st=$(adb get-state 2>/dev/null || true)
case $st in device|recovery) ;; *) echo "phone is $st, expected device or recovery" >&2; exit 2 ;; esac
if [ "$st" = device ]; then adb root >/dev/null; sleep 3; adb wait-for-device; fi
LB=$(dev los_boot); MD=$(dev misc)
[ -n "$LB" ] && [ -n "$MD" ] || { echo "no los_boot/misc" >&2; exit 2; }
MB=$(( $(adb shell cat /sys/class/block/${MD##*/}/size | tr -d '\r') / 8 ))
echo "los_boot=$LB misc=$MD boot-menu block=$MB"
if [ "$st" = device ]; then
	bc=$(ash 'getprop sys.boot_completed'); bat=$(ash 'cat /sys/class/power_supply/qcom-battery/capacity')
	echo "boot_completed=$bc battery=$bat%"
	[ "$bc" = 1 ] || { echo "phone not fully booted" >&2; exit 2; }
	[ "$bat" -ge 30 ] || { echo "battery below 30%" >&2; exit 2; }
fi

say "save current los_boot to $SAVE (sha1 verified)"
adb exec-out "dd if=$LB bs=1048576 2>/dev/null" > "$SAVE"
n=$(stat -c %s "$SAVE")
[ "$n" -ge 1048576 ] || { echo "backup too small ($n)" >&2; exit 2; }
sha=$(sha1sum < "$SAVE" | cut -d' ' -f1)
got=$(adb exec-out "head -c $n $LB | sha1sum" | cut -d' ' -f1)
echo "saved $n bytes sha1=$sha readback=$got"
[ "$got" = "$sha" ] || { echo "los_boot backup sha1 mismatch" >&2; exit 2; }
sha1sum ~/axon7-kbuild/kfast/los-boot.img | sed 's/^/known-good #31: /'
adb exec-out "dd if=$MD bs=4096 skip=$((MB - 1)) count=1 2>/dev/null" > "$MISC"
[ "$(stat -c %s "$MISC")" = 4096 ] || { echo "boot-menu block read failed" >&2; exit 2; }

say "arm watchdog on the current system (if possible)"
if [ "$st" = device ]; then
	adb shell 'printf "#!/system/bin/sh\nexec 3>/dev/watchdog\nwhile true; do echo 1 >&3; sleep 10; done\n" > /data/local/tmp/wdpet.sh; chmod 755 /data/local/tmp/wdpet.sh; pgrep -f "^/system/bin/sh /data/local/tmp/wdpet.sh\$" >/dev/null || setsid nohup /data/local/tmp/wdpet.sh >/dev/null 2>&1 < /dev/null &' || true
fi

say "write test image and one-shot LineageOS boot-menu entry"
python3 -I -c 'import struct,sys; sys.stdout.buffer.write((b"AX7BOOT1"+struct.pack("<III",2,1,2^0xa5a5a5a5)).ljust(4096,b"\0"))' > "$B/misc-los-$TS.bin"
nimg=$(stat -c %s "$IMG")
[ "$st" = recovery ] && remote=/tmp || remote=/data/local/tmp
adb push "$IMG" "$remote/los-boot-test.img" >/dev/null
adb push "$B/misc-los-$TS.bin" "$remote/misc-los.bin" >/dev/null
ash "dd if=$remote/los-boot-test.img of=$LB bs=1048576 2>/dev/null && dd if=$remote/misc-los.bin of=$MD bs=4096 seek=$MB conv=notrunc 2>/dev/null; sync"
got=$(adb exec-out "head -c $nimg $LB | sha1sum" | cut -d' ' -f1)
[ "$got" = "$(sha1sum < "$IMG" | cut -d' ' -f1)" ] || { echo "test image sha1 mismatch: $got; not rebooting" >&2; exit 2; }
echo "test image written and verified ($nimg bytes)"
flashed=1
adb reboot

say "wait up to 8 min for boot_completed=1"
ok=0 retw=0
for i in $(seq 1 96); do
	cs=$(adb get-state 2>/dev/null || true)
	case $cs in
		device)
			b=$(ash 'getprop sys.boot_completed' 2>/dev/null)
			[ "$b" = 1 ] && { ok=1; break; }
			;;
		recovery)
			if [ $retw -lt 2 ]; then
				echo "phone in TWRP after test kernel: restoring saved image"
				restore "appeared in TWRP" || exit 2
				retw=$((retw + 1))
				break
			else
				echo "phone keeps falling back to TWRP" >&2
				restore "repeated TWRP fallback" || exit 2
				break
			fi
			;;
	esac
	sleep 5
done
if [ $ok = 0 ] && [ $restored = 0 ]; then
	restore "boot_completed != 1 after 8 min" || exit 2
fi
if [ $ok = 1 ]; then
	adb root >/dev/null 2>&1; sleep 3
	say "success: $(ash 'uname -v'); nq-nci=$(ash 'test -e /dev/nq-nci && echo present || echo MISSING')"
	D0=$(adb shell dmesg | wc -l)
	if [ -n "$CLIENT" ] && [ -e "$CLIENT" ]; then
		adb push "$CLIENT" "$remote/axon7-nfc-char-test" >/dev/null
		say "char-device NCI proof"
		ash "chmod 755 $remote/axon7-nfc-char-test; timeout 20 $remote/axon7-nfc-char-test /dev/nq-nci"
		say "new dmesg"
		adb shell dmesg | tail -n +$((D0 + 1)) | grep -i -E 'pn5xx|nq-nci|nfc' | tail -60 || true
	fi
	adb push "$MISC" "$remote/misc-before.bin" >/dev/null
	ash "dd if=$remote/misc-before.bin of=$MD bs=4096 seek=$MB conv=notrunc 2>/dev/null; sync"
	say "boot menu restored"
fi
exit 0
