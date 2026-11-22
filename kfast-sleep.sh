#!/bin/bash
# Kernel-only test loop for the sleep patches on the MAIN phone (LineageOS 24).
# Derived from lineageos-24-mainline/scripts/los24-kfast.sh; never runs on the
# second phone.  Only los_boot and the one-shot boot-menu block are written,
# and the boot-menu block is restored before the script returns.
#
#   ./kfast-sleep.sh image        # build a test boot.img from the staged kernel
#   ./kfast-sleep.sh phone        # write it to los_boot, boot once, restore menu
#   ./kfast-sleep.sh both
set -euo pipefail
W=$(cd "$(dirname "$0")" && pwd)
H=${H:-/media/devilapi/Secondary HDD 2TB/ai-worker/axon7}
KOUT="$H/sleep-loskout"
KPRE="$H/sleep-losprebuilt"
IOS=/home/devilapi/Documents/GitHub/zte-axon7/ios
MK=/home/devilapi/axon7-kbuild/mkbootimg
BASE="$IOS/research/los24-build-51/boot.img"
T="$W/.kfast-sleep"
SERIAL=7e15695a
say() { echo "== $* ($(date +%FT%T))"; }
adbX() { adb -s "$SERIAL" "$@"; }
dev() { adbX shell "for b in /sys/class/block/*; do grep -q '^PARTNAME=$1\$' \$b/uevent 2>/dev/null && echo /dev/block/\${b##*/}; done; true" | tr -d '\r' | head -1; }

image() {
	say "boot image from $(basename "$(dirname "$BASE")")/$(basename "$BASE")"
	rm -rf "$T"; mkdir -p "$T"
	python3 -I - "$MK" "$BASE" "$T" "$KPRE/Image" "$KPRE/dtb/msm8996-zte-axon7.dtb" <<'EOF'
import subprocess, sys, shlex
mk, base, t, image, dtb = sys.argv[1:]
args = subprocess.run([sys.executable, f"{mk}/unpack_bootimg.py", "--boot_img", base,
                       "--out", f"{t}/unpacked", "--format", "mkbootimg", "-0"],
                      check=True, capture_output=True).stdout.split(b"\0")
args = [a.decode() for a in (args[:-1] if args and not args[-1] else args)]
for opt, new in (("--kernel", image), ("--dtb", dtb)):
    i = args.index(opt)
    args[i + 1] = new
subprocess.run([sys.executable, f"{mk}/mkbootimg.py", *args, "--output", f"{t}/boot.img"], check=True)
print("boot.img: ", " ".join(shlex.quote(a) for a in args if not a.startswith(t)))
EOF
	python3 -I "$IOS/tools/axon7-androidimg.py" convert "$T/boot.img" -o "$T/los-boot.img"
	python3 -I "$IOS/tools/axon7-androidimg.py" check "$T/los-boot.img"
	cp "$T/los-boot.img" "$W/los-sleep1-boot.img"
	# The modules in /vendor come from the image; a module that differs here
	# would make the kernel-only test invalid for that driver.
	(cd "$KPRE/modules" && sha256sum -- *.ko) > "$T/mods-local"
	if [ -d ~/axon7-kbuild/prebuilt/modules ]; then
		(cd ~/axon7-kbuild/prebuilt/modules && sha256sum -- *.ko) > "$T/mods-image"
		diff <(sort -k2 "$T/mods-image") <(sort -k2 "$T/mods-local") | awk '/^[<>]/{print $1,$3}' | sort -u > "$T/mods-diff" || true
		if [ -s "$T/mods-diff" ]; then
			echo "   WARNING: modules differ from the image's /vendor:"
			head -12 "$T/mods-diff"
		else
			echo "   modules identical to the image's /vendor: kernel-only test valid"
		fi
	fi
}

phone() {
	say "MAIN phone $SERIAL: saving boot menu"
	st=$(adbX get-state 2>/dev/null || true)
	case $st in
		device) adbX root >/dev/null; sleep 3; adbX wait-for-device ;;
		recovery) ;;
		*) echo "not in LineageOS or TWRP: '$st'" >&2; exit 1 ;;
	esac
	lb=$(dev los_boot) md=$(dev misc)
	[ -n "$lb" ] && [ -n "$md" ] || { echo "no los_boot/misc" >&2; exit 1; }
	mb=$(( $(adbX shell cat /sys/class/block/${md##*/}/size | tr -d '\r') / 8 ))
	adbX exec-out "dd if=$md bs=4096 skip=$((mb - 1)) count=1 2>/dev/null" > "$T/misc-before.bin"
	[ "$(stat -c %s "$T/misc-before.bin")" = 4096 ] || { echo "could not save boot menu" >&2; exit 1; }
	python3 -I -c 'import struct,sys; sys.stdout.buffer.write((b"AX7BOOT1"+struct.pack("<III",2,1,2^0xa5a5a5a5)).ljust(4096,b"\0"))' > "$T/misc-los.bin"
	tmp=/data/local/tmp; [ "$st" = recovery ] && tmp=/tmp
	adbX push "$T/los-boot.img" "$tmp/los-boot.img" >/dev/null
	adbX push "$T/misc-los.bin" "$tmp/misc-los.bin" >/dev/null
	adbX shell "dd if=$tmp/los-boot.img of=$lb bs=1048576 2>/dev/null && dd if=$tmp/misc-los.bin of=$md bs=4096 seek=$((mb - 1)) conv=notrunc 2>/dev/null; sync"
	n=$(stat -c %s "$T/los-boot.img")
	[ "$(adbX exec-out "head -c $n $lb | sha1sum" | cut -d' ' -f1)" = "$(sha1sum < "$T/los-boot.img" | cut -d' ' -f1)" ] ||
		{ echo "los_boot did not read back: not rebooting" >&2; exit 1; }
	say "los_boot ($lb) written and verified, boot menu: LineageOS once"
	adbX reboot
	say "waiting for LineageOS"
	sleep 20
	ok=0; retw=0
	for i in $(seq 1 200); do
		case $(adbX get-state 2>/dev/null) in
			device) ok=1; break ;;
			recovery) [ $retw -lt 2 ] && { echo "   in TWRP: rebooting to LineageOS"; adbX reboot; retw=$((retw + 1)); sleep 20; } ;;
		esac
		sleep 3
	done
	[ $ok = 1 ] || { echo "no adb after 10 min; boot menu still points to LineageOS, backup: $T/misc-before.bin" >&2; exit 3; }
	adbX root >/dev/null 2>&1; sleep 3; timeout 60 adbX wait-for-device
	adbX push "$T/misc-before.bin" /data/local/tmp/misc-before.bin >/dev/null
	adbX shell "dd if=/data/local/tmp/misc-before.bin of=$(dev misc) bs=4096 seek=$((mb - 1)) conv=notrunc 2>/dev/null; sync"
	echo "   boot menu restored"
	for i in $(seq 1 60); do [ "$(timeout 20 adbX shell getprop sys.boot_completed | tr -d '\r')" = 1 ] && break; sleep 5; done
	say "LineageOS up: $(adbX shell 'uname -r; uname -v' | tr -d '\r' | tr '\n' ' ')"
	# unattended safety: watchdog with a petting loop until the image has one
	timeout 15 adbX shell 'printf "#!/system/bin/sh\nexec 3>/dev/watchdog\nwhile true; do echo 1 >&3; sleep 10; done\n" > /data/local/tmp/wdpet.sh; chmod 755 /data/local/tmp/wdpet.sh; pgrep -f "^/system/bin/sh /data/local/tmp/wdpet.sh\$" >/dev/null || setsid nohup /data/local/tmp/wdpet.sh >/dev/null 2>&1 < /dev/null &' || true
	sleep 2; echo "   watchdog: $(adbX shell cat /sys/class/watchdog/watchdog0/state | tr -d '\r')"
}

action=${1:-both}
case $action in image) image ;; phone) phone ;; both) image; phone ;; *) echo "usage: $0 [image|phone|both]" >&2; exit 2 ;; esac
