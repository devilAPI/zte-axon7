# ZTE Axon 7 (A2017G) bring-up

Three ways of running something new on the ZTE Axon 7 (Snapdragon 820,
`ailsa_ii` / `axon7`), and everything learned about the phone along the way.

| Project | Status (2026-11-08) |
| --- | --- |
| [**iOS 16 on the Axon 7**](ios/) (**alpha**) (XNU port, submodule: [devilAPI/ios-sailfish](https://github.com/devilAPI/ios-sailfish/tree/axon7), branch `axon7`) | iOS 16.7.16 (iPhone 8 userland) boots to the lock and home screen, GPU-accelerated (Adreno 530 via Mesa freedreno), touch, Home on Volume Down, rootless jailbreak with Sileo. Wi-Fi works, rejoining included (WPA2-PSK, DHCP, Safari, Sileo). OpenSSH and apt/Sileo installs work. Dual boot with postmarketOS: boot menu after the ZTE logo (Vol+/Vol- choose, Power starts). Details: [ios/PORTING-AXON7.md](ios/PORTING-AXON7.md) |
| [**Nura**](postmarketos/) (**beta**; Linux based on postmarketOS, mainline 7.3.1) | runs from the microSD card, on its own or from the boot menu: display (S6E3HA3 dual DSI), touch, on-screen keyboard (buffyboard), Wi-Fi, Bluetooth, SSH, USB OTG (automatic) |
| [**LineageOS**](lineageos/) (**unofficial release**) | 22.2 (Android 15) on the 4.4 kernel, as a TWRP zip ([newest release](https://github.com/devilAPI/zte-axon7/releases/tag/lineageos-latest)): display, touch keys, Wi-Fi, Bluetooth (also audio), hotspot, NFC, sensors, GPS, fingerprint, both cameras with OIS, sound, encryption, SELinux enforcing; calls/data with a SIM untested |

**Want to try it?** [INSTALL.md](INSTALL.md): Nura installs on its own ([INSTALL-NURA.md](INSTALL-NURA.md)). LineageOS is a TWRP zip ([newest release](https://github.com/devilAPI/zte-axon7/releases/tag/lineageos-latest)). iOS is alpha: no downloads; the developers' multi-boot setup is in [DEV-MULTIBOOT.md](DEV-MULTIBOOT.md).
XDA threads, first posts (BBCode, status and changelog): [Nura](XDA-POST-NURA.md), [LineageOS](XDA-POST-LINEAGEOS.md), [iOS](XDA-POST-IOS.md)

## Hardware documentation

- [docs/hardware.md](docs/hardware.md): SoC, memory map, reserved memory, pstore, partitions, display, touch, keys, Wi-Fi/BT/NFC, power, audio, firmware locations, reboot/recovery modes
- [docs/bootloader.md](docs/bootloader.md): ZTE LK behaviour, load addresses, **no `fastboot boot`** and how to test kernels anyway, warning screens
- [docs/display.md](docs/display.md): the split-DSI command-mode display as the bootloader leaves it, how to send frames, raw MDP/DSI register dump

## The phone used

ZTE Axon 7 A2017G, 64 GB / 4 GB, bootloader unlocked, TWRP 3.3.0-0 as
recovery. All values in the docs come from this device (its downstream
device tree, our probe shim's register dumps, and boot tests).

## What is not in this repository

Proprietary firmware (Qualcomm/ZTE blobs), Apple software (IPSW contents),
ROM zips, and dumps of the phone's partitions. The docs say where each of
them comes from on your own device.

## Cloning

```sh
git clone --recurse-submodules https://github.com/devilAPI/zte-axon7
```
