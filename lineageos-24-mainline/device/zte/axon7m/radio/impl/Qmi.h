/*
 * Synchronous QMI requests over QRTR for the radio HAL: one datagram socket
 * per request (on QRTR a QMI client is just a socket port, no client id to
 * allocate), the service is found through the kernel's name service. Fine
 * for the few polled requests this HAL makes; indications are not used.
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#pragma once

#include <cstdint>
#include <map>
#include <optional>
#include <string>
#include <vector>

namespace axon7m::radio {

enum QmiService : uint32_t {
    kDms = 2,
    kNas = 3,
    kUim = 11,
};

struct QmiResponse {
    uint16_t result = 0xffff;  // 0 = success
    uint16_t error = 0;
    std::map<uint8_t, std::vector<uint8_t>> tlvs;

    bool ok() const { return result == 0; }
    const std::vector<uint8_t>* tlv(uint8_t type) const {
        auto it = tlvs.find(type);
        return it == tlvs.end() ? nullptr : &it->second;
    }
};

// One request; nullopt when the service is not there or does not answer
// within timeoutMs.
std::optional<QmiResponse> qmiRequest(uint32_t service, uint16_t msg,
                                      const std::vector<uint8_t>& tlvs = {},
                                      int timeoutMs = 2000);

// TLV builders and readers (little-endian)
void putTlvU8(std::vector<uint8_t>* b, uint8_t type, uint8_t v);
template <typename T>
bool getLe(const std::vector<uint8_t>& b, size_t off, T* out) {
    if (off + sizeof(T) > b.size()) return false;
    T v = 0;
    for (size_t i = 0; i < sizeof(T); i++) v |= static_cast<T>(b[off + i]) << (8 * i);
    *out = v;
    return true;
}

}  // namespace axon7m::radio
