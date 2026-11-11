#!/bin/bash
# Copy the Axon 7's firmware from a running Nura (postmarketOS) to the build
# server, for /vendor/firmware in LineageOS 24 (device.mk picks up every file
# under vendor/zte/axon7m-firmware; without that directory the build has no
# firmware, as before). The files are proprietary (ZTE/Qualcomm images from
# the phone) or linux-firmware; they never go into git.
#   NURA=user@172.16.42.1 SERVER=root@compiler scripts/firmware-from-nura.sh
# Needs ssh to Nura (askpass for the login), PMOS_SUDO_PASS for sudo, and
# zstd on the PC (Nura's linux-firmware files are .zst, Nura has no zstd). Files (paths relative to /lib/firmware, the same names the
# kernel asks for, see the Nura dmesg):
#   qcom/msm8996/zte/axon7/{a530_zap,adsp,mba,modem,slpi,venus}.mbn  (firmware-zte-axon7)
#   qcom/a530_pfp.fw qcom/a530_pm4.fw qcom/a530v3_gpmu.fw2           (Adreno 530)
#   ath10k/QCA6174/hw3.0/firmware-6.bin + board.bin (the phone's bdwlan30.bin)
#   qca/rampatch_00440302.bin qca/nvm_00440302.bin                   (Bluetooth)
#   regulatory.db regulatory.db.p7s
set -eu
NURA=${NURA:-user@172.16.42.1}
SERVER=${SERVER:-root@compiler}
DEST=/srv/los24/lineage-24.0/vendor/zte/axon7m-firmware
O=(-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o LogLevel=ERROR -o PubkeyAuthentication=no)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
files="qcom/msm8996/zte/axon7/a530_zap.mbn qcom/msm8996/zte/axon7/adsp.mbn qcom/msm8996/zte/axon7/mba.mbn
qcom/msm8996/zte/axon7/modem.mbn qcom/msm8996/zte/axon7/slpi.mbn qcom/msm8996/zte/axon7/venus.mbn
qcom/a530_pfp.fw qcom/a530_pm4.fw qcom/a530v3_gpmu.fw2 ath10k/QCA6174/hw3.0/firmware-6.bin
qca/rampatch_00440302.bin qca/nvm_00440302.bin regulatory.db regulatory.db.p7s"
# shellcheck disable=SC2016
remote='set -e; t=$(mktemp -d); cd /lib/firmware
for f in '"$(echo $files)"'; do mkdir -p "$t/$(dirname "$f")"; if [ -f "$f" ]; then cp "$f" "$t/$f"; else cp "$f.zst" "$t/$f.zst"; fi; done
mkdir -p $t/ath10k/QCA6174/hw3.0; cp postmarketos/ath10k/QCA6174/hw3.0/board.bin $t/ath10k/QCA6174/hw3.0/board.bin
tar -C $t -cf - . ; rm -rf $t'
printf '%s\n' "${PMOS_SUDO_PASS:?set PMOS_SUDO_PASS (Nura sudo password)}" | ssh "${O[@]}" "$NURA" "sudo -S -p '' sh -c '$remote'" > "$tmp/fw.tar"
mkdir "$tmp/fw" && tar -C "$tmp/fw" -xf "$tmp/fw.tar"
find "$tmp/fw" -name '*.zst' -exec zstd -q --rm -d {} \;
(cd "$tmp/fw" && find . -type f | sort | xargs sha256sum) | tee "$tmp/SHA256SUMS"
n=$(find "$tmp/fw" -type f | wc -l); [ "$n" = 15 ] || { echo "expected 15 files, got $n" >&2; exit 1; }
ssh "$SERVER" "rm -rf $DEST.new && mkdir -p $DEST.new"
tar -C "$tmp/fw" -cf - . | ssh "$SERVER" "tar -C $DEST.new -xf - && chown -R build:build $DEST.new && rm -rf $DEST && mv $DEST.new $DEST && cd $DEST && find . -type f | sort | xargs sha256sum" > "$tmp/remote"
diff "$tmp/SHA256SUMS" "$tmp/remote" && echo "firmware on $SERVER:$DEST ($n files)"
