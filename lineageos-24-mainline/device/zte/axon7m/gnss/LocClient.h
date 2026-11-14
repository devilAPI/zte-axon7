/*
 * QMI LOC client on a QRTR socket (see LocClient.cpp for the protocol).
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#pragma once

#include <linux/qrtr.h>
#include <sys/socket.h>

#include <atomic>
#include <chrono>
#include <cstdint>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <vector>

namespace axon7m::gnss {

// QMI_LOC_EVENT_POSITION_REPORT_IND, only the fields the modem sent
struct LocPosition {
    uint32_t sessionStatus = UINT32_MAX;  // 0 = success (a fix), 1 = in progress
    std::optional<double> latitude, longitude;         // degrees
    std::optional<float> horizontalUncertainty;        // m, circular
    std::optional<float> altitudeEllipsoid;            // m above WGS84
    std::optional<float> verticalUncertainty;          // m
    std::optional<float> speed, speedUncertainty;      // m/s, horizontal
    std::optional<float> heading, headingUncertainty;  // degrees
    std::optional<uint64_t> utcMs;                     // UTC, ms since 1970
    std::vector<uint16_t> usedSvIds;                   // modem numbering
};

// QMI LOC satellite systems (SYSTEMS in axon7-gps)
enum class LocSystem : uint32_t {
    GPS = 1,
    GALILEO = 2,
    SBAS = 3,
    COMPASS = 4,  // BeiDou
    GLONASS = 5,
    BDS = 6,
    QZSS = 7,
};

// One entry of QMI_LOC_EVENT_GNSS_SV_INFO_IND
struct LocSv {
    uint32_t system = 0;  // LocSystem
    uint16_t svId = 0;    // modem numbering: GPS 1-32, SBAS 33-64 or 120-158,
                          // GLONASS 65-96, QZSS 193-197, BeiDou 201-237,
                          // Galileo 301-336
    uint32_t state = 0;   // 1 idle, 2 search, 3 track (0 unknown)
    bool hasEphemeris = false, hasAlmanac = false;
    float elevation = 0, azimuth = 0;  // degrees
    float snr = 0;                     // dB-Hz, 0 = not heard
};

class LocClient {
  public:
    // Called on the client's reader thread.
    class Listener {
      public:
        virtual ~Listener() = default;
        virtual void onPosition(const LocPosition& position) = 0;
        virtual void onSvInfo(const std::vector<LocSv>& svs) = 0;
        virtual void onNmea(const std::string& sentence) = 0;
    };

    explicit LocClient(Listener* listener);  // starts the reader thread
    ~LocClient();

    // Wanted state of the positioning session; the reader thread applies it
    // as soon as the LOC service is there (and again after a modem restart).
    void setSession(bool wanted, uint32_t intervalMs);

    // Stops the session and the reader thread. Idempotent.
    void shutdown();

  private:
    using Clock = std::chrono::steady_clock;

    void run();
    void startLookup();
    void handleCtrl();
    void handleData();
    void handleIndication(uint16_t msg, const uint8_t* tlvs, size_t len);
    void serviceLost(const char* why);
    void reconcile();
    bool sendQmi(uint16_t msg, const std::vector<uint8_t>& payload);
    bool sendStart(uint32_t intervalMs);
    static void closeFd(int* fd);

    Listener* const listener_;
    int wakeFd_ = -1;  // eventfd: setSession()/shutdown() wake the reader

    std::mutex mutex_;  // guards wanted_, intervalMs_
    bool wanted_ = false;
    uint32_t intervalMs_ = 1000;
    std::atomic<bool> exit_{false};
    std::mutex joinMutex_;
    std::thread thread_;

    // reader thread only
    int dataFd_ = -1;  // QMI messages to and from the LOC service
    int ctrlFd_ = -1;  // name service lookup (NEW_SERVER/DEL_SERVER events)
    bool haveService_ = false;
    sockaddr_qrtr service_{};
    Clock::time_point nextLookup_{};
    bool waitingLogged_ = false;
    bool active_ = false;  // START sent to the current service
    uint32_t activeIntervalMs_ = 0;
    uint16_t txn_ = 0;
    std::vector<uint8_t> buf_;
};

}  // namespace axon7m::gnss
