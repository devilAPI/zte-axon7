/*
 * axon7m-gnss-test [SECONDS]: a second QMI LOC client next to the HAL (QMI
 * allows several), for checking the modem's GNSS without an app: starts a
 * session, prints a summary of the satellite and position reports every 5 s
 * and the first fix, stops after SECONDS (default 120).
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#include "LocClient.h"

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <mutex>
#include <thread>

using namespace axon7m::gnss;

namespace {
class Printer : public LocClient::Listener {
  public:
    void onPosition(const LocPosition& p) override {
        std::lock_guard l(m);
        positions++;
        if (p.sessionStatus == 0 && p.latitude && p.longitude) {
            fixes++;
            if (fixes == 1)
                printf("first fix: %.5f %.5f +-%.0f m, %zu satellites used\n", *p.latitude,
                       *p.longitude, p.horizontalUncertainty.value_or(-1), p.usedSvIds.size());
        }
    }
    void onSvInfo(const std::vector<LocSv>& svs) override {
        std::lock_guard l(m);
        svReports++;
        seen = svs.size();
        heard = tracked = 0;
        maxSnr = 0;
        for (auto& s : svs) {
            if (s.snr > 0) heard++;
            if (s.state == 3) tracked++;
            if (s.snr > maxSnr) maxSnr = s.snr;
        }
    }
    void onNmea(const std::string&) override {
        std::lock_guard l(m);
        nmea++;
    }
    void print(int t) {
        std::lock_guard l(m);
        printf("t=%3ds sv-reports %d (last: %zu listed, %d heard, %d tracked, max %.0f dB-Hz) "
               "positions %d fixes %d nmea %d\n",
               t, svReports, seen, heard, tracked, maxSnr, positions, fixes, nmea);
        fflush(stdout);
    }
    std::mutex m;
    int svReports = 0, positions = 0, fixes = 0, nmea = 0, heard = 0, tracked = 0;
    size_t seen = 0;
    float maxSnr = 0;
};
}  // namespace

int main(int argc, char** argv) {
    int secs = argc > 1 ? atoi(argv[1]) : 120;
    Printer p;
    LocClient c(&p);
    c.setSession(true, 1000);
    for (int t = 5; t <= secs; t += 5) {
        std::this_thread::sleep_for(std::chrono::seconds(5));
        p.print(t);
    }
    c.setSession(false, 1000);
    std::this_thread::sleep_for(std::chrono::milliseconds(500));
    c.shutdown();
    return 0;
}
