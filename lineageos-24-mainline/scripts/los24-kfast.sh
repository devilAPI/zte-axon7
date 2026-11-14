#!/bin/bash
# los24-kfast.sh BASE_BOOT_IMG [--server] [--no-flash]
#
# Kernel-only test loop on the developer PC, without the build server:
#   1. kernel-build.sh setup config build stage with local paths (same patch
#      series, same config, the same pinned clang as the server, all cores)
#   2. a new boot image: BASE_BOOT_IMG (boot.img of the last full image
#      build, e.g. ios/research/los24-build-31/boot.img) with the new Image
#      and DTB; ramdisk, cmdline and header stay
#   3. the modules are compared with the server's prebuilt/modules (the ones
#      in the image's /vendor): if a .ko differs, the kernel-only test is not
#      valid for that driver (push the module or build an image)
#   4. the phone (LineageOS on adb, or TWRP): los_boot <- the image (via
#      tools/axon7-androidimg.py convert), boot menu "LineageOS after 1 s" for
#      one start, reboot; once LineageOS is on adb the old boot menu block is
#      written back (a crash then ends in postmarketOS)
#   --server: also stage the kernel in root@compiler:/srv/los24/kernel/prebuilt
#      so the next image build there needs no kernel build (los24-build.sh only)
#   --no-flash: stop after the image (out: $W/los-boot.img)
#
# Run from the lineageos-24-mainline worktree. Setup once (kernel tree, clang,
# mkbootimg, about 6 GB): see KFAST_DIR below; the first build is a full one
# (about 7 min on 12 threads), later ones take seconds to a minute.
# Time per kernel test: about 3-5 min instead of 30+ (kernel + image on the
# server, super fetch and write, TWRP round trip).
set -euo pipefail
base=$(realpath "$1"); shift
server=0 flash=1
for a in "$@"; do case $a in --server) server=1 ;; --no-flash) flash=0 ;; *) echo "unknown $a" >&2; exit 2 ;; esac; done
R=$(git rev-parse --show-toplevel)
W=${KFAST_DIR:-$HOME/axon7-kbuild}	# linux/ (git tree), clang-r536225/, mkbootimg/ (from the server)
IOS=${IOS_DIR:-$(dirname "$R")/zte-axon7/ios}	# ios checkout with tools/axon7-androidimg.py
export KSRC=$W/linux KOUT=$W/out-r536225 KPRE=$W/prebuilt KCLANG=$W/clang-r536225 AXON7_REPO=$R J=$(nproc)
[ -d "$KSRC/.git" ] && [ -x "$KCLANG/bin/clang" ] && [ -f "$W/mkbootimg/mkbootimg.py" ] ||
	{ echo "setup missing in $W: linux/ (rsync -a root@compiler:/srv/los24/kernel/linux), clang-r536225/ (/srv/aosp/lineage-22.2/prebuilts/clang/host/linux-x86/), mkbootimg/ (/srv/los24/lineage-24.0/system/tools/mkbootimg/)" >&2; exit 1; }
say() { echo "== $* ($(date +%T))"; }

say "kernel"
bash "$R/lineageos-24-mainline/scripts/kernel-build.sh" setup config build stage

say "boot image from $(basename "$(dirname "$base")")/$(basename "$base")"
t=$W/kfast; rm -rf "$t"; mkdir -p "$t"
python3 -I - "$W/mkbootimg" "$base" "$t" "$KPRE/Image" "$KPRE/dtb/msm8996-zte-axon7.dtb" <<'EOF'
import subprocess, sys, shlex
mk, base, t, image, dtb = sys.argv[1:]
args = subprocess.run([sys.executable, f"{mk}/unpack_bootimg.py", "--boot_img", base,
                       "--out", f"{t}/unpacked", "--format", "mkbootimg", "-0"],
                      check=True, capture_output=True).stdout.split(b"\0")
args = [a.decode() for a in (args[:-1] if args and not args[-1] else args)]  # keep empty values (--board "")
for opt, new in (("--kernel", image), ("--dtb", dtb)):
    i = args.index(opt)
    args[i + 1] = new
subprocess.run([sys.executable, f"{mk}/mkbootimg.py", *args, "--output", f"{t}/boot.img"], check=True)
print("boot.img:", " ".join(shlex.quote(a) for a in args if not a.startswith(t)))
EOF
python3 -I "$IOS/tools/axon7-androidimg.py" convert "$t/boot.img" -o "$t/los-boot.img"
python3 -I "$IOS/tools/axon7-androidimg.py" check "$t/los-boot.img"
cp "$t/los-boot.img" "$W/los-boot.img"

say "modules against the image's (server prebuilt)"
( cd "$KPRE/modules" && sha256sum -- *.ko ) > "$t/mods-local"
ssh -o BatchMode=yes root@compiler 'cd /srv/los24/kernel/prebuilt/modules && sha256sum -- *.ko' > "$t/mods-server" ||
	echo "   (server not reachable: modules not compared)"
if [ -s "$t/mods-server" ]; then
	diff <(sort -k2 "$t/mods-server") <(sort -k2 "$t/mods-local") | awk '/^[<>]/{print $3}' | sort -u > "$t/mods-diff" || true
	if [ -s "$t/mods-diff" ]; then
		echo "   WARNING: $(wc -l < "$t/mods-diff") module(s) differ from the image's /vendor: $(head -8 "$t/mods-diff" | tr '\n' ' ')"
		echo "   (a kernel-only test is valid for built-in drivers; changed modules need an image build)"
	else
		echo "   modules identical: the kernel-only test is valid"
	fi
fi

if [ $server = 1 ]; then
	say "staging on the server"
	rsync -a --delete "$KPRE/" root@compiler:/srv/los24/kernel/prebuilt.new/
	ssh root@compiler 'cd /srv/los24/kernel && chown -R build:build prebuilt.new && rm -rf prebuilt.old && mv prebuilt prebuilt.old && mv prebuilt.new prebuilt && echo "staged $(cat prebuilt/version)"'
fi
[ $flash = 1 ] || { echo "image: $W/los-boot.img"; exit 0; }

say "phone"
st=$(adb get-state 2>/dev/null || true)
case $st in
device) adb root >/dev/null; sleep 3; adb wait-for-device ;;
recovery) ;;
*) echo "phone not in LineageOS or TWRP on adb (state: ${st:-none})" >&2; exit 1 ;;
esac
dev() { adb shell "for b in /sys/class/block/*; do grep -q '^PARTNAME=$1\$' \$b/uevent 2>/dev/null && echo /dev/block/\${b##*/}; done; true" | tr -d '\r' | head -1; }	# true: the loop's last grep fails
lb=$(dev los_boot) md=$(dev misc)
[ -n "$lb" ] && [ -n "$md" ] || { echo "no los_boot/misc on the phone" >&2; exit 1; }
mb=$(( $(adb shell cat /sys/class/block/${md##*/}/size | tr -d '\r') / 8 ))
adb exec-out "dd if=$md bs=4096 skip=$((mb - 1)) count=1 2>/dev/null" > "$t/misc-before.bin"
[ "$(stat -c %s "$t/misc-before.bin")" = 4096 ] || { echo "could not read the boot menu block" >&2; exit 1; }
python3 -I -c 'import struct,sys; sys.stdout.buffer.write((b"AX7BOOT1"+struct.pack("<III",2,1,2^0xa5a5a5a5)).ljust(4096,b"\0"))' > "$t/misc-los.bin"
tmp=/data/local/tmp; [ "$st" = recovery ] && tmp=/tmp
adb push "$t/los-boot.img" "$tmp/los-boot.img" >/dev/null
adb push "$t/misc-los.bin" "$tmp/misc-los.bin" >/dev/null
adb shell "dd if=$tmp/los-boot.img of=$lb bs=1048576 2>/dev/null && dd if=$tmp/misc-los.bin of=$md bs=4096 seek=$((mb - 1)) conv=notrunc 2>/dev/null; sync"
n=$(stat -c %s "$t/los-boot.img")
[ "$(adb exec-out "head -c $n $lb | sha1sum" | cut -d' ' -f1)" = "$(sha1sum < "$t/los-boot.img" | cut -d' ' -f1)" ] ||
	{ echo "los_boot does not read back as written: not rebooting" >&2; exit 1; }
echo "   los_boot ($lb) written and verified, boot menu: LineageOS once"
adb reboot
say "waiting for LineageOS"
sleep 20
# a plain reboot can end in TWRP (stale PON reason "recovery" before kernel
# patch 0046): reboot from there once more (TWRP's reboot reaches the menu)
ok=0 retw=0
for i in $(seq 1 200); do
	case $(adb get-state 2>/dev/null) in
	device) ok=1; break ;;
	recovery) [ $retw -lt 2 ] && { echo "   in TWRP: rebooting to LineageOS"; adb reboot; retw=$((retw + 1)); sleep 20; } ;;
	esac
	sleep 3
done
[ $ok = 1 ] || { echo "no adb from LineageOS after 10 min (boot menu still LineageOS: $t/misc-before.bin restores it)" >&2; exit 3; }
adb root >/dev/null 2>&1; sleep 3; timeout 60 adb wait-for-device
adb push "$t/misc-before.bin" /data/local/tmp/misc-before.bin >/dev/null
adb shell "dd if=/data/local/tmp/misc-before.bin of=$(dev misc) bs=4096 seek=$((mb - 1)) conv=notrunc 2>/dev/null; sync"
echo "   boot menu restored"
for i in $(seq 1 60); do [ "$(timeout 20 adb shell getprop sys.boot_completed | tr -d '\r')" = 1 ] && break; sleep 5; done
say "LineageOS up: $(adb shell uname -v | tr -d '\r')"
# unattended safety: arm the APSS watchdog (30 s) with a petting loop until
# the image has a watchdogd service; a hang then resets into the boot menu
timeout 15 adb shell 'printf "#!/system/bin/sh\nexec 3>/dev/watchdog\nwhile true; do echo 1 >&3; sleep 10; done\n" > /data/local/tmp/wdpet.sh; chmod 755 /data/local/tmp/wdpet.sh; pgrep -f "^/system/bin/sh /data/local/tmp/wdpet.sh\$" >/dev/null || setsid nohup /data/local/tmp/wdpet.sh >/dev/null 2>&1 < /dev/null &' || true	# the background loop keeps adb open: timeout
sleep 2; echo "   watchdog: $(adb shell cat /sys/class/watchdog/watchdog0/state | tr -d '\r')"
