#!/bin/bash
# Run on root@compiler as user build, under /srv/aosp/build.lock:
#   flock -w 7200 /srv/aosp/build.lock bash losdata-module-build.sh
set -u
cd /srv/los24/lineage-24.0 || exit 1
source build/envsetup.sh
lunch lineage_axon7m-userdebug
m android.hardware.radio-service.axon7m
rc=$?
echo "module-build-exit $rc $(date -u +%FT%TZ)"
exit "$rc"
