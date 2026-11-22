#!/usr/bin/env python3
"""Patch an axon7m LineageOS boot.img for one SELinux enforcing test.

Only the kernel command line is changed: androidboot.selinux=permissive becomes
androidboot.selinux=enforcing.  init takes the *first* androidboot.selinux it
finds, so appending another value does not work.  The image is otherwise
byte-for-byte the one from the build (same kernel, ramdisk, DTB).

Usage: make-enforcing-boot.py BUILD_BOOT_IMG OUT_IMG
"""
import struct
import sys

MAGIC = b"ANDROID!"


def main():
    src, dst = sys.argv[1:3]
    image = bytearray(open(src, "rb").read())
    if image[:8] != MAGIC:
        sys.exit(f"{src}: not an Android boot image")
    hv = struct.unpack_from("<I", image, 40)[0]
    if hv != 2:
        sys.exit(f"{src}: header v{hv}, expected v2")
    c1 = bytes(image[64:576]).split(b"\0", 1)[0]
    c2 = bytes(image[608:1632]).split(b"\0", 1)[0]
    cmd = c1 + c2
    old = b"androidboot.selinux=permissive"
    if cmd.count(old) != 1:
        sys.exit(f"{src}: expected exactly one {old.decode()} in the cmdline")
    cmd = cmd.replace(old, b"androidboot.selinux=enforcing")
    if len(cmd) > 511 + 1024 - 1:
        sys.exit("cmdline too long")
    image[64:576] = b"\0" * 512
    image[608:1632] = b"\0" * 1024
    image[64:64 + min(len(cmd), 511)] = cmd[:511]
    image[608:608 + len(cmd[511:])] = cmd[511:]
    open(dst, "wb").write(image)
    print(f"{dst}: cmdline: {cmd.decode()}")


if __name__ == "__main__":
    main()
