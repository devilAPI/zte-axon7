#!/bin/bash
# PC tests for the LineageOS 24 TWRP update-binary preflight. Runs the real
# script against fake partition tables / fake sysfs, no phone, no root.
# Checks: refuses cleanly (before any write) when model is unknown, vendor
# partition is missing, or bootloader/TZ is wrong.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
UPDATER=${LOS24_UPDATER:-$ROOT/tests/installer/los24-update-binary}
if [ ! -f "$UPDATER" ]; then
  UPDATER=$ROOT/../release24/lineageos-24-mainline/ci/zip/META-INF/com/google/android/update-binary
fi
[ -f "$UPDATER" ] || { echo "missing updater: $UPDATER" >&2; exit 1; }

TMP=$(mktemp -d /tmp/los24-preflight.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

pass=0 fail=0
ok() { echo "ok - $1"; pass=$((pass+1)); }
bad() { echo "not ok - $1"; echo "$2" | sed 's/^/# /'; fail=$((fail+1)); }

mk_fake_env() {
  local d=$TMP/env.$1
  rm -rf "$d"; mkdir -p "$d/bin" "$d/sys/class/block" "$d/dev" "$d/tmp" "$d/out"
  : > "$d/dev/sda"
  echo "$d"
}

add_part() { # env partname size_bytes dev
  local env=$1 name=$2 size=$3 dev=$4
  if [ $# -eq 5 ]; then name=$2; size=$4; dev=$5; fi
  local b=$env/sys/class/block/$dev
  mkdir -p "$b"
  printf 'PARTNAME=%s\n' "$name" > "$b/uevent"
  echo $(( (size + 511) / 512 )) > "$b/size"
  truncate -s "$size" "$env/dev/$dev"
}

write_tz() { # env dev tz_string
  local env=$1 dev=$2 tz=$3
  python3 - "$env/dev/$dev" "$tz" <<'PY'
import sys
p, tz = sys.argv[1], sys.argv[2]
with open(p, 'r+b') as f:
    f.seek(4096)
    f.write(('QC_IMAGE_VERSION_STRING=' + tz + '\n').encode())
PY
}

mk_zip() { # env flavour
  local env=$1 flavour=$2
  local z=$env/zipdir; rm -rf "$z"; mkdir -p "$z"
  printf '%s\n' "$flavour" > "$z/flavour"
  python3 - "$z/boot.img" <<'PY'
import sys
p=sys.argv[1]
b=bytearray(4096)
b[0:8]=b'ANDROID!'
cmd=b'androidboot.super_partition=system androidboot.boot_devices=soc@0/624000.ufshc firmware_class.path=/vendor/firmware\x00'
b[64:64+len(cmd)] = cmd
open(p,'wb').write(b)
PY
  cp "$z/boot.img" "$z/los-boot.img"
  python3 - "$z/super.raw.gz" <<'PY'
import sys, gzip
p=sys.argv[1]
buf=bytearray(8192)
buf[4096:4100]=b'gDla'
for i,name in enumerate([b'system',b'system_ext',b'product',b'vendor']):
    off=4608+i*64
    buf[off:off+len(name)] = name
with gzip.open(p,'wb') as f:
    f.write(bytes(buf))
PY
  local bootname=boot.img; [ "$flavour" = standalone ] || bootname=los-boot.img
  local bsha=$(sha1sum < "$z/$bootname" | cut -d' ' -f1)
  local ssha=$(python3 -c "import gzip,hashlib;print(hashlib.sha1(gzip.open('$z/super.raw.gz','rb').read()).hexdigest())")
  printf '%s\n' "$bsha" > "$z/$bootname.sha1"
  printf '%s\n' "$ssha" > "$z/super.raw.sha1"
  local bsize=$(stat -c%s "$z/$bootname")
  local ssize=$(python3 -c "import gzip,os;print(len(gzip.open('$z/super.raw.gz','rb').read()))")
  printf '%s %s\n' "$ssize" "$bsize" > "$z/sizes"
  (cd "$z" && zip -0 -q "$env/out/test.zip" flavour sizes super.raw.sha1 super.raw.gz "$bootname" "$bootname.sha1")
  echo "$env/out/test.zip"
}

mk_getprop() { # env device model twrp
  local env=$1 dev=$2 model=$3 twrp=$4
  cat > "$env/bin/getprop" <<SH
#!/bin/sh
case "\$1" in
  ro.product.device) echo "$dev" ;;
  ro.product.model) echo "$model" ;;
  ro.twrp.version) echo "$twrp" ;;
  *) echo "" ;;
esac
SH
  chmod +x "$env/bin/getprop"
}

common_stubs() {
  local env=$1
  for cmd in mount umount mkfs.ext4 mkfs.f2fs make_ext4fs sync; do
    printf '#!/bin/sh\nexit 0\n' > "$env/bin/$cmd"; chmod +x "$env/bin/$cmd"
  done
}

run_updater_capture() { # env zip
  local env=$1 zip=$2
  local ui=$env/out/ui.txt rc=$env/out/rc
  : > "$ui"
  set +e
  PATH="$env/bin:$PATH" \
  AXON7_TEST_SYS_BLOCK="$env/sys/class/block" \
  AXON7_TEST_BLOCK_DEV="$env/dev" \
  AXON7_TEST_TMP="$env/tmp" \
  bash -c 'exec 3> >(cat >> "$1"); shift; sh "$@"; rc=$?; exec 3>&-; wait; exit $rc' _ "$ui" "$UPDATER" 3 3 "$zip" >"$env/out/stdout" 2>"$env/out/stderr"
  echo $? > "$rc"
  set -e
}

assert_refused_before_write() { # env name pattern
  local env=$1 name=$2 pat=$3
  local ui=$env/out/ui.txt rc
  rc=$(cat "$env/out/rc")
  if [ "$rc" = "0" ]; then bad "$name" "expected non-zero exit, got 0; ui: $(cat "$ui")"; return; fi
  if ! grep -Eq "$pat" "$ui"; then bad "$name" "expected pattern '$pat' in ui: $(cat "$ui")"; return; fi
  if grep -Eq "Writing system|Writing boot|Writing los_boot|Erasing LineageOS data|Formatting cache" "$ui"; then
    bad "$name" "write happened before refusal; ui: $(cat "$ui")"; return
  fi
  ok "$name"
}

setup_standalone_good() {
  local env=$1
  mk_getprop "$env" ailsa_ii A2017G 3.3.0-0
  common_stubs "$env"
  add_part "$env" system  system  8388608  sda
  add_part "$env" boot    boot    1048576  sdb
  add_part "$env" userdata userdata 8388608 sdc
  add_part "$env" cache   cache   4194304  sdd
  add_part "$env" vendor  vendor  536870912 sde
  add_part "$env" tz      tz      4194304  sdf
  write_tz "$env" sdf "TZ.BF.4.0.1-00353"
}

setup_multiboot_good() {
  local env=$1
  mk_getprop "$env" ailsa_ii A2017G 3.3.0-0
  common_stubs "$env"
  add_part "$env" system       system       8388608 sda
  add_part "$env" boot         boot         1048576 sdb
  add_part "$env" los_boot     los_boot     1048576 sdc
  add_part "$env" los_metadata los_metadata 1048576 sdd
  add_part "$env" los_data     los_data     4194304 sde
  add_part "$env" vendor       vendor       536870912 sdf
  add_part "$env" tz           tz           4194304  sdg
  write_tz "$env" sdg "TZ.BF.4.0.1-00353"
}

# 1. Unknown/wrong device model
env=$(mk_fake_env unknown-model)
mk_getprop "$env" hammerhead Nexus5 3.3.0-0
common_stubs "$env"
add_part "$env" system system 8388608 sda
add_part "$env" boot boot 1048576 sdb
add_part "$env" userdata userdata 8388608 sdc
add_part "$env" cache cache 4194304 sdd
add_part "$env" vendor vendor 536870912 sde
add_part "$env" tz tz 4194304 sdf
write_tz "$env" sdf "TZ.BF.4.0.1-00353"
zip=$(mk_zip "$env" standalone)
run_updater_capture "$env" "$zip"
assert_refused_before_write "$env" "standalone: refuses unknown device" "ZTE Axon 7|device"

# 2. Unknown model string
env=$(mk_fake_env unknown-model-str)
mk_getprop "$env" ailsa_ii "SomeOtherPhone" 3.3.0-0
common_stubs "$env"
add_part "$env" system system 8388608 sda
add_part "$env" boot boot 1048576 sdb
add_part "$env" userdata userdata 8388608 sdc
add_part "$env" cache cache 4194304 sdd
add_part "$env" vendor vendor 536870912 sde
add_part "$env" tz tz 4194304 sdf
write_tz "$env" sdf "TZ.BF.4.0.1-00353"
zip=$(mk_zip "$env" standalone)
run_updater_capture "$env" "$zip"
assert_refused_before_write "$env" "standalone: refuses unknown model string" "A2017G/A2017U|model"

# 3. Missing vendor partition (standalone)
env=$(mk_fake_env no-vendor-standalone)
setup_standalone_good "$env"
rm -rf "$env/sys/class/block/sde" "$env/dev/sde"
zip=$(mk_zip "$env" standalone)
run_updater_capture "$env" "$zip"
assert_refused_before_write "$env" "standalone: refuses missing vendor partition" "no vendor partition|vendor partition"

# 4. Missing vendor partition (multiboot)
env=$(mk_fake_env no-vendor-multiboot)
setup_multiboot_good "$env"
rm -rf "$env/sys/class/block/sdf" "$env/dev/sdf"
python3 - "$env/dev/sdb" <<'PY'
import gzip,sys
p=sys.argv[1]
buf=bytearray(2*1024*1024)
buf[0:8]=b'ANDROID!'
payload=gzip.compress(b'xx LineageOS xx')
buf[4096:4096+len(payload)] = payload
open(p,'r+b').write(buf)
PY
zip=$(mk_zip "$env" multiboot)
run_updater_capture "$env" "$zip"
assert_refused_before_write "$env" "multiboot: refuses missing vendor partition" "no vendor partition|vendor partition"

# 5. Wrong TZ / bootloader
env=$(mk_fake_env bad-tz)
setup_standalone_good "$env"
write_tz "$env" sdf "TZ.BF.4.0.1-00001"
zip=$(mk_zip "$env" standalone)
run_updater_capture "$env" "$zip"
assert_refused_before_write "$env" "standalone: refuses wrong TrustZone/bootloader" "TrustZone|TZ\.BF\.4\.0\.1-00353|bootloader"

# 6. Missing TZ
env=$(mk_fake_env no-tz)
setup_standalone_good "$env"
rm -rf "$env/sys/class/block/sdf" "$env/dev/sdf"
zip=$(mk_zip "$env" standalone)
run_updater_capture "$env" "$zip"
assert_refused_before_write "$env" "standalone: refuses missing/unreadable TrustZone" "TrustZone|tz partition|bootloader"

echo ""
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
