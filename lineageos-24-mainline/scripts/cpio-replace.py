#!/usr/bin/env python3
"""Replace or add one regular file in a newc ("070701") cpio archive, keeping
every other entry byte for byte (owner, mode, SELinux-relevant paths), so a
ramdisk can be changed without extracting it as a normal user.

  cpio-replace.py IN.cpio OUT.cpio PATH SRCFILE [MODE_OCTAL]

PATH is the archive name (e.g. "adb_keys"); an existing entry of that name
(file or symlink) is replaced by a regular file, owner 0:0, mode MODE
(default 0644). Used by make-m0b-recovery.sh.
"""
import sys


def entries(b):
    o = 0
    while o < len(b):
        if b[o:o + 6] != b"070701":
            raise SystemExit(f"bad cpio magic at {o}")
        h = b[o:o + 110]
        f = [int(h[6 + 8 * i:14 + 8 * i], 16) for i in range(13)]
        namesize, filesize = f[11], f[6]
        name_end = o + 110 + namesize
        name = b[o + 110:name_end - 1].decode()
        data_start = (name_end + 3) & ~3
        end = (data_start + filesize + 3) & ~3
        yield name, f, b[o:end]
        o = end
        if name == "TRAILER!!!":
            return


def entry(name, mode, data, ino):
    nb = name.encode() + b"\0"
    fields = [ino, mode, 0, 0, 1, 0, len(data), 0, 0, 0, 0, len(nb), 0]
    h = b"070701" + b"".join(b"%08X" % v for v in fields)
    out = h + nb
    out += b"\0" * (-len(out) % 4)
    out += data
    out += b"\0" * (-len(out) % 4)
    return out


def main():
    src, dst, path, file = sys.argv[1:5]
    mode = int(sys.argv[5], 8) if len(sys.argv) > 5 else 0o644
    b = open(src, "rb").read()
    data = open(file, "rb").read()
    out, done, maxino, trailer = [], False, 0, None
    for name, f, raw in entries(b):
        maxino = max(maxino, f[0])
        if name == "TRAILER!!!":
            trailer = raw
            continue
        if name == path:
            out.append(entry(path, 0o100000 | mode, data, f[0]))
            done = True
        else:
            out.append(raw)
    if not done:
        out.append(entry(path, 0o100000 | mode, data, maxino + 1))
    out.append(trailer)
    blob = b"".join(out)
    blob += b"\0" * (-len(blob) % 512)
    open(dst, "wb").write(blob)
    print(f"{'replaced' if done else 'added'} {path} ({len(data)} bytes)")


if __name__ == "__main__":
    main()
