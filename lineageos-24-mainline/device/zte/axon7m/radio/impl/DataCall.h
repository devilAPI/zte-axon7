/*
 * Mobile data on the Axon 7: QMI WDS/WDA/DPM calls over QRTR and the QMAP
 * rmnet link over rmnet_ipa0 (ipa2-lite). Kept separate from RadioData so the
 * AIDL subclass only has to report the result to the framework.
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#pragma once

#include <aidl/android/hardware/radio/RadioError.h>
#include <aidl/android/hardware/radio/data/DataProfileInfo.h>
#include <aidl/android/hardware/radio/data/SetupDataCallResult.h>

#include <cstdint>
#include <map>
#include <mutex>
#include <string>
#include <vector>

namespace axon7m::radio {

namespace aidlData = ::aidl::android::hardware::radio::data;
using ::aidl::android::hardware::radio::RadioError;

struct DataCallSetup {
    bool ok = false;
    RadioError error = RadioError::MODEM_ERR;
    aidlData::SetupDataCallResult result;
};

class DataCallManager {
  public:
    // A cid comes from libminradio's setupDataCallCid(); no QMI call is made
    // on a binder thread until the framework asks for a data call.
    DataCallSetup setup(int32_t cid, const aidlData::DataProfileInfo& profile, bool roamingAllowed);
    RadioError deactivate(int32_t cid);
    std::vector<aidlData::SetupDataCallResult> list() const;

  private:
    struct Call {
        uint32_t handle = 0;  // WDS packet data handle
        uint8_t muxId = 0;
        std::string ifname;
        aidlData::SetupDataCallResult report;
    };

    mutable std::mutex mLock;
    std::map<int32_t, Call> mCalls;
    uint8_t mNextMux = 1;
};

}  // namespace axon7m::radio
