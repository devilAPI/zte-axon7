#!/bin/bash
# Fetch the queued LOS 24 build from root@compiler into ios/research (delta
# against build 51 if already present) and verify both image checksums.
set -euo pipefail
N=${1:?build number}
R=$(cd "$(dirname "$0")/../../.." && pwd)
IOS=$(realpath "$R/ios")
D=$IOS/research/los24-build-$N
S=/srv/los24/lineage-24.0/out/target/product/axon7m
mkdir -p "$D" "$R/lineageos-24-mainline/logs/modem-20261122"
L=$R/lineageos-24-mainline/logs/modem-20261122/fetch-build-$N.log
exec >"$L" 2>&1
echo "== $(date '+%FT%T') build $N"
timeout 60 ssh -o ConnectTimeout=10 root@compiler "grep -q '^build-exit 0' /srv/los24/logs/build-latest.log || { echo BUILD_NOT_OK; tail -20 /srv/los24/logs/build-latest.log; exit 1; }; cd $S && sha256sum boot.img super.img" > "$D/check.txt"
cat "$D/check.txt"
grep -q '^[0-9a-f]\{64\}  ' "$D/check.txt" || { echo "checksum output missing"; exit 1; }
[ "$(grep ' super.img$' "$D/check.txt" | cut -d' ' -f1)" != "$(sha256sum < "$IOS/research/los24-build-51/super.img" | cut -d' ' -f1)" ] || { echo "BUILD NOT NEW (super.img unchanged)"; exit 1; }
if [ -f "$IOS/research/los24-build-51/super.img" ]; then cp "$IOS/research/los24-build-51/super.img" "$D/super.img"; fi
for i in 1 2 3; do
  rsync -e 'ssh -o ConnectTimeout=10' --inplace --no-whole-file \
    root@compiler:$S/boot.img root@compiler:$S/super.img "$D/" && break
  echo "rsync retry $i"; sleep 10
done
(cd "$D" && grep -E '^[0-9a-f]{64}  ' check.txt | sha256sum -c)
echo "fetched: $(ls -lh "$D"/*.img | tr '\n' ' ')"
