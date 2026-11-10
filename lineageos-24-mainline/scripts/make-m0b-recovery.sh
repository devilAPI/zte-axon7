#!/bin/bash
# Milestone M0b test image without a new Android build: the LineageOS 24
# recovery.img from the build server, repacked with
#   - the current kernel + DTB from /srv/los24/kernel/prebuilt (e.g. with the
#     APSS watchdog node, kernel/patches/0001), and
#   - the developer's adb key as /adb_keys in the ramdisk (recovery adbd has
#     ro.adb.secure=1 and its /adb_keys points into /product, absent there).
#   - (FRONTEND=1, default) a busybox front end (m0b-frontend-init.sh) as a
#     second gzip cpio after the recovery ramdisk, started by rdinit=/axon7/init:
#     USB network + telnet 172.16.42.1 and a userspace-held watchdog, then
#     exec of Android's /init. So the boot can be inspected even if
#     Android's recovery never brings up adb. FRONTEND=0: plain recovery.
# Header (v2, offsets, cmdline) is taken over from the original image, the
# cmdline plus CMDLINE_APPEND (default: kernel log on the panel, devkmsg,
# watchdog fallback) and, with the front end, rdinit=; the result is checked
# like the M0 image (axon7-androidimg.py, shim android.c on the host).
#
# Usage (PC, repository root or worktree; AXON7_SRC = full checkout for ios/
# and postmarketos/test-initramfs):
#   [FRONTEND=0|1] [REC_IMG=path] lineageos-24-mainline/scripts/make-m0b-recovery.sh [OUTDIR]
#   (default OUTDIR /tmp/axon7m-m0b-rec; REC_IMG on the build server, default
#   the tree's out/.../recovery.img)
set -euo pipefail
R=$(git rev-parse --show-toplevel)
S=${AXON7_SRC:-$R}
O=${1:-/tmp/axon7m-m0b-rec}
H=${AXON7_BUILD_HOST:-root@compiler}
P=/srv/los24/lineage-24.0/out/target/product/axon7m
mkdir -p "$O"
scp -q "$H:${REC_IMG:-$P/recovery.img}" "$O/recovery-orig.img"
scp -q "$H:/srv/los24/kernel/prebuilt/Image" "$H:/srv/los24/kernel/prebuilt/dtb/msm8996-zte-axon7.dtb" \
	"$H:/srv/los24/kernel/prebuilt/version" "$H:/srv/los24/lineage-24.0/test-keys/adbkey.pub" "$O/"
rm -rf "$O/u"
mkbootargs=$(unpack_bootimg --boot_img "$O/recovery-orig.img" --out "$O/u" --format=mkbootimg)
gzip -dc "$O/u/ramdisk" > "$O/ramdisk.cpio"
python3 -I "$R/lineageos-24-mainline/scripts/cpio-replace.py" "$O/ramdisk.cpio" "$O/ramdisk-new.cpio" adb_keys "$O/adbkey.pub" 0644
gzip -9n < "$O/ramdisk-new.cpio" > "$O/ramdisk-new.cpio.gz"
FE=${FRONTEND:-1}
RDINIT=
if [ "$FE" = 1 ]; then
	# second archive: the kernel unpacks concatenated compressed cpios in turn
	TI=$S/postmarketos/test-initramfs
	[ -x "$TI/gen_init_cpio" ] && [ -r "$TI/root/bin/busybox" ] || { echo "missing $TI (busybox, gen_init_cpio)" >&2; exit 1; }
	cat > "$O/frontend.list" <<-EOF
	dir /axon7 0755 0 0
	dir /axon7/bin 0755 0 0
	dir /axon7/run 0755 0 0
	file /axon7/init $R/lineageos-24-mainline/scripts/m0b-frontend-init.sh 0755 0 0
	file /axon7/bin/busybox $TI/root/bin/busybox 0755 0 0
	file /axon7/bin/busybox-extras $TI/root/bin/busybox-extras 0755 0 0
	dir /lib 0755 0 0
	file /lib/ld-musl-aarch64.so.1 $TI/root/lib/ld-musl-aarch64.so.1 0755 0 0
	slink /lib/libc.musl-aarch64.so.1 ld-musl-aarch64.so.1 0777 0 0
	nod /dev/console 0600 0 0 c 5 1
	EOF
	"$TI/gen_init_cpio" "$O/frontend.list" | gzip -9n > "$O/frontend.cpio.gz"
	cat "$O/frontend.cpio.gz" >> "$O/ramdisk-new.cpio.gz"
	RDINIT=" rdinit=/axon7/init"
fi
# same header arguments, new kernel/DTB/ramdisk
eval "set -- $mkbootargs"
args=()
while [ $# -gt 0 ]; do
	case "$1" in
	--kernel) args+=("$1" "$O/Image"); shift 2 ;;
	--ramdisk) args+=("$1" "$O/ramdisk-new.cpio.gz"); shift 2 ;;
	--dtb) args+=("$1" "$O/msm8996-zte-axon7.dtb"); shift 2 ;;
	--cmdline)
		# kernel + init log on the panel (simplefb + fbcon), verbose; no
		# super partition for recovery (the old image named l24_super)
		c=$(echo " $2 " | sed 's/ androidboot.super_partition=[^ ]*//g; s/^ *//; s/ *$//')
		# watchdog.open_timeout: if nothing in userspace takes the
		# watchdog over within 120 s, the kernel stops feeding it (warm
		# reset, log kept in pstore)
		args+=("$1" "$c ${CMDLINE_APPEND-console=tty0 loglevel=7 printk.devkmsg=on watchdog.open_timeout=120}$RDINIT"); shift 2 ;;
	*) args+=("$1"); shift ;;
	esac
done
mkbootimg "${args[@]}" -o "$O/m0b-recovery.img"
python3 -I "$S/ios/tools/axon7-androidimg.py" check "$O/m0b-recovery.img"
AXON7_SRC=$S "$R/lineageos-24-mainline/scripts/shim-hostcheck.sh" "$O/m0b-recovery.img" "$O/shim-test"
echo "kernel: $(cat "$O/version")"
unpack_bootimg --boot_img "$O/m0b-recovery.img" --out "$O/chk" | grep -i "command line"
ls -l "$O/m0b-recovery.img"; sha256sum "$O/m0b-recovery.img"
