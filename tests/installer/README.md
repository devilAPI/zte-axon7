# PC installer-preflight tests

No phone, no root and no flashing: these tests run updater logic against fake
zips and fake partition tables. They came from `agent/twrp22` (commits
f42b591/d6890eb), with the LineageOS 22.2 vendor requirement removed.

```
python3 tests/installer/test_los22_preflight.py
bash tests/installer/test_los24_preflight.sh
```

- **LineageOS 22.2** (`test_los22_preflight.py`, `los22-releasetools.py`):
  checks that the TrustZone assertion is emitted before writes, that the
  device model is asserted in the device tree, and that no `vendor`
  partition assertion was reintroduced. `agent/stock22` supports ZTE's
  original layout with no vendor partition, so d6890eb's 0058 "vendor
  partition required" patch and its tests are deliberately not here. The
  fixture mirrors main's releasetools (patch 0020, TZ assertion only); it is
  not a device-tree patch.
- **LineageOS 24** (`test_los24_preflight.sh`, `los24-update-binary`): runs
  the updater script itself with `AXON7_TEST_*` paths pointing at fake sysfs
  and block devices. Checks refusal before any write for unknown device or
  model, wrong or unreadable TrustZone, and missing vendor partition. The
  LOS 24 installer still needs a vendor partition for the GPU firmware;
  that requirement is separate from the LOS 22.2 one. The updater is a
  test fixture copied from d6890eb and may lag the current CI copy (for
  example, the later `axon7m` device token).
