#!/usr/bin/env python3
"""Squash a split Qualcomm PIL firmware (foo.mdt + foo.bNN) into one foo.mbn.

Equivalent to Linaro's pil-squasher: every program segment with file data is
placed at its p_offset in the output; segments that live in the .mdt itself
(ELF + program headers + hash segment) are copied from the .mdt.
Usage: pil-squasher.py OUT.mbn IN.mdt
"""
import os
import struct
import sys


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    out_path, mdt_path = sys.argv[1], sys.argv[2]
    base = mdt_path[:-4] if mdt_path.endswith(".mdt") else mdt_path
    with open(mdt_path, "rb") as f:
        mdt = f.read()
    if mdt[:4] != b"\x7fELF":
        sys.exit("not an ELF: " + mdt_path)
    is64 = mdt[4] == 2
    if is64:
        e_phoff, = struct.unpack_from("<Q", mdt, 0x20)
        e_phentsize, e_phnum = struct.unpack_from("<HH", mdt, 0x36)
    else:
        e_phoff, = struct.unpack_from("<I", mdt, 0x1C)
        e_phentsize, e_phnum = struct.unpack_from("<HH", mdt, 0x2A)

    # The .mdt is a prefix of the squashed layout (ELF header, phdrs, hash)
    out = bytearray(mdt)

    def put(off, data):
        end = off + len(data)
        if len(out) < end:
            out.extend(b"\0" * (end - len(out)))
        out[off:end] = data

    for i in range(e_phnum):
        ph = e_phoff + i * e_phentsize
        if is64:
            p_type, p_flags, p_offset, _va, _pa, p_filesz = struct.unpack_from("<IIQQQQ", mdt, ph)
        else:
            p_type, p_offset, _va, _pa, p_filesz, _memsz, p_flags = struct.unpack_from("<IIIIIII", mdt, ph)
        if p_filesz == 0:
            continue
        seg = "%s.b%02d" % (base, i)
        if os.path.exists(seg):
            with open(seg, "rb") as f:
                data = f.read()
            if len(data) != p_filesz:
                sys.exit("%s: size %d != p_filesz %d" % (seg, len(data), p_filesz))
        elif p_offset + p_filesz <= len(mdt):
            data = mdt[p_offset:p_offset + p_filesz]
        else:
            # Segment missing on disk (some vendors omit empty/unused ones)
            print("warning: %s missing, zero-filling" % seg, file=sys.stderr)
            data = b"\0" * p_filesz
        put(p_offset, data)

    with open(out_path, "wb") as f:
        f.write(out)


if __name__ == "__main__":
    main()
