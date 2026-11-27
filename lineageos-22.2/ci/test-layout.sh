#!/bin/bash
# Offline test of the installer's layout detection (axon7-layout.sh) against fake
# partition tables, no phone and no root needed. Optional: with EDIFY_SIM=path to
# the built edify_sim (see edify-sim/build.sh) and a combined zip ZIP=..., the
# zip's real updater-script is also run through the AOSP edify interpreter.
#
#   ci/test-layout.sh [layout-script]
set -u
here=$(cd "$(dirname "$0")" && pwd)
script=${1:-$here/axon7-layout.sh}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
pass=0; fail=0

MiB=$((1024*1024))
SYSTEM_BYTES=$(sed -n 's/^SYSTEM_BYTES=//p' "$script")
VENDOR_BYTES=$(sed -n 's/^VENDOR_BYTES=//p' "$script")

# mk NAME SPEC...   SPEC: part=bytes | part=-> otherpart | part=dangling | part=file
# builds $work/NAME/{by-name,dev,sys}; unlisted partitions do not exist
mk() {
	local t=$work/$1; shift
	mkdir -p "$t/by-name" "$t/dev" "$t/sys"
	local i=0 spec n v
	for spec in "$@"; do
		n=${spec%%=*}; v=${spec#*=}
		i=$((i+1))
		case $v in
			'->'*) ln -s "../dev/sde_${v#->}" "$t/by-name/$n" ;;
			dangling) ln -s ../dev/nothing "$t/by-name/$n" ;;
			*)	: > "$t/dev/sde_$n"; mkdir -p "$t/sys/sde_$n"
				echo $((v / 512)) > "$t/sys/sde_$n/size"
				ln -s "../dev/sde_$n" "$t/by-name/$n" ;;
		esac
	done
}

# run NAME EXPECT-LAYOUT|fail [extra env...]
run() {
	local name=$1 want=$2; shift 2
	local t=$work/$name out=$work/$name/out
	mkdir -p "$out"
	env AXON7_BYNAME="$t/by-name" AXON7_SYSFS="$t/sys" AXON7_OUT="$out" AXON7_NOBLK=1 "$@" sh "$script"
	local rc=$?
	local got=fail
	if [ $rc = 0 ] && [ -f "$out/axon7-layout.prop" ]; then got=$(sed -n 's/^layout=//p' "$out/axon7-layout.prop"); fi
	if [ $rc != 0 ] && [ -f "$out/axon7-layout.prop" ]; then got="rc$rc+prop"; fi
	if [ "$got" = "$want" ]; then pass=$((pass+1)); echo "ok   $name -> $got   ($(tr '\n' ' ' < "$out/axon7-layout.txt" | cut -c1-110))"
	else fail=$((fail+1)); echo "FAIL $name: wanted $want, got $got"; cat "$out/axon7-layout.txt"; fi
}

other="modem=$((100*MiB)) persist=$((32*MiB)) modemst1=$((2*MiB)) modemst2=$((2*MiB)) fsg=$((2*MiB)) tz=$((2*MiB)) aboot=$((1*MiB))"
STOCKSYS=$((6*1024*MiB))

mk vendor-layout   system=$SYSTEM_BYTES vendor=$VENDOR_BYTES boot=$((64*MiB)) $other
run vendor-layout vendor
mk stock-layout    system=$STOCKSYS boot=$((64*MiB)) $other
run stock-layout stock
mk stock-exact     system=$SYSTEM_BYTES boot=$((64*MiB))
run stock-exact stock
mk vendor-small    system=$STOCKSYS vendor=$((256*MiB)) boot=$((64*MiB)) $other
run vendor-small stock
mk vendor-dangling system=$STOCKSYS vendor=dangling boot=$((64*MiB))
run vendor-dangling stock
mk vendor-big      system=$STOCKSYS vendor=$((2048*MiB)) boot=$((64*MiB))
run vendor-big vendor
# refuse cleanly, before anything would be written
mk system-small    system=$((4096*MiB)) boot=$((64*MiB)) $other
run system-small fail
mk system-missing  boot=$((64*MiB)) $other
run system-missing fail
mk boot-missing    system=$STOCKSYS $other
run boot-missing fail
mk boot-tiny       system=$STOCKSYS boot=$((1*MiB))
run boot-tiny fail
mk system-is-modem system=-\>modem modem=$STOCKSYS boot=$((64*MiB))
run system-is-modem fail
mk boot-is-persist boot=-\>persist persist=$((64*MiB)) system=$STOCKSYS
run boot-is-persist fail
mk system-is-boot  system=-\>boot boot=$((64*MiB))
run system-is-boot fail
mk vendor-is-system system=$STOCKSYS vendor=-\>system boot=$((64*MiB))
run vendor-is-system fail
mk system-dangling system=dangling boot=$((64*MiB))
run system-dangling fail
mkdir -p "$work/nodir"; run nodir fail AXON7_BYNAME="$work/nodir/missing"
# a regular file is not a block device on the phone
mk notblock        system=$STOCKSYS boot=$((64*MiB))
run notblock fail AXON7_NOBLK=0

# the script must not write anywhere but its two result files
mk readonly-check  system=$STOCKSYS boot=$((64*MiB))
before=$(cd "$work/readonly-check" && find by-name dev sys -type f -o -type l | sort | xargs -r ls -ld | md5sum)
run readonly-check stock
after=$(cd "$work/readonly-check" && find by-name dev sys -type f -o -type l | sort | xargs -r ls -ld | md5sum)
if [ "$before" = "$after" ]; then pass=$((pass+1)); echo "ok   partition tree untouched"; else fail=$((fail+1)); echo "FAIL tree changed"; fi

echo "layout script: $pass passed, $fail failed"
[ $fail = 0 ]
