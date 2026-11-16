/*
 * android.hardware.radio-service.axon7m: radio config, data, modem, network
 * and SIM on slot 1 (see Radio.h). Structure from AOSP's minradio example.
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#include "ModemState.h"
#include "Radio.h"

#include <android-base/logging.h>
#include <android/binder_manager.h>
#include <android/binder_process.h>

#include <chrono>
#include <thread>

using namespace std::string_literals;

namespace axon7m::radio {

static std::vector<std::shared_ptr<ndk::ICInterface>> gPublishedHals;

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
        context->addHal(hal);
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
    // the QMI services come and go with the modem; requests made while it is
    // down answer MODEM_ERR, so the HAL can start before the modem
    slot1->setConnected();
    LOG(INFO) << "radio HAL up (QMI over QRTR)";

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
