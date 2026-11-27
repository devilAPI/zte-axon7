# Copyright (C) 2009 The Android Open Source Project
# Copyright (c) 2011, The Linux Foundation. All rights reserved.
# Copyright (C) 2017 The LineageOS Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# PC-test fixture: releasetools.py for the LineageOS 22.2 axon7 device tree
# as it is on main (patch 0020, TrustZone assertion only). It deliberately
# has no vendor-partition assertion: the stock partition layout without a
# vendor partition is supported by agent/stock22, so the installer must not
# refuse that layout before writing. From d6890eb with that assert removed.

import re

import common  # noqa: F401 - provided as a stub by the PC test


def FullOTA_Assertions(info):
  AddTrustZoneAssertion(info, info.input_zip)
  return


def IncrementalOTA_Assertions(info):
  AddTrustZoneAssertion(info, info.target_zip)
  return


def AddTrustZoneAssertion(info, input_zip):
  android_info = input_zip.read("OTA/android-info.txt").decode()
  m = re.search(r'require\s+version-trustzone\s*=\s*(\S+)', android_info)
  if m:
    versions = m.group(1).split('|')
    if len(versions) and '*' not in versions:
      cmd = 'assert(axon7.verify_trustzone(' + ','.join(['"%s"' % tz for tz in versions]) + ') == "1");'
      info.script.AppendExtra(cmd)
  return
