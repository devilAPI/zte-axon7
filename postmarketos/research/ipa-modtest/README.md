# Runtime IPA test without flashing a kernel (2026-11-22)

The MAIN phone's LineageOS 24 kernel (`7.3.1-axon7m #31`) has
`CONFIG_OF_OVERLAY=y`, `CONFIG_CONFIGFS_FS=y` (but no `of_overlay` configfs
directory), `CONFIG_MODVERSIONS=n` and adb root. That makes a module-only
test possible: no kernel image, boot or misc partition write and no reboot.

* `ipa-overlay.dtso` adds the same `ipa@680000` node as Nura patch 0062 to
  the running DT (`/soc@0` is the root soc node on this FDT). The RPM clock
  phandle `0x20` and `RPM_SMD_IPA_CLK=68` came from the phone's live
  `/sys/firmware/fdt`; `qcom,bam-remote-mode` keeps Linux from resetting the
  modem/TZ-owned BAM globals.
* `dt-helper.c` is a temporary module that calls `of_overlay_fdt_apply()`.
* `Makefile` builds a self-contained `ipa2-lite.ko` from the driver sources
  of patches 0059-0061 (the LOS config has no `CONFIG_QCOM_IPA2_LITE`).
* `build.sh`, `phone-testmode.sh`, `phone-full.sh` reproduce the build and
  the two test sessions. The test scripts require the MAIN-phone lock and
  refuse to probe unless adb root, boot_completed=1, battery >= 30 % and the
  `mss` remoteproc is running. They never write boot/misc and never reboot.

`modinfo -F vermagic` on both test modules must print
`7.3.1-axon7m SMP preempt mod_unload aarch64` before they are pushed to the
phone. After the test the modules stay loaded until the next reboot; the
real Nura patch applies the DT node at boot and loads the driver from
userspace only after the modem is up.

`qmi-wds.c` is a minimal QMI-over-QRTR client (kernel's 7-byte wire header)
built with the Android NDK on the build server:

```
NDK=/srv/los24/tools/android-ndk-r30
$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android30-clang \
  -O2 -Wall -o /tmp/qmi-wds qmi-wds.c
adb push /tmp/qmi-wds /data/local/tmp/qmi-wds
adb shell /data/local/tmp/qmi-wds 0 41 0x20        # WDS Get Packet Service Status
adb shell /data/local/tmp/qmi-wds 0 48 0x20 01040001000000  # WDA Set Data Format
```

The node/port pairs come from `qrtr-lookup` on the phone. Responses match
the transaction and command, but the result TLVs report failure because the
phone has no SIM/active data service; this is not a mobile-data proof.
