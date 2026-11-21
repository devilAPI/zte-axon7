#!/bin/bash
# Offline harness for ci/zip/META-INF/com/google/android/update-binary.
# Fake block devices + stubbed TWRP commands; never touches a phone. Builds
# tiny zips with a valid Android boot cmdline and LP metadata, then checks the
# standalone write path, the developer multi-boot path, all refusal paths and
# that every mount is released by the EXIT trap. Run from anywhere:
#   lineageos-24-mainline/ci/test-installer.sh
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
src=$here/zip/META-INF/com/google/android/update-binary
work=${XDG_CACHE_HOME:-$HOME/.cache}/los24-updater-test
if [ "${KEEP_WORK:-0}" = 1 ]; then
	trap 'echo "fixtures kept at $work"' EXIT
else
	trap 'rm -rf "$work"' EXIT
fi
rm -rf "$work"
mkdir -p "$work"/{bin,tmp,fixture/etc/firmware,fixture/vendor/firmware,empty}
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "ok: $*"; }

# ---- tiny zips: 4 MiB raw "super" with the LP magic and partition names ----
python3 - "$work" <<'PY'
import gzip, hashlib, os, struct, sys, zipfile
w = sys.argv[1]


def super_raw(with_magic=True, with_names=True):
    raw = bytearray(4 << 20)
    if with_magic:
        raw[4096:4100] = struct.pack('<I', 0x616c4467)  # "gDla"
        raw[8192:8196] = struct.pack('<I', 0x414c5030)  # "0PLA"
        if with_names:
            names = b'system\0system_ext\0product\0vendor\0axon7m_dynamic_partitions\0'
            raw[8200:8200 + len(names)] = names
    return bytes(raw)


def boot_img(cmdline):
    b = bytearray(4096)
    b[:8] = b'ANDROID!'
    struct.pack_into('<9I', b, 8, 0, 0, 0, 0, 0, 0, 0, 4096, 0)
    b[64:64 + len(cmdline)] = cmdline
    return bytes(b)


GOOD = (b'androidboot.hardware=axon7m androidboot.super_partition=system '
        b'androidboot.boot_devices=soc@0/624000.ufshc firmware_class.path=/vendor/firmware')
BAD = GOOD.replace(b'androidboot.super_partition=system', b'androidboot.super_partition=WRONG')


def write_zip(name, flavour, boot, raw, sha=None, mb=False):
    bootname = 'los-boot.img' if mb else 'boot.img'
    if mb:  # the shim's menu test looks for this label in the first 16 MiB
        boot = boot[:600] + b'LineageOS' + boot[609:]
    data = {
        'flavour': flavour.encode(),
        'sizes': f'{len(raw)} {len(boot)}'.encode(),
        'super.raw.sha1': (sha or hashlib.sha1(raw).hexdigest()).encode(),
        'super.raw.gz': gzip.compress(raw, compresslevel=1, mtime=0),
        bootname: boot,
        bootname + '.sha1': hashlib.sha1(boot).hexdigest().encode(),
    }
    with zipfile.ZipFile(os.path.join(w, name), 'w', zipfile.ZIP_STORED) as z:
        for k, v in data.items():
            z.writestr(k, v)


raw = super_raw()
write_zip('test.zip', 'standalone', boot_img(GOOD), raw)
write_zip('badcmd.zip', 'standalone', boot_img(BAD), raw)
write_zip('nomagic.zip', 'standalone', boot_img(GOOD), super_raw(with_magic=False))
write_zip('badsuper.zip', 'standalone', boot_img(GOOD), super_raw(with_names=False))
write_zip('badsha.zip', 'standalone', boot_img(GOOD), raw, sha='0' * 40)
write_zip('multiboot.zip', 'multiboot', boot_img(GOOD), raw, mb=True)
PY

# ---- TWRP command stubs ----------------------------------------------------
cat > "$work/bin/getprop" <<'EOS'
#!/bin/sh
[ "$1" = ro.product.device ] && echo "${FAKE_DEVICE:-ailsa_ii}"
[ "$1" = ro.twrp.version ] && echo "${FAKE_TWRP:-3.3.0-0}"
exit 0
EOS
cat > "$work/bin/mount" <<'EOS'
#!/bin/sh
for a in "$@"; do last=$a; done
case "$last" in
  */old) mkdir -p "$last"; [ ! -d "${FAKE_FIXTURE:?}/etc" ] || cp -r "$FAKE_FIXTURE/etc" "$last/" 2>/dev/null || true ;;
  */v) mkdir -p "$last"; [ ! -d "$FAKE_FIXTURE/vendor" ] || cp -r "$FAKE_FIXTURE/vendor/." "$last/" 2>/dev/null ;;
  */cache) mkdir -p "$last" ;;
esac
exit 0
EOS
cat > "$work/bin/umount" <<'EOS'
#!/bin/sh
echo "UMOUNT $*" >> "${FAKE_UMOUNT_LOG:?}"
exit 0
EOS
cat > "$work/bin/dd" <<'EOS'
#!/bin/bash
args=()
for a in "$@"; do
  case "$a" in
    of=/dev/block/*) args+=("of=${FAKE_ROOT}/dest/${a##*/}") ;;
    if=/dev/block/*) args+=("if=${FAKE_ROOT}/dest/${a##*/}") ;;
    *) args+=("$a") ;;
  esac
done
echo "DD $*" >> "${FAKE_LOG:?}"
exec /bin/dd "${args[@]}"
EOS
for t in mkfs.ext4 mkfs.f2fs make_ext4fs; do
	cat > "$work/bin/$t" <<'EOS'
#!/bin/sh
echo "MKFS $0 $*" >> "${FAKE_LOG:?}"
exit 0
EOS
done
chmod +x "$work/bin/"*
sed -e "s#/sys/class/block#$work/sys/class/block#g" \
    -e "s#/tmp#$work/tmp#g" -e "s#/cache#$work/cache#g" "$src" > "$work/update-binary-test"
chmod +x "$work/update-binary-test"

# each firmware file is marked so the harness can tell which source was used
for f in mdt b00 b01 b02 b03 b04 b05 b06 b07; do
	echo SYSTEM > "$work/fixture/etc/firmware/a530_zap.$f"
	echo VENDOR > "$work/fixture/vendor/firmware/a530_zap.$f"
done

setup_partitions() {	# $1 = with vendor (0/1), $2 = with metadata (0/1)
	rm -rf "$work/sys" "$work/dest" "$work/cache"
	mkdir -p "$work/sys/class/block" "$work/dest"
	for spec in system:sde13:24576 boot:sde12:2048 userdata:sda9:16384 cache:sda2:8192 \
		    los_boot:sde27:2048 los_metadata:sda4:0 los_data:sda5:0; do
		name=${spec%%:*}; rest=${spec#*:}; dev=${rest%%:*}; sectors=${rest##*:}
		mkdir -p "$work/sys/class/block/$dev"
		echo "PARTNAME=$name" > "$work/sys/class/block/$dev/uevent"
		echo "$sectors" > "$work/sys/class/block/$dev/size"
		truncate -s $((sectors * 512)) "$work/dest/$dev"
	done
	if [ "$1" = 1 ]; then
		mkdir -p "$work/sys/class/block/sde28"
		echo PARTNAME=vendor > "$work/sys/class/block/sde28/uevent"
		echo 0 > "$work/sys/class/block/sde28/size"
		truncate -s 0 "$work/dest/sde28"
	fi
	if [ "$2" = 1 ]; then
		mkdir -p "$work/sys/class/block/sda3"
		echo PARTNAME=metadata > "$work/sys/class/block/sda3/uevent"
		echo 0 > "$work/sys/class/block/sda3/size"
		truncate -s 0 "$work/dest/sda3"
	fi
	: > "$work/log"; : > "$work/umounts"
}

run() {	# $1 = case name, $2 = zip, rest = env overrides as KEY=VAL
	name=$1; zip=$2; shift 2
	env -i PATH="$work/bin:/usr/bin:/bin" HOME="$HOME" \
		FAKE_ROOT="$work" FAKE_FIXTURE="$work/fixture" FAKE_LOG="$work/log" \
		FAKE_UMOUNT_LOG="$work/umounts" "$@" \
		sh "$work/update-binary-test" 3 1 "$work/$zip" 2>&1 | cat > "$work/out-$name"
	# OUTFD is /proc/self/fd/1: as a pipe it behaves like TWRP's output pipe
	# (writing to a plain file there would truncate it on every ui_print).
	echo "${PIPESTATUS[0]}" > "$work/rc-$name"
}
expect_rc() { [ "$(cat "$work/rc-$1")" = "$2" ] || { cat "$work/out-$1"; fail "$1: rc $(cat "$work/rc-$1") != $2"; }; }
expect_msg() { grep -q "$2" "$work/out-$1" || { cat "$work/out-$1"; fail "$1: no message '$2'"; }; }
expect_no_write() {	# nothing written to any fake partition
	grep -q 'DD .*of=/dev/block' "$work/log" && { cat "$work/log"; fail "$1 wrote a partition"; }
	grep -q '^MKFS' "$work/log" && { cat "$work/log"; fail "$1 formatted a partition"; }
}
super_sha_ok() { [ "$(sha1sum "$work/dest/sde13" | cut -d' ' -f1)" = "$(unzip -p "$work/test.zip" super.raw.sha1)" ]; }
boot_sha_ok() { [ "$(sha1sum "$work/dest/sde12" | cut -d' ' -f1)" = "$(unzip -p "$work/test.zip" boot.img.sha1)" ]; }

# ---- standalone, no vendor partition, real `metadata` partition present ----
setup_partitions 0 1
run standalone test.zip
expect_rc standalone 0
super_sha_ok || fail "standalone: super hash"
boot_sha_ok || fail "standalone: boot hash"
[ "$(find "$work/cache/axon7-fw" -type f | wc -l)" = 9 ] || fail "standalone: firmware not staged"
grep -q '^SYSTEM$' "$work/cache/axon7-fw/a530_zap.mdt" || fail "standalone: wrong firmware source"
grep -q 'mkfs.ext4' "$work/log" || fail "standalone: cache not formatted ext4"
grep -q 'mkfs.f2fs' "$work/log" || fail "standalone: userdata not formatted"
grep -q 'DD .*of=/dev/block/sda3' "$work/log" || fail "standalone: metadata partition not wiped"
grep -q 'UMOUNT .*cache' "$work/umounts" || fail "standalone: cache not unmounted"
ok "standalone (no vendor, metadata present): writes + staging + unmount"

# ---- standalone without a metadata partition: no wipe attempt ----
setup_partitions 0 0
run nometa test.zip
expect_rc nometa 0
! grep -q 'sda3' "$work/log" || fail "nometa: wiped a non-existent metadata partition"
ok "standalone without metadata partition: no metadata write"

# ---- physical vendor partition is the preferred firmware source ----
setup_partitions 1 1
run vendor test.zip
expect_rc vendor 0
grep -q '^VENDOR$' "$work/cache/axon7-fw/a530_zap.mdt" || fail "vendor: source not preferred"
ok "standalone with vendor partition: a530_zap sourced from vendor"

# ---- refusals before any write --------------------------------------------
setup_partitions 0 1
run wrongdev test.zip FAKE_DEVICE=htc
expect_rc wrongdev 1; expect_msg wrongdev "this zip is for the ZTE Axon 7"; expect_no_write wrongdev
run oldtwrp test.zip FAKE_TWRP=3.2.1-8
expect_rc oldtwrp 1; expect_msg oldtwrp "too old"; expect_no_write oldtwrp
run nofirmware test.zip FAKE_FIXTURE="$work/empty"
expect_rc nofirmware 1; expect_msg nofirmware "no a530_zap GPU firmware"; expect_no_write nofirmware
grep -q 'UMOUNT .*old' "$work/umounts" || fail "nofirmware: trap did not unmount old system"
run badcmd badcmd.zip
expect_rc badcmd 1; expect_msg badcmd "androidboot.super_partition=system"; expect_no_write badcmd
run nomagic nomagic.zip
expect_rc nomagic 1; expect_msg nomagic "no Android logical-partition metadata"; expect_no_write nomagic
run badsuper badsuper.zip
expect_rc badsuper 1; expect_msg badsuper "no logical partition 'system'"; expect_no_write badsuper
ok "refusals: wrong device, old TWRP, no firmware, bad cmdline, bad super magic/names (no writes)"

# ---- trap releases mounts after a failure past the staging step ------------
setup_partitions 0 1
run badsha badsha.zip
expect_rc badsha 1; expect_msg badsha "does not read back correctly"
grep -q 'UMOUNT .*cache' "$work/umounts" || fail "badsha: trap did not unmount cache"
grep -q 'UMOUNT .*old' "$work/umounts" || fail "badsha: trap did not unmount old system"
ok "trap: cache and old-system mounts released on a late failure"

# ---- developer multi-boot flavour still works ------------------------------
setup_partitions 0 1
printf 'LineageOS' > "$work/dest/sde12"
run multiboot multiboot.zip
expect_rc multiboot 0
[ "$(sha1sum "$work/dest/sde13" | cut -d' ' -f1)" = "$(unzip -p "$work/multiboot.zip" super.raw.sha1)" ] || fail "multiboot: super hash"
[ "$(sha1sum "$work/dest/sde27" | cut -d' ' -f1)" = "$(unzip -p "$work/multiboot.zip" los-boot.img.sha1)" ] || fail "multiboot: los_boot hash"
! grep -q 'mkfs.ext4' "$work/log" || fail "multiboot: formatted cache"
ok "multiboot: super + los_boot written, cache untouched"

# ---- firmware lookup: the built /vendor/firmware links --------------------
# Kernel cmdline has firmware_class.path=/vendor/firmware; Soong installs the
# generator's symlinks into the vendor image. List both flavours and verify
# the committed Android.bp is the standalone variant.
gen=$here/../scripts/gen-firmware-links.py
bp=$here/../device/zte/axon7m/firmware/Android.bp
for flavour in standalone multiboot; do
	python3 "$gen" --flavour "$flavour" --dry-run | grep a530_zap |
		sed "s#^#$flavour: #" | tee "$work/links-$flavour"
done
grep -q '/vendor/firmware/qcom/msm8996/zte/axon7/a530_zap.mbn -> /metadata/axon7-fw/a530_zap.mdt' "$work/links-standalone" ||
	fail "standalone a530_zap link does not resolve to the staged file"
grep -q '/vendor/firmware/qcom/msm8996/zte/axon7/a530_zap.mbn -> /mnt/vendor/fw_vendor/firmware/a530_zap.mdt' "$work/links-multiboot" ||
	fail "multiboot a530_zap link no longer uses the vendor partition"
python3 "$gen" --flavour standalone -o "$work/Android.bp" >/dev/null
cmp -s "$work/Android.bp" "$bp" || fail "committed Android.bp is not the standalone generator output"
ok "firmware links: standalone -> /metadata/axon7-fw, multiboot -> /mnt/vendor/fw_vendor"

echo "ALL INSTALLER HARNESS CASES PASSED"
