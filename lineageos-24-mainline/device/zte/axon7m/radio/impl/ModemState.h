/*
 * What the radio HAL knows about the modem, read over QMI (DMS, UIM, NAS)
 * and mapped to the radio AIDL types.
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#pragma once

#include <aidl/android/hardware/radio/network/RegStateResult.h>
#include <aidl/android/hardware/radio/network/SignalStrength.h>
#include <aidl/android/hardware/radio/sim/CardStatus.h>

#include <optional>
#include <string>

namespace axon7m::radio {

// UIM Get Card Status (0x2F), first slot; nullopt when UIM did not answer
std::optional<::aidl::android::hardware::radio::sim::CardStatus> readCardStatus();

// NAS Get Serving System (0x24); nullopt when NAS did not answer
std::optional<::aidl::android::hardware::radio::network::RegStateResult> readRegState();

// NAS Get Signal Info (0x4F); defaults (unavailable) when NAS did not answer
::aidl::android::hardware::radio::network::SignalStrength readSignalStrength();

// DMS Get IDs (0x25) TLV 0x11
std::optional<std::string> readImei();
// DMS Get Revision (0x23) TLV 0x01
std::optional<std::string> readRevision();
// DMS UIM Get IMSI (0x43) TLV 0x01
std::optional<std::string> readImsi();

}  // namespace axon7m::radio
