#!/bin/sh
# Static tests for tools/axon7-preflight.sh, tools/axon7-make-vendor.sh and
# tools/axon7-cellular-diag.sh. No phone and no root: the scripts' fixtures
# live under a temporary folder (AXON7_ROOT / --table / --props). Run:
# tools/test-axon7-variant.sh
set -u
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/axon7-tools.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT
fail=0
pass=0

check() {	# check DESCRIPTION COMMAND...
	d=$1; shift
	if "$@" >"$tmp/out" 2>"$tmp/err"; then
		printf '  ok    %s\n' "$d"; pass=$((pass + 1))
	else
		printf '  FAIL  %s\n' "$d"; sed 's/^/        /' "$tmp/out" "$tmp/err" | tail -20
		fail=$((fail + 1))
	fi
}
check_fails() {
	d=$1; shift
	if "$@" >"$tmp/out" 2>"$tmp/err"; then
		printf '  FAIL  %s (unexpected success)\n' "$d"; fail=$((fail + 1))
	else
		printf '  ok    %s\n' "$d"; pass=$((pass + 1))
	fi
}

check_rc() {	# check_rc WANTED_STATUS DESCRIPTION COMMAND...
	want=$1
	d=$2
	shift 2
	if "$@" >"$tmp/out" 2>"$tmp/err"; then got=0; else got=$?; fi
	if [ "$got" = "$want" ]; then
		printf '  ok    %s\n' "$d"; pass=$((pass + 1))
	else
		printf '  FAIL  %s (exit %d, want %d)\n' "$d" "$got" "$want"
		sed 's/^/        /' "$tmp/out" "$tmp/err" | tail -20
		fail=$((fail + 1))
	fi
}
check_grep() {	# check_grep DESCRIPTION PATTERN COMMAND... (exit status ignored)
	d=$1; p=$2; shift 2
	"$@" >"$tmp/out" 2>"$tmp/err"
	if grep -q -- "$p" "$tmp/out"; then
		printf '  ok    %s\n' "$d"; pass=$((pass + 1))
	else
		printf '  FAIL  %s (pattern: %s)\n' "$d" "$p"
		sed 's/^/        /' "$tmp/out" "$tmp/err" | tail -20
		fail=$((fail + 1))
	fi
}

# --- syntax ---------------------------------------------------------------
printf 'syntax\n'
for s in axon7-preflight.sh axon7-make-vendor.sh axon7-cellular-diag.sh; do
	check "sh -n $s" sh -n "$here/$s"
	check "dash -n $s" dash -n "$here/$s"
	if command -v busybox >/dev/null 2>&1; then
		check "busybox ash -n $s" busybox ash -n "$here/$s"
	fi
done

# --- fixtures -------------------------------------------------------------
mkroot() {
	r=$1
	mkdir -p "$r/dev/block/bootdevice/by-name" "$r/sys/class/block" "$r/dev/block/mmcblk0"
}
mkpart() {	# mkpart ROOT NAME SIZE_512_SECTORS
	r=$1; n=$2; sz=$3
	: > "$r/dev/block/bootdevice/by-name/$n"
	mkdir -p "$r/sys/class/block/$n"
	echo "$sz" > "$r/sys/class/block/$n/size"
}
mkfs_magic() {	# mkfs_magic FILE f2fs|ext4|blank
	f=$1; t=$2
	case $t in
		f2fs) printf '\020\040\365\362' | dd of="$f" bs=1 seek=1024 conv=notrunc 2>/dev/null ;;
		ext4) printf '\123\357' | dd of="$f" bs=1 seek=1080 conv=notrunc 2>/dev/null ;;
		blank) : > "$f" ;;
	esac
}
props=$tmp/props-a2017u
cat > "$props" <<'EOF'
ro.product.device=ailsa_ii
ro.product.model=A2017U
ro.lineage.version=22.2-20261109-UNOFFICIAL-axon7
ro.bootloader=unknown
EOF
props_g=$tmp/props-a2017g
cat > "$props_g" <<'EOF'
ro.product.device=ailsa_ii
ro.product.model=A2017G
ro.lineage.version=24.0-...
EOF
props_noband=$tmp/props-noband
cat > "$props_noband" <<'EOF'
ro.product.device=ailsa_ii
ro.product.model=A2017U
EOF
props_boot=$tmp/props-boot
cat > "$props_boot" <<'EOF'
ro.boot.product.device=ailsa_ii
ro.boot.product.model=A2017U
ro.boot.bootloader=TZ.BF.4.0.1-00353
EOF
props_band=$tmp/props-a2017u-band
cat > "$props_band" <<'EOF'
ro.product.device=ailsa_ii
ro.product.model=A2017U
ro.lineage.version=22.2-20261109-UNOFFICIAL-axon7
ro.bootloader=TZ.BF.4.0.1-00353
gsm.version.baseband=4-M8996FAAAANAZM-2 1 [Nov 02 2017]
EOF

r1=$tmp/r1
mkroot "$r1"
mkpart "$r1" tz 4096
printf 'QC_IMAGE_VERSION_STRING=TZ.BF.4.0.1-00353\n' > "$r1/dev/block/bootdevice/by-name/tz"
mkpart "$r1" userdata 104857600
mkfs_magic "$r1/dev/block/bootdevice/by-name/userdata" f2fs
mkpart "$r1" vendor 1048576
mkfs_magic "$r1/dev/block/bootdevice/by-name/vendor" ext4
for p in boot los_boot los_metadata los_data system; do mkpart "$r1" "$p" 204800; done
printf 'boot menu: LineageOS\n' > "$r1/dev/block/bootdevice/by-name/boot"

r2=$tmp/r2	# ext4 userdata, for the passing los22 case
cp -r "$r1" "$r2"
: > "$r2/dev/block/bootdevice/by-name/userdata"
mkfs_magic "$r2/dev/block/bootdevice/by-name/userdata" ext4

r3=$tmp/r3	# los24 without los_data
cp -r "$r1" "$r3"
rm -f "$r3/dev/block/bootdevice/by-name/los_data" "$r3/sys/class/block/los_data/size"

r4=$tmp/r4	# stock layout: ext4 userdata, no vendor partition
cp -r "$r2" "$r4"
rm -f "$r4/dev/block/bootdevice/by-name/vendor" "$r4/sys/class/block/vendor/size"

# --- preflight ------------------------------------------------------------
printf 'preflight\n'
check_grep "A2017U is recognised" "variant: A2017U" \
	env AXON7_ROOT="$r1" "$here/axon7-preflight.sh" --props "$props" --rom los22
check_fails "los22 refuses f2fs /data" \
	env AXON7_ROOT="$r1" "$here/axon7-preflight.sh" --props "$props" --rom los22
check_grep "f2fs message names the first-boot symptom" "invalid magic" \
	env AXON7_ROOT="$r1" "$here/axon7-preflight.sh" --props "$props" --rom los22
check "los22 passes with ext4 /data and vendor" \
	env AXON7_ROOT="$r2" "$here/axon7-preflight.sh" --props "$props" --rom los22
check "los22 passes without vendor (stock layout; warning only)" \
	env AXON7_ROOT="$r4" "$here/axon7-preflight.sh" --props "$props" --rom los22
check_grep "los22 warns about the missing vendor partition" "stock-layout image" \
	env AXON7_ROOT="$r4" "$here/axon7-preflight.sh" --props "$props" --rom los22
check_fails "los24 still refuses a missing vendor partition" \
	env AXON7_ROOT="$r4" "$here/axon7-preflight.sh" --props "$props" --rom los24
check "los24 passes with the multi-boot partitions" \
	env AXON7_ROOT="$r1" "$here/axon7-preflight.sh" --props "$props" --rom los24
check_fails "los24 refuses a missing los_data" \
	env AXON7_ROOT="$r3" "$here/axon7-preflight.sh" --props "$props" --rom los24
check "generic does not fail on f2fs (Nura/iOS do not use it)" \
	env AXON7_ROOT="$r1" "$here/axon7-preflight.sh" --props "$props"

# --- cellular diag ---------------------------------------------------------
printf 'cellular-diag\n'
check "cellular-diag --help" "$here/axon7-cellular-diag.sh" --help
check_rc 2 "cellular-diag rejects an unknown ROM" "$here/axon7-cellular-diag.sh" --rom bogus
check_rc 0 "cellular-diag: A2017U los22 with modem up -> clean" \
	"$here/axon7-cellular-diag.sh" --rom los22 --props "$props_band"
check_grep "cellular-diag: A2017U is recognised" "variant: A2017U" \
	"$here/axon7-cellular-diag.sh" --rom los22 --props "$props"
check_grep "cellular-diag: reports the modem firmware version" "modem firmware version: 4-M8996" \
	"$here/axon7-cellular-diag.sh" --rom los22 --props "$props_band"
check_fails "cellular-diag: A2017U los22 without modem (empty gsm.version.baseband) -> FAIL" \
	"$here/axon7-cellular-diag.sh" --rom los22 --props "$props_noband"
check_grep "cellular-diag: A2017G / los24 recognised" "variant: A2017G" \
	"$here/axon7-cellular-diag.sh" --rom los24 --props "$props_g"
check_grep "cellular-diag: boot properties win over runtime props" "variant: A2017U" \
	"$here/axon7-cellular-diag.sh" --rom los22 --props "$props_boot"

# --- make-vendor ----------------------------------------------------------
# Real A2017G table from the PARTY thread, before the vendor partition was
# created (4096-byte sectors): system starts 54922, ends 1627785; recovery
# starts 1627786.
table=$tmp/table.txt
cat > "$table" <<'EOF'
Found valid GPT with protective MBR; using GPT.
Disk /dev/block/sde: 1663995 sectors, 6.3 GiB
Sector size (logical/physical): 4096/4096 bytes
Disk identifier (GUID): 00000000-0000-0000-0000-000000000000
Partition table holds up to 12 entries
First usable sector is 6, last usable sector is 1663989
Partitions will be aligned on 2-sector boundaries
Total free space is 15763 sectors (61.6 MiB)

Number  Start (sector)    End (sector)  Size       Code  Name
   1               6             133   512.0 KiB   FFFF  rpm
   2             134             645   2.0 MiB     FFFF  tz
  11           38282           38537   1024.0 KiB  FFFF  aboot
  12           38538           54921   64.0 MiB    FFFF  boot
  13           54922         1627785   6.0 GiB     8300  system
  14         1627786         1644169   64.0 MiB    FFFF  recovery
  28         1496714         1627785   512.0 MiB   8300  other
EOF
# The fixture above intentionally has partition 28 occupied -> must be refused.
check_fails "make-vendor refuses an occupied partition 28" \
	"$here/axon7-make-vendor.sh" --table "$table"
sed -i '/^ *28 /d' "$table"
check_grep "plan shrinks system to 1496713" "--new=13:54922:1496713" \
	"$here/axon7-make-vendor.sh" --table "$table"
check_grep "plan creates vendor 1496714..1627785" "--new=28:1496714:1627785" \
	"$here/axon7-make-vendor.sh" --table "$table"
check_grep "plan is read-only by default" "Nothing written" \
	"$here/axon7-make-vendor.sh" --table "$table"
sed 's/4096\/4096/512\/512/' "$table" > "$tmp/table-512.txt"
check_fails "make-vendor refuses a non-4096-sector disk" \
	"$here/axon7-make-vendor.sh" --table "$tmp/table-512.txt"
sed 's/ system$/ notsystem/' "$table" > "$tmp/table-wrong.txt"
check_fails "make-vendor refuses an unexpected layout" \
	"$here/axon7-make-vendor.sh" --table "$tmp/table-wrong.txt"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
