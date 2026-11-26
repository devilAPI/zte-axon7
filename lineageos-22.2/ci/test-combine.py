#!/usr/bin/env python3
"""Offline test of combine-zip.py and of the combined zip's installer logic.

Builds fake vendor/stock OTA zips (same structure as the real ones, tiny
payloads), combines them and checks the result. If EDIFY_SIM points at the
built ci/edify-sim binary, the combined zip's real updater-script is run
through the AOSP edify interpreter against fake partition tables for every
layout and failure case, with the real axon7-layout.sh from the zip.

  EDIFY_SIM=/path/edify_sim ci/test-combine.py
"""
import os, subprocess, sys, tempfile, zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
COMBINE = os.path.join(HERE, "combine-zip.py")
HEADER = '''assert(getprop("ro.product.device") == "ailsa_ii" || getprop("ro.build.product") == "ailsa_ii" || 
       getprop("ro.product.device") == "axon7" || getprop("ro.build.product") == "axon7" || abort("E3004: This package is for device: ailsa_ii,axon7; this device is " + getprop("ro.product.device") + "."););
assert(axon7.verify_trustzone("TZ.BF.4.0.1-00353") == "1");
ui_print("Target: ZTE/P996A03_O/msm8996:8.0.0/OPR1.170623.032/520:user/release-keys");
'''
OLD_TAIL = 'package_extract_dir("install", "/tmp/install");\nblock_image_update("x");\n'
def tl(end):  # transfer list v4 writing blocks [0,end)
    return "4\n%d\n0\n0\nnew 2,0,%d\n" % (end, end)

def make(path, vendor, sys_end=400000, ven_end=90000, header=HEADER):
    with zipfile.ZipFile(path, "w") as z:
        z.writestr("META-INF/com/android/metadata", "ota-type=BLOCK\n")
        z.writestr("META-INF/com/android/metadata.pb", b"pb")
        z.writestr("META-INF/com/android/otacert", "cert")
        z.writestr("META-INF/com/google/android/update-binary", b"bin")
        z.writestr("META-INF/com/google/android/updater-script", header + OLD_TAIL)
        z.writestr("system.new.dat.br", b"SYS-" + (b"V" if vendor else b"N"))
        z.writestr("system.patch.dat", b"")
        z.writestr("system.transfer.list", tl(sys_end))
        z.writestr("boot.img", b"BOOT-" + (b"V" if vendor else b"N"))
        z.writestr("recovery.img", b"rec")
        z.writestr("install/bin/backuptool.sh", "#!/bin/sh\n")
        if vendor:
            z.writestr("vendor.new.dat.br", b"VEN")
            z.writestr("vendor.patch.dat", b"")
            z.writestr("vendor.transfer.list", tl(ven_end))

fails = 0
def check(cond, msg):
    global fails
    print(("ok   " if cond else "FAIL ") + msg)
    if not cond:
        fails += 1

def combine(work, **kw):
    v, s, o = (os.path.join(work, n) for n in ("v.zip", "s.zip", "o.zip"))
    make(v, True, **{k: x for k, x in kw.items() if k in ("sys_end", "ven_end")})
    make(s, False, **{k: x for k, x in kw.items() if k == "sys_end"})
    if "stock_header" in kw:
        make(s, False, header=kw["stock_header"])
    if os.path.exists(o):
        os.unlink(o)
    r = subprocess.run([sys.executable, COMBINE, "--vendor-zip", v, "--stock-zip", s, "--out", o, "--no-sign"],
                       capture_output=True, text=True)
    return r, o

with tempfile.TemporaryDirectory() as work:
    r, o = combine(work)
    check(r.returncode == 0, "combine ok: " + r.stdout.strip().splitlines()[-1] if r.returncode == 0 else r.stderr)
    z = zipfile.ZipFile(o)
    names = z.namelist()
    for n in ("system.new.dat.br", "vendor.new.dat.br", "boot.img", "system-nv.new.dat.br",
              "system-nv.transfer.list", "system-nv.patch.dat", "boot-nv.img",
              "install/bin/axon7-layout.sh", "install/bin/backuptool.sh"):
        check(n in names, "has " + n)
    check(names[0].startswith("META-INF/com/android/metadata"), "metadata first")
    check(not any(n.startswith("vendor-nv") for n in names), "no vendor image for the stock layout")
    check(z.read("system.new.dat.br") == b"SYS-V" and z.read("system-nv.new.dat.br") == b"SYS-N", "system images not mixed up")
    check(z.read("boot.img") == b"BOOT-V" and z.read("boot-nv.img") == b"BOOT-N", "boot images not mixed up")
    sc = z.read("META-INF/com/google/android/updater-script").decode()
    check(sc.startswith(HEADER) and "axon7-layout.sh" in sc and "E3010" in sc, "updater-script: header kept, layout check, refusal")
    check("system-nv.new.dat.br" in sc and "boot-nv.img" in sc, "updater-script writes the stock set in the stock branch")
    check(sc.count("by-name/vendor") == 1, "vendor partition only written in the vendor branch")
    check("modem" not in sc and "persist" not in sc and "modemst" not in sc, "script never names modem/persist/EFS")
    ls = z.read("install/bin/axon7-layout.sh").decode()
    check("SYSTEM_BYTES=5905580032" in ls and "VENDOR_BYTES=536870912" in ls, "layout constants")

    r, _ = combine(work, sys_end=1500000)   # 6.1 GB of blocks > system_bytes
    check(r.returncode != 0 and "more than" in r.stderr, "refuses an image bigger than the file system size")
    r, _ = combine(work, stock_header=HEADER.replace("00353", "00999"))
    check(r.returncode != 0 and "differ" in r.stderr, "refuses mismatching TrustZone assert")

    # run through the real edify interpreter
    sim = os.environ.get("EDIFY_SIM")
    if sim:
        r, o = combine(work)
        ex = os.path.join(work, "x"); os.makedirs(ex)
        zipfile.ZipFile(o).extractall(ex)
        bin_ = os.path.join(ex, "install/bin")
        MiB = 1 << 20
        def run(name, parts, extra=None):
            t = os.path.join(work, "t_" + name)
            for d in ("by-name", "dev", "sys"):
                os.makedirs(os.path.join(t, d))
            for p, size in parts.items():
                open(os.path.join(t, "dev", p), "w").close()
                os.makedirs(os.path.join(t, "sys", p))
                open(os.path.join(t, "sys", p, "size"), "w").write(str(size // 512))
                os.symlink("../dev/" + p, os.path.join(t, "by-name", p))
            env = dict(os.environ, AXON7_BYNAME=t + "/by-name", AXON7_SYSFS=t + "/sys", AXON7_OUT=t,
                       AXON7_NOBLK="1", SIM_BIN=bin_, **(extra or {}))
            log = os.path.join(t, "log")
            rc = subprocess.run([sim, os.path.join(ex, "META-INF/com/google/android/updater-script"), log], env=env).returncode
            return rc, open(log).read()
        base = {"modem": 100 * MiB, "persist": 32 * MiB, "boot": 64 * MiB}
        rc, lg = run("vendor", dict(base, system=5905580032, vendor=512 * MiB))
        check(rc == 0 and "block_image_update" in lg and "vendor.new.dat.br" in lg and "boot.img -> /dev/block/bootdevice/by-name/boot" in lg
              and "system-nv" not in lg and "boot-nv" not in lg, "edify: vendor layout writes system+vendor+boot")
        rc, lg = run("stock", dict(base, system=6 * 1024 * MiB))
        w = [l for l in lg.splitlines() if l.startswith("WRITE")]
        check(rc == 0 and len(w) == 2 and "system-nv.new.dat.br" in w[0] and "boot-nv.img" in w[1] and "vendor" not in " ".join(w),
              "edify: stock layout writes only system(-nv)+boot-nv: %s" % w)
        rc, lg = run("smallvendor", dict(base, system=6 * 1024 * MiB, vendor=128 * MiB))
        check(rc == 0 and "vendor.new.dat.br" not in lg and "system-nv" in lg, "edify: too small vendor partition is ignored, not written")
        for n, parts, ex_env in (("tiny-system", dict(base, system=3 * 1024 * MiB), {}),
                                 ("no-system", dict(base), {}),
                                 ("no-boot", {"system": 6 * 1024 * MiB}, {}),
                                 ("wrong-device", dict(base, system=6 * 1024 * MiB), {"SIM_DEVICE": "klte"}),
                                 ("old-tz", dict(base, system=6 * 1024 * MiB), {"SIM_TZ_OK": "0"})):
            rc, lg = run(n, parts, ex_env)
            check(rc == 3 and "WRITE" not in lg and "ABORT" in lg, "edify: %s aborts with nothing written (%s)" % (n, [l for l in lg.splitlines() if l.startswith("ABORT")][:1]))
    else:
        print("skip edify run (set EDIFY_SIM)")

print("FAILED %d" % fails if fails else "all passed")
sys.exit(1 if fails else 0)
