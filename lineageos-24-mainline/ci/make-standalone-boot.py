#!/usr/bin/env python3
"""Boot image for the standalone LineageOS 24 zip (flashed to normal `boot`).

LineageOS' build produces a v2 boot image with a *raw* arm64 Image and the
DTBs in the v2 dtb section (needed by the multi-boot shim, which cannot
gunzip with the MMU off). ZTE's LK boots the normal `boot` partition the way
it boots Nura's boot.img: header v0, page 4096, gzip-compressed Image with
the board DTB appended to the kernel slot, ramdisk in its own slot.

This converts the build's v2 image to that format (no firmware, no keys:
only the kernel, ramdisk, DTB and cmdline from the build). The appended DTB
is the one built by scripts/kernel-build.sh, selected by qcom,msm-id and
qcom,board-id; like the shim, this script refuses an image with no DTB.

A build whose cmdline lost androidboot.super_partition=system,
androidboot.boot_devices or firmware_class.path would boot into a first-stage
init that cannot mount logical partitions or load firmware; instead of
copying it blindly, refuse and print the cmdline that was found.

    make-standalone-boot.py IN.img -o OUT.img

The result is checked by axon7-androidimg.py check-in-v0 mode? No: that tool
checks the shim format; use `make-standalone-boot.py --check OUT.img` here.
"""
import argparse
import gzip
import struct
import sys

MAGIC = b"ANDROID!"
FDT_MAGIC = b"\xd0\x0d\xfe\xed"
PAGE = 4096
KBASE = 0x80000000
KLIMIT = 0x83400000  # the splash reservation starts here
# Tokens the standalone zip's boot image must carry (BoardConfig.mk). The
# boot_devices value is the UFS controller of the A2017G; if it ever changes,
# check this list as well as the build.
REQUIRED_CMDLINE = (
    "androidboot.super_partition=system",
    "androidboot.boot_devices=soc@0/624000.ufshc",
    "firmware_class.path=/vendor/firmware",
)


def die(msg):
    print(f"make-standalone-boot: {msg}", file=sys.stderr)
    sys.exit(1)


def up(n, page):
    return (n + page - 1) // page * page


def check_cmdline(raw, where):
    cmdline = raw.split(b"\0", 1)[0].decode("utf-8", "replace")
    print(f"cmdline ({where}): {cmdline}")
    tokens = cmdline.split()
    missing = [t for t in REQUIRED_CMDLINE if t not in tokens]
    if missing:
        die(f"{where} cmdline is missing required token(s): {' '.join(missing)}")


def parse_v2(b):
    if b[:8] != MAGIC:
        die("not an Android boot image")
    (ks, ka, rs, ra, ss, sa, ta, page, hv) = struct.unpack_from("<9I", b, 8)
    if hv != 2:
        die(f"expected a v2 boot image from the LineageOS build, got v{hv}")
    if page != PAGE:
        die(f"expected a {PAGE} byte page, got {page}")
    if not ks or not rs or ss:
        die("empty kernel/ramdisk or a second-stage bootloader in the image")
    off = page
    kernel = b[off:off + ks]
    off += up(ks, page)
    ramdisk = b[off:off + rs]
    off += up(rs, page)
    off += up(ss, page)
    dtbo_size = struct.unpack_from("<I", b, 1632)[0]
    off += up(dtbo_size, page)
    dtb_size, dtb_addr = struct.unpack_from("<IQ", b, 1648)
    if not dtb_size:
        die("the v2 image has no dtb section")
    dtb_blob = b[off:off + dtb_size]
    if len(dtb_blob) != dtb_size:
        die("truncated dtb section")
    if kernel[56:60] != b"ARM\x64":
        die("kernel is not a raw arm64 Image")
    text_off, image_size = struct.unpack_from("<QQ", kernel, 8)
    if not image_size:
        die("bad image_size in the kernel header")
    if KBASE + text_off + image_size + 2 * SZ_2M > KLIMIT:
        die(f"image_size {image_size} does not fit below the splash reservation")
    return dict(kernel=kernel, ramdisk=ramdisk, dtbs=dtb_blob,
                cmdline=b[64:576], ka=ka, ra=ra, sa=sa, ta=ta)


SZ_2M = 2 << 20


def split_dtbs(blob):
    out, o = [], 0
    while o < len(blob):
        if blob[o:o + 4] != FDT_MAGIC:
            die(f"no FDT magic at dtb offset {o:#x}")
        n = struct.unpack_from(">I", blob, o + 4)[0]
        if n < 40 or o + n > len(blob):
            die(f"bad DTB size {n} at {o:#x}")
        out.append(blob[o:o + n])
        o += n
    return out


def make_v0(src):
    h = parse_v2(src)
    dtbs = split_dtbs(h["dtbs"])
    if len(dtbs) != 1:
        die(f"expected the single board DTB from kernel-build.sh, got {len(dtbs)}")
    # gzip -1 keeps the image small and is what LK can decompress (Nura's
    # boot.img uses the same format). mtime=0 keeps CI builds reproducible.
    kernel = gzip.compress(h["kernel"], compresslevel=1, mtime=0) + dtbs[0]
    header = bytearray(PAGE)
    header[:8] = MAGIC
    struct.pack_into("<9I", header, 8,
                     len(kernel), h["ka"], len(h["ramdisk"]), h["ra"],
                     0, 0x80f00000, h["ta"], PAGE, 0)
    header[64:64 + len(h["cmdline"])] = h["cmdline"]
    return (bytes(header) + kernel + b"\0" * (-len(kernel) % PAGE)
            + h["ramdisk"] + b"\0" * (-len(h["ramdisk"]) % PAGE))


def check_v0(img):
    if img[:8] != MAGIC:
        die("not an Android boot image")
    ks, ka, rs, ra, ss, sa, ta, page, hv = struct.unpack_from("<9I", img, 8)
    if hv != 0 or page != PAGE:
        die(f"LK needs header v0 with a {PAGE} byte page, got v{hv}/{page}")
    if ka != 0x80008000 or ra != 0x81000000:
        die(f"unexpected load addresses {ka:#x}/{ra:#x}")
    k = img[page:page + ks]
    if k[:2] != b"\x1f\x8b":
        die("kernel is not gzip-compressed")
    import zlib
    d = zlib.decompressobj(16 + zlib.MAX_WBITS)
    image = d.decompress(k) + d.flush()
    dtb = d.unused_data
    if image[56:60] != b"ARM\x64":
        die("decompressed kernel is not a raw arm64 Image")
    if not dtb or dtb[:4] != FDT_MAGIC:
        die("no DTB appended to the kernel")
    check_cmdline(img[64:576], "converted")
    return f"OK: v0 image, kernel {ks} B (Image {len(image)}, DTB {len(dtb)}), ramdisk {rs} B"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("image", help="v2 boot.img from the LineageOS build")
    ap.add_argument("-o", "--output", help="write the LK boot image here")
    ap.add_argument("--check", action="store_true", help="check an already converted image")
    a = ap.parse_args()
    data = open(a.image, "rb").read()
    if a.check:
        print(check_v0(data))
        return
    if not a.output:
        die("-o is required")
    check_cmdline(data[64:576], "build")
    out = make_v0(data)
    open(a.output, "wb").write(out)
    print(check_v0(out))


if __name__ == "__main__":
    main()
