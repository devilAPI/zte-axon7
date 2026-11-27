#!/bin/sh
# Create the 512 MiB community vendor partition from the tail of system on the
# ZTE Axon 7 (ailsa_ii / axon7). This is the documented replacement for Oki's
# PARTY tool, whose AndroidFileHost download (fid 1322778262903995063) and XDA
# attachment are no longer obtainable (reported in issue #1).
#
# It changes ONLY the GPT of the UFS LUN that holds system (default
# /dev/block/sde, 4096-byte sectors):
#   - partition 13 system: start unchanged, end moved 512 MiB towards the start
#   - partition 28 vendor: the freed 512 MiB, name "vendor"
# Nothing else is written. It never touches boot, recovery, aboot/xbl/tz,
# modem, persist or the EFS partitions (modemst1/2, fsg, fsc).
#
# The sector numbers are read from the phone's own table, never hardcoded.
# Run it in TWRP. Default is a read-only plan; --apply writes, --yes confirms.
#
# Usage:
#   axon7-make-vendor.sh                     # print the plan (read-only)
#   axon7-make-vendor.sh --apply --yes       # write the GPT (TWRP)
#   axon7-make-vendor.sh --disk /dev/block/sde
#   axon7-make-vendor.sh --table FILE        # parse a saved `sgdisk -p` output
#   axon7-make-vendor.sh --help
#
# After --apply: reboot to recovery so the kernel reloads the table, then wipe
# System before flashing (the old ext4 filesystem is now larger than its
# partition; the ROM installer writes a fresh one). If the table write is
# interrupted, restore the backup printed by the script with
#   sgdisk --load-backup=FILE /dev/block/sde
set -u

disk=/dev/block/sde
table_file=
apply=0
yes=0

usage() { sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
	case $1 in
		--apply) apply=1 ;;
		--yes) yes=1 ;;
		--disk) disk=${2:?--disk needs a device}; shift ;;
		--table) table_file=${2:?--table needs a file}; shift ;;
		--help|-h) usage; exit 0 ;;
		*) echo "$0: unknown argument '$1' (see --help)" >&2; exit 2 ;;
	esac
	shift
done

die() { echo "axon7-make-vendor: $*" >&2; exit 1; }

if [ -n "$table_file" ]; then
	[ -r "$table_file" ] || die "cannot read $table_file"
	table=$(cat "$table_file")
	[ "$apply" = 1 ] && die "--apply needs a real device, not --table"
else
	command -v sgdisk >/dev/null 2>&1 || die "sgdisk missing (TWRP has it under /sbin)"
	[ -b "$disk" ] || die "$disk is not a block device (run in TWRP; do not point this at /dev/sda)"
	table=$(sgdisk -p "$disk") || die "cannot read the GPT of $disk"
fi

# Refuse anything that is not the Axon 7's system LUN: the layout around
# system (aboot 11, boot 12, system 13, recovery 14) is the invariant used
# here, and it was also the layout in the user report.
sector=$(echo "$table" | sed -n 's/^Sector size (logical\/physical): *\([0-9][0-9]*\).*/\1/p' | head -1)
[ -n "$sector" ] || die "cannot read the sector size from the table"
[ "$sector" = 4096 ] || die "$disk: sector size is $sector, expected 4096 (the Axon 7's system LUN); refusing"

row() {	# $1 partition number -> "number start end name"
	echo "$table" | awk -v n="$1" '$1 ~ /^[0-9]+$/ && $1 == n { print $1, $2, $3, $NF; exit }'
}
name_row() {	# $1 partition name -> "number start end name"
	echo "$table" | awk -v n="$1" '$1 ~ /^[0-9]+$/ && $NF == n { print $1, $2, $3, $NF; exit }'
}

sysrow=$(row 13)
[ -n "$sysrow" ] || die "no partition 13 on $disk"
set -- $sysrow
[ "$4" = system ] || die "partition 13 is '$4', not 'system': not the expected Axon 7 layout"
sys_start=$2
sys_end=$3

rec=$(row 14)
[ -n "$rec" ] || die "no partition 14 (recovery) on $disk: not the expected Axon 7 layout"
set -- $rec
[ "$4" = recovery ] || die "partition 14 is '$4', not 'recovery': not the expected Axon 7 layout"
[ "$sys_end" -lt "$2" ] || die "system (ends $sys_end) does not end before recovery (starts $2); refusing"

[ -z "$(name_row vendor)" ] || die "a vendor partition already exists; nothing to do"
[ -z "$(row 28)" ] || die "partition 28 is already in use; refusing"

# 512 MiB in sectors of $sector bytes (131072 for 4096-byte sectors).
vendor_sectors=$(( 512 * 1024 * 1024 / sector ))
sys_sectors=$(( sys_end - sys_start + 1 ))
[ "$sys_sectors" -gt $(( vendor_sectors + 1024 * 1024 * 1024 / sector )) ] ||
	die "system is too small ($sys_sectors sectors) to lose $vendor_sectors sectors and stay over 1 GiB"

new_end=$(( sys_end - vendor_sectors ))
ven_start=$(( new_end + 1 ))
ven_end=$sys_end

# No other partition may overlap the space the vendor partition will take.
overlap=$(echo "$table" | awk -v a="$ven_start" -v b="$ven_end" -v n=13 '
	$1 ~ /^[0-9]+$/ && $1 != n && $2 + 0 <= b && $3 + 0 >= a { print $1 " " $2 " " $3 " " $NF }')
[ -z "$overlap" ] || die "partition(s) already occupy the target range: $overlap"

echo "Axon 7 vendor partition plan (read-only until --apply --yes)"
echo "  disk:                 $disk (sector $sector bytes)"
echo "  system (13):          start $sys_start, end $sys_end  ->  end $new_end"
echo "  vendor (28, new):     start $ven_start, end $ven_end  ($(( vendor_sectors * sector / 1024 / 1024 )) MiB)"
echo ""
echo "Commands:"
echo "  sgdisk --delete=13 $disk"
echo "  sgdisk --new=13:$sys_start:$new_end --change-name=13:system $disk"
echo "  sgdisk --new=28:$ven_start:$ven_end --change-name=28:vendor $disk"
echo ""

if [ "$apply" != 1 ]; then
	echo "Nothing written. Run again with --apply --yes to write the table."
	exit 0
fi
[ "$yes" = 1 ] || die "--apply also needs --yes (this changes the partition table; back up first)"
[ -b "$disk" ] || die "$disk is not a block device"

backup_dir=${AXON7_BACKUP_DIR:-}
if [ -z "$backup_dir" ]; then
	[ -d /sdcard ] && backup_dir=/sdcard || backup_dir=/tmp
fi
backup=$backup_dir/axon7-gpt-$(date +%Y%m%d-%H%M%S).bin
sgdisk --backup="$backup" "$disk" >/dev/null || die "could not back up the GPT to $backup"
echo "old GPT saved to $backup (copy it off the phone; restore: sgdisk --load-backup=$backup $disk)"
echo "writing..."

sgdisk --delete=13 "$disk" || die "deleting partition 13 failed; the old table is saved in $backup"
sgdisk --new="13:$sys_start:$new_end" --change-name=13:system "$disk" ||
	die "recreating system failed; restore $backup"
sgdisk --new="28:$ven_start:$ven_end" --change-name=28:vendor "$disk" ||
	die "creating vendor failed; restore $backup"

after=$(sgdisk -p "$disk") || die "cannot re-read the table; restore $backup"
new_sys=$(echo "$after" | awk '$1 == 13 { print $2, $3; exit }')
new_ven=$(echo "$after" | awk '$NF == "vendor" { print $2, $3; exit }')
[ "$new_sys" = "$sys_start $new_end" ] || die "system is not at $sys_start..$new_end after writing; restore $backup"
[ "$new_ven" = "$ven_start $ven_end" ] || die "vendor is not at $ven_start..$ven_end after writing; restore $backup"

echo ""
echo "$after"
echo ""
echo "Done. Reboot to recovery so the kernel reloads the partition table,"
echo "then wipe System before flashing (the old ext4 filesystem is larger"
echo "than the new partition; the ROM writes a fresh one)."
