# ZTE Axon 7 (A2017G) bring-up

Three ways of running something new on the ZTE Axon 7 (Snapdragon 820,
`ailsa_ii` / `axon7`), and everything learned about the phone along the way.

| Project | Status (2026-11-05) |
| --- | --- |
| [**iOS 16 on the Axon 7**](ios/) (XNU port, submodule: [devilAPI/ios-sailfish](https://github.com/devilAPI/ios-sailfish/tree/axon7), branch `axon7`) | Apple's XNU kernel boots on the phone: shim, MMU, VM, zone allocator and the kernel console on the full 1440x2560 screen. Next: UFS root, iOS userland |
| [**postmarketOS**](postmarketos/) (mainline Linux 7.3.1) | device tree, kernel and device packages written, kernel builds; first boot test pending |
| [**LineageOS**](lineageos/) | 18.1 (Android 11) is the newest that exists; plan for porting 22.2 (Android 15) |

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
