/*
 * AIDL android.hardware.nfc HAL for the ZTE Axon 7's NXP PN548.
 *
 * The PN548 speaks NCI 1.1 and keeps its own firmware, so all the NCI work
 * can stay in AOSP's libnfc-nci stack (packages/modules/Nfc). This HAL only
 * owns the raw character device from the kernel's pn5xx-raw driver:
 *
 *   open()      power the chip up, start the reader, send OPEN_CPLT
 *   write()     pass NCI commands to the chip
 *   read thread pass NCI responses/notifications to INfcClientCallback
 *   close()     power down and stop the reader, send CLOSE_CPLT
 *
 * CORE_RESET/CORE_INIT and RF discovery are handled by libnfc-nci, not here.
 */
#define LOG_TAG "nfc-service.axon7m"

#include <aidl/android/hardware/nfc/BnNfc.h>
#include <aidl/android/hardware/nfc/INfc.h>
#include <aidl/android/hardware/nfc/INfcClientCallback.h>
#include <aidl/android/hardware/nfc/NfcCloseType.h>
#include <aidl/android/hardware/nfc/NfcConfig.h>
#include <aidl/android/hardware/nfc/NfcEvent.h>
#include <aidl/android/hardware/nfc/NfcStatus.h>
#include <aidl/android/hardware/nfc/PresenceCheckAlgorithm.h>
#include <android-base/logging.h>
#include <android/binder_ibinder.h>
#include <android/binder_manager.h>
#include <android/binder_process.h>

#include <pthread.h>
#include <signal.h>
#include <sys/ioctl.h>

#include <atomic>
#include <cerrno>
#include <cstring>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include <fcntl.h>
#include <unistd.h>

namespace aidl {
namespace android {
namespace hardware {
namespace nfc {

using ::ndk::ScopedAStatus;

namespace {

// Same ioctl as ZTE's pn5xx_i2c.c and drivers/nfc/pn5xx-raw.c.
constexpr unsigned kPn544Magic = 0xE9;
constexpr unsigned kPn5xxSetPwr = _IOW(kPn544Magic, 0x01, unsigned int);
constexpr const char* kDevice = "/dev/nq-nci";
constexpr const char* kFallbackDevice = "/dev/pn54x";
constexpr size_t kMaxFrame = 512;

ScopedAStatus failed() {
  return ScopedAStatus::fromServiceSpecificError(
      static_cast<int32_t>(NfcStatus::FAILED));
}

}  // namespace

class Nfc : public BnNfc {
 public:
  Nfc() = default;
  ~Nfc() override { close(NfcCloseType::DISABLE); }

  ScopedAStatus open(
      const std::shared_ptr<INfcClientCallback>& clientCallback) override {
    if (clientCallback == nullptr) return failed();
    if (fd_.load() >= 0) {
      LOG(WARNING) << "open on an already open device";
      return failed();
    }

    int fd = ::open(kDevice, O_RDWR | O_CLOEXEC);
    if (fd < 0) {
      fd = ::open(kFallbackDevice, O_RDWR | O_CLOEXEC);
    }
    if (fd < 0) {
      PLOG(ERROR) << "cannot open the PN548 character device";
      return failed();
    }
    if (::ioctl(fd, kPn5xxSetPwr, 1u) < 0) {
      PLOG(ERROR) << "PN5XX_SET_PWR(1) failed";
      ::close(fd);
      return failed();
    }

    fd_.store(fd);
    {
      std::lock_guard<std::mutex> lock(callback_lock_);
      callback_ = clientCallback;
      death_recipient_ = AIBinder_DeathRecipient_new(onClientDeath);
      if (death_recipient_ != nullptr) {
        AIBinder_linkToDeath(clientCallback->asBinder().get(),
                             death_recipient_, this);
      }
    }

    stop_reader_ = false;
    reader_ = std::thread(&Nfc::readerLoop, this);
    LOG(INFO) << "open: " << kDevice << " fd " << fd << ", reader started";
    sendEvent(NfcEvent::OPEN_CPLT, NfcStatus::OK);
    return ScopedAStatus::ok();
  }

  ScopedAStatus close(NfcCloseType /*type*/) override {
    if (fd_.load() < 0) return failed();

    stop_reader_ = true;
    if (reader_.joinable()) {
      // The kernel driver's read() waits for an IRQ and has no ->poll();
      // bionic has no pthread_cancel, so a no-op SIGUSR1 interrupts it.
      pthread_kill(reader_.native_handle(), SIGUSR1);
      reader_.join();
    }

    int fd = fd_.exchange(-1);
    if (fd >= 0) {
      if (::ioctl(fd, kPn5xxSetPwr, 0u) < 0) {
        PLOG(WARNING) << "PN5XX_SET_PWR(0) failed";
      }
      ::close(fd);
    }

    sendEvent(NfcEvent::CLOSE_CPLT, NfcStatus::OK);
    std::shared_ptr<INfcClientCallback> old_callback;
    AIBinder_DeathRecipient* recipient = nullptr;
    {
      std::lock_guard<std::mutex> lock(callback_lock_);
      old_callback = callback_;
      recipient = death_recipient_;
      callback_ = nullptr;
      death_recipient_ = nullptr;
    }
    if (recipient != nullptr) {
      if (old_callback != nullptr) {
        AIBinder_unlinkToDeath(old_callback->asBinder().get(), recipient, this);
      }
      AIBinder_DeathRecipient_delete(recipient);
    }
    LOG(INFO) << "close: device released";
    return ScopedAStatus::ok();
  }

  ScopedAStatus coreInitialized() override {
    if (fd_.load() < 0) return failed();
    // PN548 holds its own firmware; there is nothing to download here.
    LOG(INFO) << "coreInitialized: no vendor patch download needed";
    sendEvent(NfcEvent::POST_INIT_CPLT, NfcStatus::OK);
    return ScopedAStatus::ok();
  }

  ScopedAStatus factoryReset() override {
    LOG(INFO) << "factoryReset: no persistent state in this HAL";
    return ScopedAStatus::ok();
  }

  ScopedAStatus getConfig(NfcConfig* config) override {
    *config = NfcConfig{};
    config->presenceCheckAlgorithm =
        PresenceCheckAlgorithm::ISO_DEP_NAK;
    config->maxIsoDepTransceiveLength = 261;
    return ScopedAStatus::ok();
  }

  ScopedAStatus powerCycle() override {
    int fd = fd_.load();
    if (fd < 0) return failed();
    LOG(INFO) << "powerCycle";
    if (::ioctl(fd, kPn5xxSetPwr, 0u) < 0 ||
        ::ioctl(fd, kPn5xxSetPwr, 1u) < 0) {
      PLOG(ERROR) << "powerCycle failed";
      sendEvent(NfcEvent::ERROR, NfcStatus::FAILED);
      return failed();
    }
    sendEvent(NfcEvent::OPEN_CPLT, NfcStatus::OK);
    return ScopedAStatus::ok();
  }

  ScopedAStatus preDiscover() override {
    if (fd_.load() < 0) return failed();
    sendEvent(NfcEvent::PRE_DISCOVER_CPLT, NfcStatus::OK);
    return ScopedAStatus::ok();
  }

  ScopedAStatus write(const std::vector<uint8_t>& data,
                      int32_t* written) override {
    int fd = fd_.load();
    if (fd < 0 || data.empty()) {
      *written = 0;
      return failed();
    }
    if (verbose_) {
      LOG(DEBUG) << "write " << data.size() << " bytes, first "
                 << static_cast<int>(data[0]) << " / "
                 << static_cast<int>(data[1]);
    }
    size_t offset = 0;
    while (offset < data.size()) {
      ssize_t n = ::write(fd, data.data() + offset, data.size() - offset);
      if (n < 0) {
        if (errno == EINTR) continue;
        PLOG(ERROR) << "write to PN548 failed";
        *written = static_cast<int32_t>(offset);
        return failed();
      }
      offset += static_cast<size_t>(n);
    }
    *written = static_cast<int32_t>(offset);
    return ScopedAStatus::ok();
  }

  ScopedAStatus setEnableVerboseLogging(bool enable) override {
    verbose_ = enable;
    return ScopedAStatus::ok();
  }

  ScopedAStatus isVerboseLoggingEnabled(bool* enable) override {
    *enable = verbose_;
    return ScopedAStatus::ok();
  }

  ScopedAStatus controlGranted(NfcStatus* status) override {
    // This HAL never sends REQUEST_CONTROL; libnfc-nci owns the NFCC.
    *status = NfcStatus::OK;
    return ScopedAStatus::ok();
  }

 private:
  static void onClientDeath(void* cookie) {
    auto* self = static_cast<Nfc*>(cookie);
    std::shared_ptr<INfcClientCallback> callback;
    {
      std::lock_guard<std::mutex> lock(self->callback_lock_);
      callback = self->callback_;
    }
    if (callback != nullptr &&
        !AIBinder_isAlive(callback->asBinder().get())) {
      LOG(WARNING) << "NFC client died, closing the device";
      self->close(NfcCloseType::DISABLE);
    }
  }

  std::shared_ptr<INfcClientCallback> getCallback() {
    std::lock_guard<std::mutex> lock(callback_lock_);
    return callback_;
  }

  void sendEvent(NfcEvent event, NfcStatus status) {
    auto callback = getCallback();
    if (callback == nullptr) return;
    auto ret = callback->sendEvent(event, status);
    if (!ret.isOk()) {
      LOG(ERROR) << "sendEvent failed: " << ret.getDescription();
    }
  }

  void sendData(const uint8_t* data, size_t size) {
    auto callback = getCallback();
    if (callback == nullptr) return;
    std::vector<uint8_t> frame(data, data + size);
    if (verbose_) {
      LOG(DEBUG) << "received " << size << " bytes, first "
                 << static_cast<int>(frame[0]) << " / "
                 << static_cast<int>(frame[1]);
    }
    auto ret = callback->sendData(frame);
    if (!ret.isOk()) {
      LOG(ERROR) << "sendData failed: " << ret.getDescription();
    }
  }

  void readerLoop() {
    while (!stop_reader_) {
      int fd = fd_.load();
      if (fd < 0) return;
      uint8_t buffer[kMaxFrame];
      ssize_t n = ::read(fd, buffer, sizeof(buffer));
      if (n > 0) {
        sendData(buffer, static_cast<size_t>(n));
      } else if (n < 0 && errno != EINTR && !stop_reader_) {
        PLOG(ERROR) << "read from PN548 failed";
        sendEvent(NfcEvent::ERROR, NfcStatus::ERR_TRANSPORT);
        return;
      }
    }
  }

  std::atomic<int> fd_{-1};
  std::atomic<bool> stop_reader_{false};
  std::atomic<bool> verbose_{false};
  std::thread reader_;
  std::mutex callback_lock_;
  std::shared_ptr<INfcClientCallback> callback_;
  AIBinder_DeathRecipient* death_recipient_ = nullptr;
};

}  // namespace nfc
}  // namespace hardware
}  // namespace android
}  // namespace aidl

int main() {
  using ::aidl::android::hardware::nfc::Nfc;
  using ::aidl::android::hardware::nfc::INfc;

  LOG(INFO) << "Axon 7 PN548 NFC AIDL HAL starting";
  struct sigaction sa{};
  sa.sa_handler = [](int) {};
  sigemptyset(&sa.sa_mask);
  sa.sa_flags = 0;  // no SA_RESTART: read() must return EINTR on close
  if (sigaction(SIGUSR1, &sa, nullptr) < 0) {
    PLOG(ERROR) << "cannot install SIGUSR1 handler";
    return 1;
  }
  if (!ABinderProcess_setThreadPoolMaxThreadCount(4)) {
    LOG(ERROR) << "cannot set binder thread pool size";
    return 1;
  }
  auto service = ndk::SharedRefBase::make<Nfc>();
  const std::string instance = std::string(INfc::descriptor) + "/default";
  binder_status_t status =
      AServiceManager_addService(service->asBinder().get(), instance.c_str());
  if (status != STATUS_OK) {
    LOG(ERROR) << "cannot register " << instance << ": " << status;
    return 1;
  }
  LOG(INFO) << "registered " << instance;
  ABinderProcess_joinThreadPool();
  return 0;
}
