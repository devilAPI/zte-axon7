**Nura (beta)**: Linux (postmarketOS, mainline Linux 7.3) for the ZTE Axon 7 (A2017G). It runs from the **microSD card**; internal storage is not touched.

### Files

- `nura-axon7-DATE-sdcard.img.xz`: write it to the microSD card (balenaEtcher, or `xz -dc … | dd`). **The card is erased.**
- `nura-axon7-DATE-boot.img`: flash it in TWRP: Install → Install Image → **Boot**. Back up your Boot partition first (that is your way back to Android).
- `SHA256SUMS-DATE`: checksums (`sha256sum -c`).

### First start

Nura contains no Qualcomm/ZTE firmware: at the first start it copies the firmware from your phone's own partitions and restarts once. Then log in as **user**, password **@NURA_PASSWORD@**, and change the password right away with `passwd`.

Full guide: https://github.com/devilAPI/zte-axon7/blob/main/INSTALL-NURA.md. What works and what doesn't: see the XDA thread.

Kernel source (GPLv2): https://github.com/devilAPI/linux/tree/zte-axon7. Not affiliated with ZTE or postmarketOS. Flash at your own risk.
