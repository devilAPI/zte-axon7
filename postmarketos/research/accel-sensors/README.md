# Accelerometer scale: build and test artifacts (2026-11-22)

Kernel fix: Nura patch 0059 (`0059-iio-accel-smgr_accel-correct-scale-to-match-SLPI-factory-calibration.patch`).
The SLPI applies the phone's factory calibration from `/persist/sensors/sns.reg`,
so 1 g is about 690310 counts instead of the 640000 assumed by the old WIP
driver. `smgr_accel` reports `IIO_VAL_INT_PLUS_NANO` with 0 / 14211
(9.81 / 690310 = 0.000014211 m/s^2 per LSB) instead of 0 / 15328.

## Compiled module

`CONFIG_IIO_QCOM_SMGR_ACCEL=m`, so the fix can be checked in the running
LineageOS 24 kernel (build #31) without a test kernel or a reboot.

Build recipe (pinned clang, same config and patches as the #31 boot image):

```sh
KSRC=~/axon7-kbuild/linux            # shared tree, HEAD d9f5e3d6a + Nura/LOS patches
KOUT=~/axon7-kbuild/accel-kout2      # copy of ~/axon7-kbuild/out-r536225 (no spaces in path!)
CL=~/axon7-kbuild/clang-r536225
PATH=$CL/bin:$PATH LD_LIBRARY_PATH=$CL/lib64:$CL/lib \
make -C $KSRC O=$KOUT ARCH=arm64 LLVM=1 LLVM_IAS=1 LOCALVERSION= \
  HOSTCFLAGS="-I/usr/include -I/usr/include/x86_64-linux-gnu" \
  HOSTLDFLAGS="-L/usr/lib/x86_64-linux-gnu -fuse-ld=lld" \
  -j2 M=drivers/iio/accel modules
# kbuild writes M= modules into the *source* dir:
cp $KSRC/drivers/iio/accel/smgr_accel.ko /media/devilapi/Secondary\ HDD\ 2TB/ai-worker/axon7/accel-build/smgr_accel-fixed.ko
```

Evidence the compiled module carries the new constant (`llvm-objdump -d`,
`smgr_accel_read_raw`; the old module from `prebuilt/modules/smgr_accel.ko`
has `mov w8, #0x3be0` = 15328):

```
164: 5286f068      mov w8, #0x3783             // =14211
168: 52800060      mov w0, #0x3                // =3
```

`modinfo accel-build/smgr_accel-fixed.ko`: `depends: smgr`,
`vermagic: 7.3.1-axon7m SMP preempt mod_unload aarch64` (same as the image's
module). sha256 `df9d684c4fd5c1b6643e73f48db34484dfcf458407575f2fb2b26cde4c532bbb`.

## On-phone test

`../accel-build/smgr_accel-fixed.ko` and `accel-build/sensread` (NDK r30 build
of `lineageos-24-mainline/tools/sensread.c`, sha256
`c3048ce7a39b26e53c7da0e879b2c897a42765706721e8af0191048ce3ec35bd`) are ready
outside the git worktree.

`smgr-accel-module-test.sh` runs under the main phone's flock, saves the
original `/vendor/lib/modules/smgr_accel.ko` on the HDD, stops
`vendor.sensors-axon7m`, unbinds the `qcom-smgr-accel` platform device, swaps
the module, reads `in_accel_scale` and measures with `sensread` (buffered IIO,
so there are no `in_accel_*_raw` files), then
restores the original module and HAL. It never touches boot/misc/persist/EFS.

**Status 2026-11-22: verified on the main phone in LOS 24 build #31.**
`smgr-accel-module-test.sh` was run under the phone's flock: `in_accel_scale`
went from 0.000015328 to 0.000014211 and the resting magnitude from 10.650 to
9.876 m/s² (target 9.81 ± 1 %); gyro bias and mag magnitude were unchanged.
The original module/HAL were restored and adb stayed up. Full measurements,
the test log and the one-orientation limitation are in
`RESULTS-2026-11-22.md` and `2026-11-22-module-swap.log`.
`qcom-smgr-accel` is buffered-only (no `in_accel_*_raw` sysfs files), so the
log uses `sensread` for the acceleration values.
