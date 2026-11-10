#!/bin/bash
# Offline check of a boot image against the multi-boot shim's LineageOS path:
# ios/shim/android.c exactly as the phone runs it, built for the host with
# its own host_android_test.c (in a temporary copy; expected entry taken from
# the Image's text_offset instead of the 4.4 kernel's 0x80000), fed the image
# and a stand-in for the DTB ZTE LK passes (memory, msm-id/board-id, LK-style
# bootargs). Prints the shim's log (cmdline, entry, DTB address), the
# resulting /chosen and /memory, and "ok:" or "FAIL".
#
# Usage: shim-hostcheck.sh IMAGE [WORKDIR]   (AXON7_SRC = checkout with ios/)
set -euo pipefail
R=$(git rev-parse --show-toplevel)
S=${AXON7_SRC:-$R}
IMG=$1
W=${2:-$(mktemp -d /tmp/shim-hostcheck.XXXXXX)}
rm -rf "$W"; mkdir -p "$W"
cp "$S"/ios/shim/*.[ch] "$W/"
# 0x80000000 + the Image's own text_offset instead (mainline: 0)
python3 -I - "$W/host_android_test.c" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
old = '\tif (j_entry != 0x80080000u) fail("entry not 0x80000000 + text_offset 0x80000");\n'
new = ('\tuint64_t toff; memcpy(&toff, img + page + 8, 8);\n'
       '\tif (j_entry != 0x80000000u + toff) fail("entry not 0x80000000 + text_offset");\n')
assert old in s, "host test changed upstream"
open(p, "w").write(s.replace(old, new, 1))
PYEOF
cc -O1 -Wall -Wextra -Werror -DANDROID_HOST_TEST -I"$W" "$W/host_android_test.c" "$W/android.c" "$W/fdtw.c" -o "$W/ta"
cat > "$W/lk.dts" <<'EOF'
/dts-v1/;
/ {
	#address-cells = <2>;
	#size-cells = <2>;
	model = "stand-in for the DTB ZTE LK patched for the shim";
	qcom,msm-id = <246 0x30001>;
	qcom,board-id = <100 0>;
	memory { device_type = "memory"; reg = <0 0x80000000 0 0x80000000 0x1 0x0 0 0x7e4c0000>; };
	chosen { bootargs = "console=ttyHSL0", "androidboot.serialno=0123abcd androidboot.baseband=msm skip_initramfs rootwait ro init=/init kpti=1"; };
};
EOF
dtc -q -I dts -O dtb -o "$W/lk.dtb" "$W/lk.dts"
"$W/ta" "$IMG" "$W/lk.dtb" "$W/out.dtb" | grep -E "LOS (cmdline|entry|dtb)|ok:|FAIL"
dtc -q -I dtb -O dts "$W/out.dtb" 2>/dev/null | grep -E "bootargs|linux,initrd|reg = <0x00 0x80000000" | head -5
# the staging area and read limits the phone shim uses for this image
python3 -I - "$IMG" <<'PYEOF'
import struct, sys
h = open(sys.argv[1], "rb").read(1660)
ks, rs, ss, page = (struct.unpack_from("<I", h, o)[0] for o in (8, 16, 24, 36))
dtbo, ds = struct.unpack_from("<I", h, 1632)[0], struct.unpack_from("<I", h, 1648)[0]
up = lambda n: (n + page - 1) // page * page
ro = page + up(ks); so = ro + up(rs); dbo = so + up(ss) + up(dtbo); total = dbo + up(ds)
st = 0xa4000000
print(f"staging {st:#x}..{st + total:#x} ({total / 2**20:.1f} MiB of 128), "
      f"initrd {st + ro:#x}..{st + ro + rs:#x}, DTB work copy 0xac000000")
PYEOF
