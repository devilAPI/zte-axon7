#!/vendor/bin/sh
# Load the IPA v2.5 driver (ipa2-lite) only after the modem is up.
#
# The Axon 7's IPA BAM is owned by the modem/TZ: probing the driver with the
# modem stopped resets the SoC (Mi MIX PHASE6_FINDINGS, Nura IPA.md). The
# kernel module is therefore deliberately absent from modules.load. Nura's
# patch 0062 puts the ipa@680000 node into the device tree at boot; this
# service waits for the mss remoteproc, then modprobe binds the driver to it
# and rmnet_ipa0 appears.
set -u
mss=/sys/class/remoteproc/remoteproc0/state
i=0
while [ "$i" -lt 60 ]; do
    state=$(cat "$mss" 2>/dev/null || echo unknown)
    [ "$state" = running ] && break
    sleep 1
    i=$((i + 1))
done
if [ "$state" != running ]; then
    echo "axon7m-ipa: modem not running ($state) after ${i}s, not loading" > /dev/kmsg
    exit 1
fi
timeout 30 /vendor/bin/modprobe -a -d /vendor/lib/modules ipa2_lite
rc=$?
echo "axon7m-ipa: modprobe ipa2_lite rc=$rc, modem=$state" > /dev/kmsg
exit "$rc"
