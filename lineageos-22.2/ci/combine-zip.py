#!/usr/bin/env python3
"""Combine the two LineageOS 22.2 OTA zips of one source tree into the zip
that installs on both partition layouts of the ZTE Axon 7.

  --vendor-zip  OTA zip built with AXON7_STANDALONE=1 (system.* + vendor.* + boot.img;
                needs the community vendor partition)
  --stock-zip   OTA zip built with AXON7_STANDALONE=novendor (system.* with the vendor
                files inside, boot.img whose ramdisk has /vendor -> /system/vendor)

The result is the vendor zip plus system-nv.* and boot-nv.img (from the stock zip),
ci/axon7-layout.sh (read-only layout detection) and a new updater-script that runs
the detection first and aborts before writing anything if neither layout works.

Checks (any failure = exit 1, no output file):
  * both zips are for the same device asserts / TrustZone / build fingerprint
  * the vendor zip has vendor.*, the stock zip has none
  * no image writes beyond the file system size it was built for
  * the system size constants of axon7-layout.sh match the images

Signing: the result must be signed like the inputs. Pass --sign-cmd with {in}
and {out}, e.g. 'java -Djava.library.path=LIB -jar signapk.jar -w PEM PK8 {in} {out}'.
--no-sign leaves it unsigned (offline tests).
"""
import argparse
import os
import re
import shlex
import subprocess
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
BLOCK = 4096
STORED_SUFFIXES = (".br", ".img", ".dat")


def die(msg):
    print("combine-zip: " + msg, file=sys.stderr)
    sys.exit(1)


def transfer_list_max_end(data):
    """Highest block (exclusive) any `new` command writes (block_image_update v4)."""
    lines = data.decode().splitlines()
    if len(lines) < 4 or lines[0].strip() not in ("1", "2", "3", "4"):
        die("transfer list has an unknown version: %r" % lines[:1])
    end = 0
    for line in lines[4:]:
        parts = line.split()
        if len(parts) == 2 and parts[0] in ("new", "zero", "erase"):
            nums = [int(x) for x in parts[1].split(",")]
            if nums[0] != len(nums) - 1 or nums[0] % 2:
                die("bad range set in transfer list: %s" % line)
            end = max([end] + nums[2::2])
    return end


def header_of(script):
    """Lines of an OTA updater-script before the first package_extract_dir."""
    out = []
    for line in script.splitlines():
        if line.startswith("package_extract_dir"):
            break
        out.append(line)
    else:
        die("updater-script has no package_extract_dir line")
    return "\n".join(out).rstrip() + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--vendor-zip", required=True)
    ap.add_argument("--stock-zip", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--layout-sh", default=os.path.join(HERE, "axon7-layout.sh"))
    ap.add_argument("--template", default=os.path.join(HERE, "updater-script.in"))
    ap.add_argument("--system-bytes", type=int, default=5905580032)
    ap.add_argument("--vendor-bytes", type=int, default=536870912)
    ap.add_argument("--sign-cmd", help="signing command with {in} and {out}")
    ap.add_argument("--no-sign", action="store_true")
    a = ap.parse_args()

    if not a.sign_cmd and not a.no_sign:
        die("give --sign-cmd or --no-sign")

    zv = zipfile.ZipFile(a.vendor_zip)
    zs = zipfile.ZipFile(a.stock_zip)
    nv, ns = set(zv.namelist()), set(zs.namelist())

    for n in ("system.new.dat.br", "system.transfer.list", "system.patch.dat",
              "vendor.new.dat.br", "vendor.transfer.list", "vendor.patch.dat",
              "boot.img", "META-INF/com/google/android/updater-script",
              "META-INF/com/google/android/update-binary"):
        if n not in nv:
            die("vendor zip has no %s" % n)
    for n in ("system.new.dat.br", "system.transfer.list", "system.patch.dat", "boot.img",
              "META-INF/com/google/android/updater-script"):
        if n not in ns:
            die("stock zip has no %s" % n)
    if any(n.startswith("vendor.") for n in ns):
        die("stock zip contains a vendor image: it was not built with AXON7_STANDALONE=novendor")
    for n in ns:
        if n.startswith("system-nv") or n == "boot-nv.img" or n.startswith("install/bin/axon7"):
            die("stock zip already looks combined (%s)" % n)

    hv = header_of(zv.read("META-INF/com/google/android/updater-script").decode())
    hs = header_of(zs.read("META-INF/com/google/android/updater-script").decode())
    if hv != hs:
        die("the two zips differ in device asserts / TrustZone / fingerprint:\n--- vendor\n%s--- stock\n%s" % (hv, hs))
    if "axon7.verify_trustzone" not in hv or "ailsa_ii" not in hv:
        die("updater-script header lacks the device or TrustZone assert")

    # the images must fit the file system sizes the layout script checks
    for label, z, name, limit in (("vendor zip system", zv, "system.transfer.list", a.system_bytes),
                                  ("stock zip system", zs, "system.transfer.list", a.system_bytes),
                                  ("vendor zip vendor", zv, "vendor.transfer.list", a.vendor_bytes)):
        end = transfer_list_max_end(z.read(name))
        if end * BLOCK > limit:
            die("%s writes up to byte %d, more than %d" % (label, end * BLOCK, limit))
        print("%s: last written block %d (%d bytes), limit %d" % (label, end, end * BLOCK, limit))

    layout = open(a.layout_sh).read()
    layout, n1 = re.subn(r"(?m)^SYSTEM_BYTES=\d+$", "SYSTEM_BYTES=%d" % a.system_bytes, layout)
    layout, n2 = re.subn(r"(?m)^VENDOR_BYTES=\d+$", "VENDOR_BYTES=%d" % a.vendor_bytes, layout)
    if n1 != 1 or n2 != 1:
        die("axon7-layout.sh has no SYSTEM_BYTES/VENDOR_BYTES lines")
    script = open(a.template).read().replace("@HEADER@\n", hv)
    if "@HEADER@" in script:
        die("template placeholder not replaced")

    tmp = a.out + ".unsigned" if a.sign_cmd else a.out
    if os.path.exists(tmp):
        os.unlink(tmp)

    def add_stream(zout, src_zip, src_name, dst_name):
        info = zipfile.ZipInfo(dst_name, (2009, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_STORED if dst_name.endswith(STORED_SUFFIXES) else zipfile.ZIP_DEFLATED
        info.external_attr = 0o644 << 16
        with src_zip.open(src_name) as fi, zout.open(info, "w", force_zip64=True) as fo:
            while True:
                buf = fi.read(1 << 20)
                if not buf:
                    break
                fo.write(buf)

    def add_bytes(zout, dst_name, data, mode=0o644):
        info = zipfile.ZipInfo(dst_name, (2009, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = mode << 16
        zout.writestr(info, data)

    with zipfile.ZipFile(tmp, "w", allowZip64=True) as zo:
        order = [n for n in zv.namelist() if n.startswith("META-INF/com/android/metadata")]
        order += [n for n in zv.namelist() if n not in order]
        for n in order:
            if n.endswith("/"):
                continue
            if n == "META-INF/com/google/android/updater-script":
                add_bytes(zo, n, script.encode())
            elif n.startswith("META-INF/") and (n.endswith(".SF") or n.endswith(".RSA") or n.endswith("MANIFEST.MF")):
                continue  # signature files of the input: re-signed below
            else:
                add_stream(zo, zv, n, n)
        for src, dst in (("system.new.dat.br", "system-nv.new.dat.br"),
                         ("system.patch.dat", "system-nv.patch.dat"),
                         ("system.transfer.list", "system-nv.transfer.list"),
                         ("boot.img", "boot-nv.img")):
            add_stream(zo, zs, src, dst)
        add_bytes(zo, "install/bin/axon7-layout.sh", layout.encode(), 0o755)

    if a.sign_cmd:
        cmd = [x.replace("{in}", tmp).replace("{out}", a.out) for x in shlex.split(a.sign_cmd)]
        r = subprocess.run(cmd)
        if r.returncode != 0:
            die("signing failed: %r" % cmd)
        os.unlink(tmp)
    print("wrote %s (%d bytes)" % (a.out, os.path.getsize(a.out)))


if __name__ == "__main__":
    main()
