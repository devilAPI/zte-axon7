#!/bin/bash
# Build a Nura release for the ZTE Axon 7: a raw microSD image and boot.img,
# without any Qualcomm/ZTE firmware (the phone copies its own at the first
# boot, axon7-firmware). Login: user / $NURA_PASSWORD (the published default
# password; the GitHub workflow takes it from the repository variable
# NURA_DEFAULT_PASSWORD).
#
# Needs sudo (pmbootstrap), asks for the password once.
# Output: out/release/nura-axon7-DATE-sdcard.img.xz, nura-axon7-DATE-boot.img,
#         SHA256SUMS
#
# Usage: NURA_PASSWORD=... scripts/nura-release.sh
set -euo pipefail
: "${NURA_PASSWORD:?set NURA_PASSWORD to the published default login password}"
cd "$(dirname "$0")/.."
pmb() { python3 pmbootstrap/pmbootstrap.py "$@"; }
date=$(date +%Y%m%d)
rel=out/release
mkdir -p "$rel"

sudo -v		# once, pmbootstrap reuses it
# a public image must not contain the builder's SSH keys
if [ "$(pmb config ssh_keys)" != False ]; then
	echo "pmbootstrap ssh_keys is on: run 'pmbootstrap config ssh_keys False' first" >&2
	exit 1
fi
aports=$(pmb config aports)
cp -r pmaports-local/device/testing/device-zte-axon7 pmaports-local/device/testing/linux-zte-axon7 "$aports/device/testing/"
pmb -y checksum device-zte-axon7
pmb -y build device-zte-axon7 linux-zte-axon7
pmb -y zap		# fresh chroots: nothing left over from a developer install
pmb -y install --password "$NURA_PASSWORD"

# the image must not contain the firmware package
if pmb chroot -r -- apk info -e firmware-zte-axon7 >/dev/null 2>&1; then
	echo "firmware-zte-axon7 is installed in the rootfs: not a release image" >&2
	exit 1
fi
if pmb chroot -r -- sh -c 'ls /usr/lib/firmware/qcom/msm8996/zte/axon7/*.mbn' >/dev/null 2>&1; then
	echo "proprietary .mbn files in the rootfs: not a release image" >&2
	exit 1
fi

pmb export
exp=/tmp/postmarketOS-export
img=$(readlink -f "$exp/zte-axon7.img")
boot=$(readlink -f "$exp/boot.img")
# sparse -> raw, so balenaEtcher/dd can write it to the card
if [ "$(head -c 4 "$img" | od -An -tx1 | tr -d ' ')" = 3aff26ed ]; then
	simg2img "$img" "$rel/nura-axon7-$date-sdcard.img"
else
	cp "$img" "$rel/nura-axon7-$date-sdcard.img"
fi
xz -T0 -9 -f "$rel/nura-axon7-$date-sdcard.img"
cp "$boot" "$rel/nura-axon7-$date-boot.img"
(cd "$rel" && sha256sum "nura-axon7-$date-sdcard.img.xz" "nura-axon7-$date-boot.img" > SHA256SUMS-$date)
ls -la "$rel"
echo "done: $rel"
