/*
 * android.hardware.radio-service.axon7m: config, data, modem, network, SIM,
 * messaging and a voice stub on slot 1 (see Radio.h, RadioMessaging.h,
 * RadioVoice.h). Structure from AOSP's minradio example.
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#include "ModemState.h"
#include "Qmi.h"
#include "Radio.h"
#include "RadioMessaging.h"
#include "RadioVoice.h"

#include <android-base/logging.h>
#include <android/binder_manager.h>
#include <android/binder_process.h>

#include <chrono>
#include <thread>
#include <type_traits>
#include <utility>

using namespace std::string_literals;

namespace axon7m::radio {

static std::vector<std::shared_ptr<ndk::ICInterface>> gPublishedHals;
// QMI listeners live for the whole process; they reconnect after a modem restart.
static std::vector<std::unique_ptr<QmiListener>> gListeners;

template <typename T>
static std::shared_ptr<T> publish(const std::string& instanceName,
                                   std::shared_ptr<minimal::SlotContext> context) {
    const auto instance = T::descriptor + "/"s + instanceName;
    if (!AServiceManager_isDeclared(instance.c_str())) {
        LOG(INFO) << instance << " is not declared in VINTF";
        return nullptr;
    }
    std::shared_ptr<T> hal;
    if constexpr (std::is_same_v<T, RadioConfig>) {
        hal = ndk::SharedRefBase::make<T>();
    } else {
        hal = ndk::SharedRefBase::make<T>(context);
        if constexpr (std::is_base_of_v<minimal::RadioSlotBase, T>) context->addHal(hal);
    }
    gPublishedHals.push_back(hal);
    CHECK_EQ(AServiceManager_addService(hal->asBinder().get(), instance.c_str()), STATUS_OK);
    return hal;
}

static void main() {
    android::base::InitLogging(nullptr, android::base::LogdLogger(android::base::RADIO));
    android::base::SetDefaultTag("radio-axon7m");
    android::base::SetMinimumLogSeverity(android::base::INFO);
    ABinderProcess_setThreadPoolMaxThreadCount(4);
    ABinderProcess_startThreadPool();

    auto slot1 = std::make_shared<minimal::SlotContext>(1);
    publish<RadioConfig>("default", slot1);
    publish<RadioData>("slot1", slot1);
    publish<RadioModem>("slot1", slot1);
    auto network = publish<RadioNetwork>("slot1", slot1);
    auto sim = publish<RadioSim>("slot1", slot1);
    auto messaging = publish<RadioMessaging>("slot1", slot1);
    publish<RadioVoice>("slot1", slot1);
    // the QMI services come and go with the modem; requests made while it is
    // down answer MODEM_ERR, so the HAL can start before the modem
    slot1->setConnected();
    LOG(INFO) << "radio HAL up (QMI over QRTR)";

    if (messaging) messaging->start();

    // Indications let the cached state change immediately (the 5 s poll is
    // still there for firmware that never sends them). A UIM status change is
    // turned into simStatusChanged by RadioSim::poll().
    std::vector<QmiRegistration> nas = {{0x03, {0x13, 1, 0, 1,  // serving system
                                                0x17, 1, 0, 1,  // network time
                                                0x18, 1, 0, 1,  // system info
                                                0x19, 1, 0, 1}}};  // signal info
    std::vector<QmiRegistration> dms = {{0x01, {0x14, 1, 0, 1}}};  // operating mode
    std::vector<QmiRegistration> uim = {{0x2E, {0x01, 4, 0, 1, 0, 0, 0}}};  // card status
    std::vector<QmiRegistration> wms = {{0x01, {0x10, 1, 0, 1}}};  // MT messages
    std::vector<QmiRegistration> wds = {{0x01, {0x12, 1, 0, 1,  // bearer technology
                                                0x17, 1, 0, 1}}};  // data call status
    auto refresh = [network, sim](uint16_t, const QmiResponse&) {
        refreshModemState();
        if (sim) sim->poll();
        if (network) network->poll();
    };
    gListeners.push_back(std::make_unique<QmiListener>(kDms, std::move(dms), refresh));
    gListeners.push_back(std::make_unique<QmiListener>(kNas, std::move(nas), refresh));
    gListeners.push_back(std::make_unique<QmiListener>(kUim, std::move(uim), refresh));
    gListeners.push_back(std::make_unique<QmiListener>(
            kWms, std::move(wms),
            [messaging](uint16_t msg, const QmiResponse& r) {
                if (messaging) messaging->onIndication(msg, r);
            }));
    gListeners.push_back(std::make_unique<QmiListener>(
            kWds, std::move(wds), [](uint16_t msg, const QmiResponse& r) {
                if (msg == 0x01) {
                    const auto* status = r.tlv(0x1F);  // WDS Data Call Status
                    if (status && !status->empty())
                        LOG(INFO) << "WDS data call status " << static_cast<int>((*status)[0]);
                }
            }));

    std::thread([network, sim] {
        for (;;) {
            refreshModemState();
            if (sim) sim->poll();
            if (network) network->poll();
            std::this_thread::sleep_for(std::chrono::seconds(5));
        }
    }).detach();
    ABinderProcess_joinThreadPool();
    LOG(FATAL) << "radio HAL thread pool ended";
}

}  // namespace axon7m::radio

int main() {
    axon7m::radio::main();
    return EXIT_FAILURE;
}
