# Installing on the ZTE Axon 7 (A2017G / A2017U)

| System | Phase | How to install |
|---|---|---|
| **Nura** (Linux, based on postmarketOS) | beta | on its own, from the microSD card: [INSTALL-NURA.md](INSTALL-NURA.md) |
| **LineageOS 22.2** (Android 15) | unofficial release | TWRP zip: [newest release](https://github.com/devilAPI/zte-axon7/releases/tag/lineageos-latest) (requirements in its notes: Oreo universal bootloader; works with or without the community vendor partition); developers: [DEV-MULTIBOOT.md](DEV-MULTIBOOT.md) |
| **iOS 16.7.16** | alpha | no downloads during the alpha (built on your PC from Apple's IPSW); developers: [DEV-MULTIBOOT.md](DEV-MULTIBOOT.md) |

The multi-boot setup (boot menu with all three systems) is the development
setup; it is described in [DEV-MULTIBOOT.md](DEV-MULTIBOOT.md).

## A2017U (US) owners

All three models share the codename `ailsa_ii`/`axon7` and the same hardware;
the differences are the modem/band firmware and the stock software. A2017U
units on stock B35 **have no fastboot endpoint**, so the A2017G unlock
instructions do not apply as written. A user reports that an EDL flash of the
B15-NEW `aboot`+`fbop` restored `fastboot oem unlock` (B29 alone was not
enough), that TWRP 3.7 can format `/data` as f2fs while LineageOS 22.2 needs
ext4, and that the PARTY download is dead (a `sgdisk` replacement works).
LineageOS 22.2 boots on that phone; calls/SMS/data are **untested** on
A2017U. Read [docs/variant-a2017u.md](docs/variant-a2017u.md) first and run
`tools/axon7-preflight.sh` before flashing.
