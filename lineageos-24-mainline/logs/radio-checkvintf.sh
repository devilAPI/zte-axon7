#!/bin/bash
# Host-side VINTF check of the proposed FCM 202504 manifest and radio V4
# fragment, using the build server's checkvintf and the AOSP tree's out/ roots.
# Run on root@compiler. Only reads files; writes the staged copy under
# /srv/los24/tmp/radio-agent-stage/root/.
set -euo pipefail
S=/srv/los24/tmp/radio-agent-stage
O=/srv/los24/lineage-24.0/out/target/product/axon7m
C=/srv/los24/lineage-24.0/out/host/linux-x86/bin/checkvintf
mkdir -p "$S/root/vendor/etc/vintf/manifest" "$S/empty" "$S/apex"
cp "$S/manifest.xml" "$S/root/vendor/etc/vintf/manifest.xml"
cp "$S/radio/radio-axon7m.xml" "$S/root/vendor/etc/vintf/manifest/"
cp "$O/vendor/etc/vintf/compatibility_matrix.xml" "$S/root/vendor/etc/vintf/"
# The build adds the sepolicy version to the source manifest; do the same.
python3 - <<'PY'
p = "/srv/los24/tmp/radio-agent-stage/root/vendor/etc/vintf/manifest.xml"
s = open(p).read()
if "<sepolicy>" not in s:
    s = s.replace("</manifest>", "    <sepolicy>\n        <version>202604</version>\n    </sepolicy>\n</manifest>")
open(p, "w").write(s)
PY
# apex-info-list.xml was pulled from the running phone (no personal data).
"$C" --check-compat \
    --dirmap /system:"$O/system" --dirmap /vendor:"$S/root/vendor" \
    --dirmap /product:"$O/product" --dirmap /system_ext:"$O/system_ext" \
    --dirmap /odm:"$S/empty" --dirmap /apex:"$S/apex" \
    --property ro.product.first_api_level=34 --property ro.boot.product.hardware.sku=
