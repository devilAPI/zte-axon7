#!/bin/bash
# Copy this repository's LineageOS 24 mainline parts to the build server and
# into the Android tree. Run on the PC from the repository root (or worktree):
#   lineageos-24-mainline/scripts/server-sync-device.sh
# Server layout (user build):
#   /srv/los24/axon7/repo/                 copy of the needed repo parts
#   /srv/los24/lineage-24.0/device/zte/axon7m          device tree (rsync --delete)
#   /srv/los24/lineage-24.0/device/zte/axon7m-kernel   copy of /srv/los24/kernel/prebuilt (no symlink out of the tree)
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
H=${AXON7_BUILD_HOST:-root@compiler}
rsync -a --delete -R postmarketos/pmaports-local/device/testing/linux-zte-axon7 \
	lineageos-24-mainline "$H:/srv/los24/axon7/repo/"
ssh "$H" 'chown -R build:build /srv/los24/axon7/repo
su - build -c "T=/srv/los24/lineage-24.0
[ -d \$T/device ] || { echo \"Android tree not synced yet\"; exit 0; }
mkdir -p \$T/device/zte \$T/.repo/local_manifests
rsync -a --delete /srv/los24/axon7/repo/lineageos-24-mainline/device/zte/axon7m/ \$T/device/zte/axon7m/
[ -d /srv/los24/kernel/prebuilt ] && rsync -a --delete /srv/los24/kernel/prebuilt/ \$T/device/zte/axon7m-kernel/
cp /srv/los24/axon7/repo/lineageos-24-mainline/manifest/axon7m.xml \$T/.repo/local_manifests/
echo synced device tree"'
