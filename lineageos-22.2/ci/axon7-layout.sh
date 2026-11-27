#!/sbin/sh
# Axon 7 LineageOS 22.2 installer: decide which partition layout to install to.
# Runs first in the TWRP zip (edify run_program), READ-ONLY: it opens nothing
# for writing except its own two result files under $AXON7_OUT (/tmp).
#
# Layouts (the zip carries one image set for each):
#   vendor  the community layout: system + a 512 MiB "vendor" partition after it.
#           system.new.dat.br + vendor.new.dat.br + boot.img (vendor image on its own).
#   stock   ZTE's original table, no vendor partition (or one too small to
#           hold the vendor image). system-nv.new.dat.br + boot-nv.img: the vendor
#           files live INSIDE the system image (/vendor -> /system/vendor).
#           Nothing is written to a vendor partition even if there is one.
#
# Result: exit code 0 and $AXON7_OUT/axon7-layout.prop with layout=vendor|stock,
# or exit code 1 (nothing was decided; the message says why). The installer
# aborts BEFORE writing anything in that case.
#
# Only system, boot (and, by the zip's other steps, userdata/cache) are ever
# written. modem, persist, fsg/fsc/modemst1/2 (EFS), tz, aboot, xbl and the
# other bootloader partitions are not looked at, let alone opened.
#
# Test overrides (never set on the phone):
#   AXON7_BYNAME  directory with the by-name links   (/dev/block/bootdevice/by-name)
#   AXON7_SYSFS   directory with <dev>/size in 512 B (/sys/class/block)
#   AXON7_OUT     where the result files go          (/tmp)
#   AXON7_NOBLK=1 accept regular files as "block devices" (fake tables)
#
# SYSTEM_BYTES / VENDOR_BYTES: the file system sizes inside the zip's images
# (misc_info system_size / vendor_size). combine-zip.py rewrites the two values.
SYSTEM_BYTES=5905580032
VENDOR_BYTES=536870912

BYNAME=${AXON7_BYNAME:-/dev/block/bootdevice/by-name}
SYSFS=${AXON7_SYSFS:-/sys/class/block}
OUT=${AXON7_OUT:-/tmp}
MSG=$OUT/axon7-layout.txt
PROP=$OUT/axon7-layout.prop

: > "$MSG" 2>/dev/null
rm -f "$PROP" 2>/dev/null

say() { echo "$*" >> "$MSG"; }
fail() { say "ERROR: $*"; say "Nothing was written to the phone."; exit 1; }

# size in bytes of the block device behind a by-name link, empty if unusable
part_bytes() {	# $1 name
	link=$BYNAME/$1
	[ -e "$link" ] || return 1
	real=$(readlink -f "$link" 2>/dev/null) || return 1
	[ -n "$real" ] || return 1
	if [ "${AXON7_NOBLK:-0}" != 1 ] && [ ! -b "$real" ]; then
		return 1
	fi
	dev=${real##*/}
	[ -r "$SYSFS/$dev/size" ] || return 1
	sectors=$(cat "$SYSFS/$dev/size" 2>/dev/null)
	case $sectors in ''|*[!0-9]*) return 1 ;; esac
	# sectors * 512 without 32-bit overflow in busybox sh: 64-bit arithmetic is
	# available in TWRP's mksh/ash; guard anyway
	echo $((sectors * 512))
}

real_of() { readlink -f "$BYNAME/$1" 2>/dev/null; }

[ -d "$BYNAME" ] || fail "$BYNAME does not exist (not TWRP on an Axon 7?)"

sys_b=$(part_bytes system) || fail "no usable 'system' partition (by-name/system)"
# TWRP 3.3.1 busybox [ -ge ] is 32-bit: compare in $((...)) (64-bit).
boot_b=$(part_bytes boot) || fail "no usable 'boot' partition (by-name/boot)"
[ "$(($boot_b >= 33554432))" = 1 ] || fail "'boot' is only $boot_b bytes (expected 64 MiB)"

[ "$(($sys_b >= SYSTEM_BYTES))" = 1 ] || fail "'system' is $sys_b bytes; the ROM image needs $SYSTEM_BYTES"

# system and boot must be two different devices, and neither may be a
# partition the installer must never touch
sys_real=$(real_of system); boot_real=$(real_of boot)
[ "$sys_real" != "$boot_real" ] || fail "'system' and 'boot' are the same device"
for n in modem persist modemst1 modemst2 fsg fsc tz aboot xbl rpm hyp cmnlib devinfo; do
	r=$(real_of "$n")
	[ -z "$r" ] && continue
	[ "$r" != "$sys_real" ] || fail "'system' resolves to the $n partition ($r); refusing"
	[ "$r" != "$boot_real" ] || fail "'boot' resolves to the $n partition ($r); refusing"
done

layout=stock
reason="no vendor partition (ZTE's original layout)"
if [ -e "$BYNAME/vendor" ]; then
	if ven_b=$(part_bytes vendor); then
		ven_real=$(real_of vendor)
		[ "$ven_real" != "$sys_real" ] && [ "$ven_real" != "$boot_real" ] \
			|| fail "'vendor' resolves to the system or boot device; refusing"
		if [ "$(($ven_b >= VENDOR_BYTES))" = 1 ]; then
			layout=vendor
			reason="vendor partition of $ven_b bytes"
		else
			reason="vendor partition is only $ven_b bytes (< $VENDOR_BYTES), left untouched"
		fi
	else
		reason="a 'vendor' entry exists but is not a readable block device, ignored"
	fi
fi

say "Layout: $layout ($reason)"
say "system: $sys_b bytes, boot: $boot_b bytes"
echo "layout=$layout" > "$PROP" || fail "cannot write $PROP"
exit 0
