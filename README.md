# ZTE Axon 7 (A2017G) bring-up

Three ways of running something new on the ZTE Axon 7 (Snapdragon 820,
`ailsa_ii` / `axon7`), and everything learned about the phone along the way.

| Project | Status (2026-11-06) |
| --- | --- |
| [**iOS 16 on the Axon 7**](ios/) (XNU port, submodule: [devilAPI/ios-sailfish](https://github.com/devilAPI/ios-sailfish/tree/axon7), branch `axon7`) | iOS 16.7.16 (iPhone 8 userland) boots to the lock and home screen, GPU-accelerated (Adreno 530 via Mesa freedreno), touch, Home on Volume Down, rootless jailbreak with Sileo. Wi-Fi works, rejoining included (WPA2-PSK, DHCP, Safari, Sileo). OpenSSH and apt/Sileo installs work. Dual boot with postmarketOS: boot menu after the ZTE logo (Vol+/Vol- choose, Power starts). Details: [ios/PORTING-AXON7.md](ios/PORTING-AXON7.md) |
| [**postmarketOS**](postmarketos/) (mainline Linux 7.3.1) | boots from microSD via the boot menu: display (S6E3HA3 dual DSI), touch, on-screen keyboard (buffyboard), Wi-Fi, SSH, USB OTG (manual), on-device kernel updates |
| [**LineageOS**](lineageos/) | 22.2 (Android 15) port in progress (device tree, 4.4 kernel); the boot menu already has its entry and partitions |

**Want to try it?** Step-by-step installation guide (iOS + postmarketOS with a boot menu): [INSTALL.md](INSTALL.md)

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
