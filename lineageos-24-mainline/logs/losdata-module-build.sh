#!/bin/bash
# Reproduce the successful radio HAL module build on root@compiler (user build).
# The shared /srv/aosp/build.lock was held for hours by other workers' full
# images; this builds ONLY the HAL with the already generated out/ graph, so
# no second full image is started. siso is not used: it wedges in futex_wait.
set -u
cd /srv/los24/lineage-24.0 || exit 1
export HOME=/home/build  # su without -l leaves HOME=/root; ccache then fails
source build/envsetup.sh
breakfast axon7m
prebuilts/build-tools/linux-x86/bin/ninja -f out/combined-lineage_axon7m.ninja -j4 \
    android.hardware.radio-service.axon7m
rc=$?
echo "module-build-exit $rc $(date -u +%FT%TZ)"
exit "$rc"
