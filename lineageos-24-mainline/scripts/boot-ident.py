#!/usr/bin/env python3
"""What is in the Axon 7's `boot` partition (or a boot image file)?

  boot-ident.py [IMAGE]     (default /dev/disk/by-partlabel/boot; read-only)

Prints the header, what the kernel slot holds (the multi-boot shim: normal
menu or LOS_TEST build, with or without the LineageOS entry; or a plain
Linux kernel = Nura's own boot.img, which LK starts without any menu), the
ramdisk slot (postmarketOS bundle "AX7PMOS1" or an initramfs) and a sha256
of the kernel slot to compare with known shim builds. Python standard
library only, so it runs on Nura and on the PC.
"""
import gzip, hashlib, struct, sys, zlib

path = sys.argv[1] if len(sys.argv) > 1 else "/dev/disk/by-partlabel/boot"
with open(path, "rb") as f:
    b = f.read(96 << 20)
if b[:8] != b"ANDROID!":
    sys.exit(f"{path}: no Android boot image (first bytes {b[:8]!r})")
ks, ka, rs, ra, ss, sa, ta, page, hv = struct.unpack_from("<9I", b, 8)
up = lambda n: (n + page - 1) // page * page
kern = b[page:page + ks]
rd = b[page + up(ks):page + up(ks) + rs]
print(f"{path}: header v{hv}, page {page}, kernel {ks} bytes @ {ka:#x}, ramdisk {rs} bytes @ {ra:#x}, "
      f"cmdline {b[64:576].split(bytes(1))[0].decode(errors='replace')!r}")
print(f"kernel slot sha256 {hashlib.sha256(kern).hexdigest()}")

img = kern
if kern[:2] == b"\x1f\x8b":
    try:
        img = zlib.decompressobj(31).decompress(kern, 64 << 20)
        print(f"kernel slot: gzip, {len(img)} bytes unpacked")
    except zlib.error as e:
        print(f"kernel slot: gzip that does not unpack ({e})")
if img[56:60] == b"ARM\x64":
    print("  arm64 Image header present")


def has(s):
    return s.encode() in img


if has("AXON7 SHIM: loader"):
    test = has("LOS test: restart reason recovery")
    print("  => multi-boot SHIM (boot menu)")
    print(f"     LineageOS entry: {'yes' if has('LineageOS') else 'NO (older shim: iOS + postmarketOS only)'}")
    print(f"     stored default (misc AX7BOOT1): {'yes' if has('MENU default') else 'NO'}")
    print(f"     LOS_TEST build: {'YES (watchdog 30 s, one LineageOS boot then TWRP)' if test else 'no (normal menu)'}")
elif b"Linux version" in img:
    v = img[img.index(b"Linux version"):][:120].split(b"\n")[0].decode(errors="replace")
    print(f"  => plain LINUX kernel, no boot menu: {v}")
    print("     LK starts this kernel directly: the boot menu default is never read")
else:
    print("  => neither the shim nor a Linux kernel recognised")

if rd[:8] == b"AX7PMOS1":
    print("ramdisk slot: postmarketOS bundle (AX7PMOS1) for the shim's postmarketOS entry")
elif rd[:2] == b"\x1f\x8b":
    print("ramdisk slot: gzip (an initramfs)")
else:
    print(f"ramdisk slot: {rd[:8]!r}")
