#!/bin/bash
# Build the two temporary test modules against the prepared LOS 24 kernel
# build tree for the running #31 kernel (phone config, no MODVERSIONS).
# Requires a kernel worktree based on gpl-los24 with patches 0059-0061
# applied, and a copy of the prepared out-r536225 build directory.
set -euo pipefail
K=/home/devilapi/axon7-kbuild/ipa-los
O=/home/devilapi/axon7-kbuild/ipa-loskout
M=/home/devilapi/axon7-kbuild/ipa-modtest
DTC="$O/scripts/dtc/dtc"
mkdir -p "$M"
cp "$(dirname "$0")"/{ipa-overlay.dtso,dt-helper.c,Makefile} "$M/"
cp "$K/drivers/net/ipa2-lite"/{ipa.c,ipa-qmi.c,ipa.h,ipa-hw.h} "$M/"
# 0x20 is the RPM clock-controller phandle in the phone's live FDT, 68 is
# RPM_SMD_IPA_CLK; dtc cannot generate a fixup for a phandle path in a
# property value, so the overlay carries the numeric phandle.
"$DTC" -@ -I dts -O dtb -o "$M/ipa-overlay.dtbo" -p 0x1000 "$M/ipa-overlay.dtso"
python3 - "$M/ipa-overlay.dtbo" "$M/ipa-overlay.h" <<'PY'
import sys
data = open(sys.argv[1], 'rb').read()
with open(sys.argv[2], 'w') as f:
    f.write('static const unsigned char ipa_ovl[] __attribute__((aligned(8))) = {\n')
    for i in range(0, len(data), 12):
        f.write('\t' + ', '.join('0x%02x' % b for b in data[i:i+12]) + ',\n')
    f.write('};\nstatic const unsigned int ipa_ovl_len = %d;\n' % len(data))
PY
export PATH="$HOME/axon7-kbuild/clang-r536225/bin:$PATH"
make -C "$K" O="$O" ARCH=arm64 LLVM=1 LLVM_IAS=1 \
  CC="$HOME/axon7-kbuild/clang-r536225/bin/clang" \
  LD="$HOME/axon7-kbuild/clang-r536225/bin/ld.lld" M="$M" modules
modinfo -F vermagic "$M/ipa2-lite.ko"
