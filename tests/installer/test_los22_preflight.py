#!/usr/bin/env python3
"""PC tests for the LineageOS 22.2 (axon7) edify-OTA preflight.

From f42b591/d6890eb (agent/twrp22), with every vendor-partition test and
the 0058 "vendor required" patch check removed: agent/stock22 supports
ZTE's original partition layout with no vendor partition, so asserting one
before the write would refuse a supported layout. What stays is the
TrustZone/download preflight and the device-model assertion, both checked
against fixture zip metadata and the device-tree patches on this branch.
No phone, no root.
"""
import importlib.util
import sys
import types
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
RELEASETOOLS = HERE / "los22-releasetools.py"
PORT = ROOT / "lineageos-22.2" / "port-22.2" / "device_zte_axon7"


class FakeScript:
    def __init__(self):
        self.lines = []

    def AppendExtra(self, s):
        self.lines.append(s)

    def text(self):
        return "\n".join(self.lines)


class FakeZip:
    def __init__(self, entries):
        self.entries = entries

    def read(self, name):
        v = self.entries[name]
        return v if isinstance(v, bytes) else v.encode()


class FakeInfo:
    def __init__(self, entries):
        self.input_zip = FakeZip(entries)
        self.target_zip = self.input_zip
        self.script = FakeScript()


def load_releasetools():
    sys.modules.setdefault("common", types.ModuleType("common"))
    spec = importlib.util.spec_from_file_location("releasetools_axon7", RELEASETOOLS)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class TestLos22ReleasetoolsPreflight(unittest.TestCase):
    def setUp(self):
        self.rt = load_releasetools()

    def emit(self, tz="TZ.BF.4.0.1-00353", entries=None):
        info = FakeInfo(entries or {"OTA/android-info.txt": f"require version-trustzone={tz}\n"})
        self.rt.FullOTA_Assertions(info)
        return info.script.lines

    # --- TrustZone / bootloader ---

    def test_tz_assert_emitted(self):
        lines = self.emit()
        joined = "\n".join(lines)
        self.assertIn('axon7.verify_trustzone("TZ.BF.4.0.1-00353")', joined)
        self.assertIn('== "1"', joined)

    def test_wrong_tz_not_accepted_by_assert(self):
        # The emitted assert only accepts the board-info TZ; a different TZ
        # string is not in the allowed list.
        lines = self.emit(tz="TZ.BF.4.0.1-00353")
        joined = "\n".join(lines)
        self.assertNotIn("TZ.BF.4.0.1-00001", joined)
        self.assertIn("TZ.BF.4.0.1-00353", joined)

    def test_tz_assert_before_writes(self):
        lines = self.emit()
        tz_i = next(i for i, l in enumerate(lines) if "verify_trustzone" in l)
        write_markers = ("block_image_update", "package_extract_file", "write_raw_image", "format(")
        for i, l in enumerate(lines):
            if any(w in l for w in write_markers):
                self.assertGreater(i, tz_i, f"write before TZ assert: {l}")

    # --- no vendor-partition requirement (stock layout is supported) ---

    def test_no_vendor_partition_assert(self):
        joined = "\n".join(self.emit()).lower()
        self.assertNotIn("vendor", joined)
        self.assertNotIn("AddVendorPartitionAssertion", joined)

    def test_no_vendor_assert_patch_on_this_branch(self):
        # 0058 from agent/twrp22 would refuse phones with no vendor partition.
        # agent/stock22 supports the stock layout instead; neither that patch
        # nor the refusing one belongs on main in this change.
        patches = sorted(p.name for p in PORT.glob("*.patch"))
        self.assertFalse(any("installer-preflight-refuse" in p for p in patches), patches)

    # --- model / device ---

    def test_model_assert_device_declared(self):
        # Model/unknown-device refusal is enforced by TARGET_OTA_ASSERT_DEVICE
        # in BoardConfig.mk (the build system emits a getprop ro.product.device
        # assert) and by the device's OTA assert device list.
        bc = PORT / "0001-axon7-BoardConfig-fstab-and-init-for-lineage-22.2.patch"
        text = bc.read_text(errors="ignore")
        self.assertIn("TARGET_OTA_ASSERT_DEVICE := ailsa_ii,axon7", text)

    def test_board_info_trustzone_present(self):
        notes = ROOT / "lineageos-22.2" / "FLASHING-PLAN.md"
        text = notes.read_text(errors="ignore")
        self.assertIn("TZ.BF.4.0.1-00353", text)

    def test_incremental_has_same_preflight(self):
        info = FakeInfo({"OTA/android-info.txt": "require version-trustzone=TZ.BF.4.0.1-00353\n"})
        self.rt.IncrementalOTA_Assertions(info)
        joined = "\n".join(info.script.lines)
        self.assertIn("verify_trustzone", joined)
        self.assertNotIn("vendor", joined.lower())


if __name__ == "__main__":
    unittest.main(verbosity=2)
