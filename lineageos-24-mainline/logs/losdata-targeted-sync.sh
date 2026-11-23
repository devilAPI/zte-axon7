#!/bin/bash
# Copy ONLY losdata's files to the shared build server, without --delete.
# oc-axon7-serversync uses rsync --delete for the whole LOS tree; another
# worker's sync removed these files while the module build was queued.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
H=${AXON7_BUILD_HOST:-root@compiler}
R=/srv/los24/axon7/repo
rsync -aR \
  postmarketos/pmaports-local/device/testing/linux-zte-axon7/config-zte-axon7.aarch64 \
  postmarketos/pmaports-local/device/testing/linux-zte-axon7/0059-net-add-the-ipa2-lite-driver-for-IPA-v2.x.patch \
  postmarketos/pmaports-local/device/testing/linux-zte-axon7/0060-net-ipa2-lite-support-IPA-v2.5-on-MSM8996.patch \
  postmarketos/pmaports-local/device/testing/linux-zte-axon7/0061-net-ipa2-lite-QMAPv4-checksums-and-TX-lifetime-fixes.patch \
  postmarketos/pmaports-local/device/testing/linux-zte-axon7/0062-arm64-dts-qcom-msm8996-zte-axon7-add-IPA-v2.5.patch \
  lineageos-24-mainline/kernel/android-axon7m.config \
  lineageos-24-mainline/device/zte/axon7m/ \
  lineageos-24-mainline/logs/losdata-module-build.sh \
  "$H:$R/"
ssh "$H" "chown -R build:build $R
su -s /bin/sh build -c 'rsync -a $R/lineageos-24-mainline/device/zte/axon7m/ /srv/los24/lineage-24.0/device/zte/axon7m/'"
echo targeted-sync-ok
