#!/bin/sh
# Read-only preflight for the ZTE Axon 7 (ailsa_ii / axon7, all variants:
# A2017G, A2017U, A2017). Run it in TWRP (Advanced > Terminal) or from an
# adb root shell before flashing anything. It never writes to a partition.
#
# It checks the things that differ between the A2017G (what the project was
# developed on) and the A2017U (US; user-reported working, see
# docs/variant-a2017u.md):
#   - the reported device/model and the TrustZone version in `tz`
#   - the filesystem on userdata (TWRP 3.7 can format it as f2fs, while
#     LineageOS 22.2's fstab requires ext4: first boot fails with
#     "invalid magic", apexd aborts and the phone restarts in a loop)
#   - whether the community vendor partition exists (LineageOS 22.2 stops
#     after writing system; LineageOS 24 reads its GPU firmware from it)
#   - for LineageOS 24: the multi-boot partitions (los_boot, los_metadata,
#     los_data) and the boot menu
#
# Usage:
#   axon7-preflight.sh [--rom generic|los22|los24|nura|ios] [--props FILE]
#   axon7-preflight.sh --help
#
# Exit status: 0 = no blocker, 1 = at least one blocker, 2 = usage error.
# `--props FILE` (key=value lines) and AXON7_ROOT=DIR (prefix for /sys and
# /dev) exist so the script can be tested without a phone.
set -u

rom=generic
props_file=
root=${AXON7_ROOT:-}
while [ $# -gt 0 ]; do
	case $1 in
		--help|-h)
			sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
			exit 0
			;;
		--rom) rom=${2:-}; shift 2 || { echo "usage: $0 [--rom generic|los22|los24|nura|ios]" >&2; exit 2; } ;;
		--props) props_file=${2:-}; shift 2 || { echo "usage: $0 [--props FILE]" >&2; exit 2; } ;;
		*) echo "$0: unknown argument '$1' (see --help)" >&2; exit 2 ;;
	esac
done
case $rom in generic|los22|los24|nura|ios) ;; *)
	echo "$0: unknown ROM '$rom' (generic, los22, los24, nura, ios)" >&2; exit 2 ;;
esac

blockers=0
warnings=0
say()  { printf '%s\n' "$*"; }
ok()   { printf '  ok    %s\n' "$*"; }
warn() { printf '  WARN  %s\n' "$*"; warnings=$((warnings + 1)); }
bad()  { printf '  FAIL  %s\n' "$*"; blockers=$((blockers + 1)); }

prop() {
	# $1 key. Reads --props first, then getprop, then nothing.
	if [ -n "$props_file" ]; then
		sed -n "s/^$1=//p" "$props_file" | head -1
	elif command -v getprop >/dev/null 2>&1; then
		getprop "$1" 2>/dev/null
	fi
}

# TWRP for ailsa_ii has no /dev/block/by-name; the platform path is the one
# TWRP's installer uses. Try both, plus the bootdevice alias.
part() {
	for p in \
		"$root/dev/block/bootdevice/by-name/$1" \
		"$root/dev/block/platform/soc/624000.ufshc/by-name/$1" \
		"$root/dev/block/by-name/$1"; do
		[ -e "$p" ] && { echo "$p"; return 0; }
	done
	return 1
}

part_size_mib() {
	# /sys/class/block/<node>/size is in 512-byte sectors
	b=$(readlink -f "$1" 2>/dev/null || echo "$1")
	s=${b##*/}
	f="$root/sys/class/block/$s/size"
	[ -r "$f" ] || return 1
	echo $(( $(cat "$f") / 2048 ))
}

fs_magic() {
	# hex bytes at byte offset $2, length $3, from block device $1
	dd if="$1" bs=1 skip="$2" count="$3" 2>/dev/null |
		od -An -tx1 2>/dev/null | tr -d ' \n'
}

fs_type() {
	# ext4/f2fs/unknown for a block device; read-only.
	dev=$1
	m=$(fs_magic "$dev" 1024 4)
	case $m in
		1020f5f2) echo f2fs; return 0 ;;
	esac
	m=$(fs_magic "$dev" 1080 2)
	case $m in
		53ef) echo ext4; return 0 ;;
	esac
	if command -v blkid >/dev/null 2>&1; then
		t=$(blkid -o value -s TYPE "$dev" 2>/dev/null)
		[ -n "$t" ] && { echo "$t"; return 0; }
	fi
	echo unknown
}

say "ZTE Axon 7 preflight (read-only), ROM profile: $rom"
say ""

# --- identity -------------------------------------------------------------
dev=$(prop ro.product.device)
model=$(prop ro.product.model)
lineage=$(prop ro.lineage.version)
bootloader=$(prop ro.bootloader)
baseband=$(prop gsm.version.baseband)
say "Device"
[ -n "$dev" ] && say "  ro.product.device:  $dev" || warn "ro.product.device is empty (not booted into Android/TWRP, or no getprop)"
[ -n "$model" ] && say "  ro.product.model:   $model"
[ -n "$lineage" ] && say "  ro.lineage.version: $lineage"
[ -n "$bootloader" ] && say "  ro.bootloader:      $bootloader"
[ -n "$baseband" ] && say "  baseband:           $baseband"
case $dev in
	ailsa_ii|axon7) ok "codename is ailsa_ii/axon7 (A2017G, A2017U and A2017 share it); the ROM installers' device assert passes" ;;
	"") ;;
	*) warn "unexpected device '$dev': this project only supports ailsa_ii/axon7" ;;
esac
case $model in
	*A2017U*) say "  variant: A2017U (US) reported"
	          say "           - stock B35 has no fastboot; the unlock route was an EDL flash of the"
	          say "             B15-NEW aboot+fbop (B29 alone was not enough), then reflash TWRP."
	          say "           - use an A2017U modem package, never the A2017G one."
	          say "           - cellular (calls/SMS/data) is UNTESTED on the A2017U." ;;
	*A2017G*) say "  variant: A2017G (global; the variant the project was tested on)" ;;
	*A2017*)  say "  variant: A2017 (China) reported (untested)" ;;
esac
say ""

# --- TrustZone ------------------------------------------------------------
say "Bootloader / TrustZone"
if tz=$(part tz); then
	ver=$(tr -c '[:print:]' '\n' < "$tz" 2>/dev/null | grep -m1 'QC_IMAGE_VERSION_STRING' || true)
	if [ "$ver" = "QC_IMAGE_VERSION_STRING=TZ.BF.4.0.1-00353" ]; then
		ok "$ver (the Oreo bootstack LineageOS 22.2 requires)"
	else
		[ -n "$ver" ] && say "  tz: $ver" || warn "could not read QC_IMAGE_VERSION_STRING from $tz"
		case $rom in
			los22) bad "LineageOS 22.2's installer asserts TZ.BF.4.0.1-00353; install the Oreo universal bootstack for your model first" ;;
			*) warn "LineageOS 22.2 requires TZ.BF.4.0.1-00353; Nura/LineageOS 24/iOS do not check it" ;;
		esac
	fi
else
	warn "no tz partition found (not in TWRP, or the by-name links are missing)"
fi
say ""

# --- userdata filesystem --------------------------------------------------
say "userdata filesystem"
if ud=$(part userdata); then
	fs=$(fs_type "$ud")
	say "  $ud: $fs"
	case $fs in
		ext4) ok "ext4" ;;
		f2fs)
			case $rom in
				los22)
					bad "/data is f2fs but LineageOS 22.2 mounts it as ext4 with fileencryption=ice,quota"
					say "        First boot then fails with 'invalid magic', root stays read-only, apexd aborts and"
					say "        the phone restarts in a loop. Fix, either:"
					say "          TWRP > Wipe > Advanced Wipe > Data > Repair or Change File System > EXT4 (keeps nothing useful)"
					say "          or in TWRP's terminal (ERASES INTERNAL STORAGE):"
					say "            mke2fs -t ext4 /dev/block/bootdevice/by-name/userdata"
					say "        TWRP 3.7.0_9-0's 'Format Data' may produce f2fs on this phone; check again afterwards."
					;;
				*) warn "/data is f2fs; LineageOS 22.2 requires ext4. Nura/iOS/LineageOS 24 do not use userdata this way" ;;
			esac
			;;
		unknown) warn "could not identify the filesystem (no permission or blank partition); check it in TWRP" ;;
		*) warn "/data is $fs; LineageOS 22.2 expects ext4" ;;
	esac
else
	warn "no userdata partition found (not in TWRP, or the by-name links are missing)"
fi
say ""

# --- vendor ---------------------------------------------------------------
say "Vendor partition"
if v=$(part vendor); then
	mib=$(part_size_mib "$v" || echo "?")
	fs=$(fs_type "$v")
	ok "$v exists (${mib} MiB, $fs)"
	if [ "$mib" != "?" ] && [ "$mib" -lt 384 ]; then
		warn "vendor is smaller than 384 MiB; LineageOS needs about 403 MB (512 MiB partition)"
	fi
	case $rom in
		los24) say "        LineageOS 24 reads a530_zap (GPU firmware) from it read-only; do not wipe Vendor" ;;
		los22) say "        LineageOS 22.2 writes system/vendor here; keep it" ;;
		nura)  say "        Nura also falls back to the system partition if there is no vendor" ;;
	esac
else
	case $rom in
		los22) bad "no vendor partition: LineageOS 22.2 stops after it has overwritten system"
		       say "        Create one with tools/axon7-make-vendor.sh (the PARTY replacement; 512 MiB from"
		       say "        the end of system). Read its plan first and use the phone's real sector numbers." ;;
		los24) bad "no vendor partition: LineageOS 24 loads its GPU firmware from it (black screen without it)"
		       say "        Create one with tools/axon7-make-vendor.sh, or install LineageOS 22.2 first." ;;
		*) warn "no vendor partition (fine for Nura/iOS; the project's Android ROMs need one)" ;;
	esac
fi
say ""

# --- multi-boot / other partitions ---------------------------------------
if [ "$rom" = los24 ]; then
	say "LineageOS 24 multi-boot partitions"
	for p in boot los_boot los_metadata los_data system; do
		if b=$(part "$p"); then
			ok "$p -> $b ($(part_size_mib "$b" || echo '?') MiB)"
		else
			bad "no $p partition: LineageOS 24 only installs into the multi-boot layout (DEV-MULTIBOOT.md)"
		fi
	done
	if b=$(part boot); then
		if dd if="$b" bs=1048576 count=16 2>/dev/null | tr -c 'A-Za-z' '\n' | grep -q '^LineageOS$'; then
			ok "boot contains a boot menu with a LineageOS entry"
		else
			warn "no 'LineageOS' label in the first 16 MiB of boot (menu compressed? the installer also checks gunzip'd pages)"
		fi
	fi
	say ""
elif [ "$rom" = nura ]; then
	say "Nura"
	if [ -b "$root/dev/block/mmcblk0" ] || [ -b "$root/dev/block/mmcblk0p1" ]; then
		ok "microSD card (mmcblk0) present"
	else
		warn "no microSD card seen (Nura's root filesystem lives on it)"
	fi
	say ""
fi

# --- summary --------------------------------------------------------------
say "Summary: $blockers blocker(s), $warnings warning(s)"
if [ "$blockers" -gt 0 ]; then
	say "Do not flash until the FAIL lines are fixed."
	exit 1
fi
say "No blocker found. Read the warnings; nothing was written."
exit 0
