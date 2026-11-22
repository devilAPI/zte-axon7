/*
 * SPDX-License-Identifier: Apache-2.0
 */
#define LOG_TAG "radio-axon7m"

#include "Qmi.h"

#include <android-base/logging.h>
#include <android-base/unique_fd.h>

#include <linux/qrtr.h>
#include <poll.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#include <atomic>
#include <cerrno>
#include <cstring>
#include <mutex>
#include <utility>

#ifndef AF_QIPCRTR
#define AF_QIPCRTR 42
#endif

namespace axon7m::radio {

namespace {

std::atomic<uint16_t> gTxn{1};
std::mutex gCacheLock;
std::map<uint32_t, sockaddr_qrtr> gCache;  // service -> address

int64_t nowMs() {
    timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000LL + ts.tv_nsec / 1000000;
}

bool waitReadable(int fd, int64_t deadline) {
    for (;;) {
        int64_t left = deadline - nowMs();
        if (left <= 0) return false;
        pollfd p{fd, POLLIN, 0};
        int r = poll(&p, 1, static_cast<int>(left));
        if (r > 0) return true;
        if (r == 0) return false;
        if (errno != EINTR) return false;
    }
}

void delayMs(int ms) { poll(nullptr, 0, ms); }

std::optional<sockaddr_qrtr> lookup(uint32_t service, int64_t deadline) {
    {
        std::lock_guard l(gCacheLock);
        auto it = gCache.find(service);
        if (it != gCache.end()) return it->second;
    }
    android::base::unique_fd fd(socket(AF_QIPCRTR, SOCK_DGRAM | SOCK_CLOEXEC, 0));
    if (fd < 0) return std::nullopt;
    sockaddr_qrtr self{};
    socklen_t len = sizeof(self);
    if (getsockname(fd, reinterpret_cast<sockaddr*>(&self), &len) < 0) return std::nullopt;
    qrtr_ctrl_pkt pkt{};
    pkt.cmd = QRTR_TYPE_NEW_LOOKUP;
    pkt.server.service = service;
    sockaddr_qrtr ns{};
    ns.sq_family = AF_QIPCRTR;
    ns.sq_node = self.sq_node;
    ns.sq_port = QRTR_PORT_CTRL;
    if (sendto(fd, &pkt, sizeof(pkt), 0, reinterpret_cast<sockaddr*>(&ns), sizeof(ns)) < 0)
        return std::nullopt;
    while (waitReadable(fd, deadline)) {
        qrtr_ctrl_pkt r{};
        if (recv(fd, &r, sizeof(r), 0) < static_cast<ssize_t>(sizeof(r))) continue;
        if (r.cmd != QRTR_TYPE_NEW_SERVER) continue;
        if (r.server.service == 0 && r.server.node == 0 && r.server.port == 0) break;  // end
        if (r.server.service != service) continue;
        sockaddr_qrtr a{};
        a.sq_family = AF_QIPCRTR;
        a.sq_node = r.server.node;
        a.sq_port = r.server.port;
        std::lock_guard l(gCacheLock);
        gCache[service] = a;
        return a;
    }
    return std::nullopt;
}

void forget(uint32_t service) {
    std::lock_guard l(gCacheLock);
    gCache.erase(service);
}

uint16_t nextTxn() {
    uint16_t txn = gTxn++;
    if (txn == 0) txn = gTxn++;
    return txn;
}

void writeFrame(int fd, const sockaddr_qrtr& addr, uint16_t txn, uint16_t msg,
                const std::vector<uint8_t>& tlvs) {
    std::vector<uint8_t> b = {0, static_cast<uint8_t>(txn), static_cast<uint8_t>(txn >> 8),
                              static_cast<uint8_t>(msg), static_cast<uint8_t>(msg >> 8),
                              static_cast<uint8_t>(tlvs.size()),
                              static_cast<uint8_t>(tlvs.size() >> 8)};
    b.insert(b.end(), tlvs.begin(), tlvs.end());
    (void)sendto(fd, b.data(), b.size(), 0, reinterpret_cast<const sockaddr*>(&addr),
                 sizeof(addr));
}

QmiResponse parseResponse(const uint8_t* buf, size_t len) {
    QmiResponse r;
    size_t off = 0;
    while (off + 3 <= len) {
        uint8_t t = buf[off];
        uint16_t l = buf[off + 1] | buf[off + 2] << 8;
        if (off + 3 + l > len) break;
        r.tlvs[t].assign(buf + off + 3, buf + off + 3 + l);
        off += 3 + l;
    }
    if (auto* res = r.tlv(0x02); res && res->size() >= 4) {
        r.result = (*res)[0] | (*res)[1] << 8;
        r.error = (*res)[2] | (*res)[3] << 8;
    }
    return r;
}

}  // namespace

void putTlvU8(std::vector<uint8_t>* b, uint8_t type, uint8_t v) {
    b->insert(b->end(), {type, 1, 0, v});
}

void putTlvU16(std::vector<uint8_t>* b, uint8_t type, uint16_t v) {
    b->insert(b->end(), {type, 2, 0, static_cast<uint8_t>(v), static_cast<uint8_t>(v >> 8)});
}

void putTlvU32(std::vector<uint8_t>* b, uint8_t type, uint32_t v) {
    b->insert(b->end(), {type, 4, 0, static_cast<uint8_t>(v), static_cast<uint8_t>(v >> 8),
                         static_cast<uint8_t>(v >> 16), static_cast<uint8_t>(v >> 24)});
}

void putTlvBytes(std::vector<uint8_t>* b, uint8_t type, const void* data, size_t len) {
    if (len > 0xffff) return;
    b->push_back(type);
    b->push_back(len & 0xff);
    b->push_back((len >> 8) & 0xff);
    const auto* p = static_cast<const uint8_t*>(data);
    b->insert(b->end(), p, p + len);
}

void putTlvString(std::vector<uint8_t>* b, uint8_t type, const std::string& v) {
    putTlvBytes(b, type, v.data(), v.size());
}

std::optional<QmiResponse> qmiRequest(uint32_t service, uint16_t msg,
                                       const std::vector<uint8_t>& tlvs, int timeoutMs) {
    int64_t deadline = nowMs() + timeoutMs;
    auto addr = lookup(service, deadline);
    if (!addr) return std::nullopt;
    android::base::unique_fd fd(socket(AF_QIPCRTR, SOCK_DGRAM | SOCK_CLOEXEC, 0));
    if (fd < 0) return std::nullopt;
    uint16_t txn = nextTxn();
    writeFrame(fd, *addr, txn, msg, tlvs);

    std::vector<uint8_t> buf(65536);
    while (waitReadable(fd, deadline)) {
        sockaddr_qrtr from{};
        socklen_t fl = sizeof(from);
        ssize_t n = recvfrom(fd, buf.data(), buf.size(), 0, reinterpret_cast<sockaddr*>(&from),
                             &fl);
        if (n < 7 || from.sq_node != addr->sq_node || from.sq_port != addr->sq_port) continue;
        uint16_t rtxn = buf[1] | buf[2] << 8, rmsg = buf[3] | buf[4] << 8,
                 len = buf[5] | buf[6] << 8;
        if (buf[0] != 2 || rtxn != txn || rmsg != msg || 7 + len > n) continue;
        return parseResponse(buf.data() + 7, len);
    }
    LOG(WARNING) << "QMI service " << service << " msg 0x" << std::hex << msg << ": no answer";
    forget(service);
    return std::nullopt;
}

QmiListener::QmiListener(uint32_t service, std::vector<QmiRegistration> registrations,
                         Callback callback)
    : mService(service),
      mRegistrations(std::move(registrations)),
      mCallback(std::move(callback)),
      mThread([this] { run(); }) {}

QmiListener::~QmiListener() {
    mStop = true;
    if (mThread.joinable()) mThread.join();
}

void QmiListener::run() {
    android::base::unique_fd fd(socket(AF_QIPCRTR, SOCK_DGRAM | SOCK_CLOEXEC, 0));
    if (fd < 0) {
        PLOG(ERROR) << "QMI indication socket";
        return;
    }
    std::vector<uint8_t> buf(65536);
    while (!mStop) {
        auto addr = lookup(mService, nowMs() + 2000);
        if (!addr) {
            delayMs(1000);  // modem not up yet (or restarting)
            continue;
        }
        int64_t lastRegistration = 0;
        while (!mStop) {
            if (nowMs() - lastRegistration >= 30000) {
                for (const auto& registration : mRegistrations)
                    writeFrame(fd, *addr, nextTxn(), registration.msg, registration.tlvs);
                lastRegistration = nowMs();
            }
            pollfd p{fd, POLLIN, 0};
            int r = poll(&p, 1, 1000);
            if (r == 0) continue;
            if (r < 0) {
                if (errno == EINTR) continue;
                break;
            }
            sockaddr_qrtr from{};
            socklen_t fl = sizeof(from);
            ssize_t n = recvfrom(fd, buf.data(), buf.size(), 0, reinterpret_cast<sockaddr*>(&from),
                                 &fl);
            if (n < 0 && errno == ECONNREFUSED) break;  // modem restarted
            if (n < 7 || buf[0] != 4 || from.sq_node != addr->sq_node ||
                from.sq_port != addr->sq_port)
                continue;
            uint16_t msg = buf[3] | buf[4] << 8, len = buf[5] | buf[6] << 8;
            if (7 + len > n) continue;
            if (mCallback) mCallback(msg, parseResponse(buf.data() + 7, len));
        }
        forget(mService);
        delayMs(500);
    }
}

}  // namespace axon7m::radio
