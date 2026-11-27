#!/usr/bin/env python3
"""Compare the vendor files of the stock-layout system image (its /vendor directory)
with the separate vendor image of the vendor-layout build: same paths, type/mode,
owner, size, SELinux label and file capabilities (labels/capabilities/missing files are fatal). Uses e2fsprogs debugfs on the raw
images, read-only, no root and no loop devices needed.

  verify-stock-image.py STOCK_system.img VENDOR_vendor.img [--simg2img PATH]

Both images come from the same source tree (copy them out of out/ between builds).
Exit 0 and "IDENTICAL" if equal, else 1 with the first differences."""
import re, subprocess, sys, tempfile, os

def raw(path, simg2img, tmp, name):
    with open(path, "rb") as f:
        sparse = f.read(4) == b"\x3a\xff\x26\xed"
    if not sparse:
        return path
    out = os.path.join(tmp, name)
    subprocess.run([simg2img, path, out], check=True)
    return out

def dbg(img, *cmds):
    r = subprocess.run(["debugfs", "-R", "; ".join(cmds), img], capture_output=True, text=True)
    return r.stdout

def dbg_batch(img, cmds, tmp):
    cf = os.path.join(tmp, "cmds"); open(cf, "w").write("\n".join(cmds) + "\n")
    r = subprocess.run(["debugfs", "-f", cf, img], capture_output=True, text=True)
    return r.stdout

def walk(img, root, tmp):
    """-> {relpath: (mode, uid, gid, size, ino)}"""
    ents = {}
    stack = [(root, "")]
    while stack:
        d, rel = stack.pop()
        for line in dbg(img, "ls -p %s" % d).splitlines():
            p = line.split("/")
            if len(p) < 8 or p[0] != "":
                continue
            ino, mode, uid, gid, name, size = p[1], p[2], p[3], p[4], p[5], p[6]
            if name.strip("./") == "" or name in (".", "..") or (rel == "" and name == "lost+found" and root == "/"):
                continue
            r = rel + "/" + name
            ents[r] = (mode, uid, gid, size, ino)
            if mode.startswith("04"):   # directory (debugfs prints 040755)
                stack.append((d.rstrip("/") + "/" + name, r))
    return ents

def xattrs(img, ents, tmp):
    inos = sorted({v[4] for v in ents.values()})
    cmds = []
    for i in inos:
        cmds += ["ea_get -x <%s> security.selinux" % i, "ea_get -x <%s> security.capability" % i]
    out = dbg_batch(img, cmds, tmp)
    res, cur = {}, None
    for line in out.splitlines():
        m = re.match(r"debugfs:\s+ea_get -x <(\d+)> (\S+)", line)
        if m:
            cur = (m.group(1), m.group(2)); res.setdefault(cur[0], [])
        elif cur and line.startswith(cur[1] + " ("):
            res[cur[0]].append(line.strip())
    return res

def table(img, root, tmp):
    e = walk(img, root, tmp)
    x = xattrs(img, e, tmp)
    return {p: (v[0], v[1], v[2], v[3], tuple(x.get(v[4], []))) for p, v in e.items()}

def main():
    a = sys.argv[1:]
    simg = "simg2img"
    if "--simg2img" in a:
        i = a.index("--simg2img"); simg = a[i + 1]; del a[i:i + 2]
    if len(a) != 2:
        sys.exit(__doc__)
    with tempfile.TemporaryDirectory() as tmp:
        s = raw(a[0], simg, tmp, "sys.raw"); v = raw(a[1], simg, tmp, "ven.raw")
        st = table(s, "/system/vendor", tmp)  # the system image is the root: /system/vendor
        vt = table(v, "/", tmp)
    print("stock system /system/vendor: %d entries, vendor image: %d entries" % (len(st), len(vt)))
    # fatal: a path of the vendor image missing from system/vendor (except the files
    # the vendor image build generates itself), a different SELinux label or capability.
    # reported only: mode/owner (fs_config_files entries of the vendor image are not
    # applied to /system/vendor; the system build gives root:shell 0755) and sizes
    # (the two builds are separate: module outputs and generated contexts differ).
    GENERATED = ("/etc/NOTICE.xml.gz", "/etc/aconfig_flags.pb", "/etc/excluded-input-devices.xml",
                 "/etc/fs_config_dirs", "/etc/fs_config_files", "/etc/linker.config.pb")
    fatal, owner, size = [], [], []
    for p in sorted(vt):
        if p not in st:
            if p not in GENERATED:
                fatal.append("missing in system/vendor: %s" % p)
            continue
        m, u, g, sz, xa = vt[p]; m2, u2, g2, sz2, xa2 = st[p]
        if xa != xa2:
            fatal.append("%s\n   vendor.img:    %s\n   system/vendor: %s" % (p, xa, xa2))
        if (m, u, g) != (m2, u2, g2):
            owner.append("%s %s:%s %s -> %s:%s %s" % (p, u, g, m, u2, g2, m2))
        elif sz != sz2:
            size.append(p)
    for p in sorted(set(st) - set(vt)):
        fatal.append("extra in system/vendor: %s" % p)
    print("mode/owner differences (info): %d" % len(owner))
    for o in owner[:15]: print("   " + o)
    print("size-only differences (info): %d" % len(size))
    if fatal:
        print("DIFFERENCES (labels/capabilities/missing): %d" % len(fatal)); print("\n".join(fatal[:30])); sys.exit(1)
    labelled = sum(1 for x in vt.values() if any(t.startswith("security.selinux") for t in x[4]))
    print("LABELS IDENTICAL (%d entries labelled, capabilities equal, no missing files)" % labelled)

main()
