# PN5xx raw NCI character device (not in the release series)

`pn5xx-raw-char-device.patch` adds `/dev/nq-nci`, `/dev/pn5xx`, `/dev/pn54x`
for the PN548 (exact NCI frames, IRQ masked until read). Tested 2026-11-22 as
a module on the main phone under LineageOS 24 (kernel #31): NCI 1.1 reset and
init frames answered (`40 00 03 00 11 00`). Not added to the Nura series
because it is built-in (`CONFIG_NFC_PN5XX_CHAR=y`) and would compete with the
working nxp-nci netlink stack; it is only needed once an Android PN548 HAL
exists (hardware/nxp/nfc at android-17 builds only the SNxxx AIDL HAL).
Branch: agent/nfchal (LineageOS 24 side merged, gated off with AXON7_NFC=1).
