/*
 * QMI clients over QRTR for the radio HAL. On QRTR a QMI client is just a
 * datagram socket port (no client id to allocate): the modem's services are
 * found through the kernel's name service. Requests use one socket each so a
 * slow modem never blocks a binder thread; QmiListener keeps a socket open for
 * indications from DMS/NAS/UIM/WMS/WDS and re-looks the service up if it goes
 * away with the modem.
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#pragma once

#include <atomic>
#include <cstdint>
#include <functional>
#include <map>
#include <memory>
#include <optional>
#include <string>
#include <thread>
#include <vector>

namespace axon7m::radio {

enum QmiService : uint32_t {
    kWds = 1,
    kDms = 2,
    kNas = 3,
    kWms = 5,
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
                                      int timeoutMs = 1000);

// A request a listener sends once it has a socket to the service (event
// registration, operating-mode reports, ...). It is repeated after a modem
// restart.
struct QmiRegistration {
    uint16_t msg;
    std::vector<uint8_t> tlvs;
};

class QmiListener {
  public:
    using Callback = std::function<void(uint16_t msg, const QmiResponse& response)>;
    QmiListener(uint32_t service, std::vector<QmiRegistration> registrations, Callback callback);
    ~QmiListener();

    QmiListener(const QmiListener&) = delete;
    QmiListener& operator=(const QmiListener&) = delete;

  private:
    void run();

    const uint32_t mService;
    const std::vector<QmiRegistration> mRegistrations;
    const Callback mCallback;
    std::atomic<bool> mStop{false};
    std::thread mThread;
};

// TLV builders and readers (little-endian)
void putTlvU8(std::vector<uint8_t>* b, uint8_t type, uint8_t v);
void putTlvU16(std::vector<uint8_t>* b, uint8_t type, uint16_t v);
void putTlvU32(std::vector<uint8_t>* b, uint8_t type, uint32_t v);
template <typename T>
bool getLe(const std::vector<uint8_t>& b, size_t off, T* out) {
    if (off + sizeof(T) > b.size()) return false;
    T v = 0;
    for (size_t i = 0; i < sizeof(T); i++) v |= static_cast<T>(b[off + i]) << (8 * i);
    *out = v;
    return true;
}

}  // namespace axon7m::radio
