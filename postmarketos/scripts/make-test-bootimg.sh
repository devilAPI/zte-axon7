#!/bin/sh
# Build out/boot-test.img: mainline Image.gz + appended Axon 7 dtb + test initramfs.
# Header values match the stock boot.img (v0, page 4096, base 0x80000000).
set -eu
W=$(cd "$(dirname "$0")/.." && pwd)
B=$W/build
O=$W/out
mkdir -p "$O"

cat "$B/arch/arm64/boot/Image.gz" "$B/arch/arm64/boot/dts/qcom/msm8996-zte-axon7.dtb" > "$O/Image.gz-dtb"
cp "$B/arch/arm64/boot/dts/qcom/msm8996-zte-axon7.dtb" "$O/"
cp "$B/arch/arm64/boot/Image.gz" "$O/"

CMDLINE="console=ttyMSM0,115200 console=tty0 clk_ignore_unused pd_ignore_unused panic=10 loglevel=7"

mkbootimg \
	--header_version 0 \
	--kernel "$O/Image.gz-dtb" \
	--ramdisk "$W/test-initramfs/initramfs-test.cpio.gz" \
	--base 0x80000000 \
	--kernel_offset 0x00008000 \
	--ramdisk_offset 0x01000000 \
	--second_offset 0x00f00000 \
	--tags_offset 0x00000100 \
	--pagesize 4096 \
	--os_version 10.0.0 \
	--os_patch_level 2020-05 \
	--cmdline "$CMDLINE" \
	-o "$O/boot-test.img"

ls -l "$O"
sha256sum "$O/boot-test.img"
