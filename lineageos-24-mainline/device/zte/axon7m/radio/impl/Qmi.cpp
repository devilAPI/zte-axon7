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
#include <cstring>
#include <mutex>

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

}  // namespace

void putTlvU8(std::vector<uint8_t>* b, uint8_t type, uint8_t v) {
    b->insert(b->end(), {type, 1, 0, v});
}

std::optional<QmiResponse> qmiRequest(uint32_t service, uint16_t msg,
                                      const std::vector<uint8_t>& tlvs, int timeoutMs) {
    int64_t deadline = nowMs() + timeoutMs;
    auto addr = lookup(service, deadline);
    if (!addr) return std::nullopt;
    android::base::unique_fd fd(socket(AF_QIPCRTR, SOCK_DGRAM | SOCK_CLOEXEC, 0));
    if (fd < 0) return std::nullopt;
    uint16_t txn = gTxn++;
    if (txn == 0) txn = gTxn++;
    std::vector<uint8_t> b = {0, static_cast<uint8_t>(txn), static_cast<uint8_t>(txn >> 8),
                              static_cast<uint8_t>(msg), static_cast<uint8_t>(msg >> 8),
                              static_cast<uint8_t>(tlvs.size()),
                              static_cast<uint8_t>(tlvs.size() >> 8)};
    b.insert(b.end(), tlvs.begin(), tlvs.end());
    if (sendto(fd, b.data(), b.size(), 0, reinterpret_cast<const sockaddr*>(&*addr),
               sizeof(*addr)) < 0) {
        PLOG(WARNING) << "QMI service " << service << " msg 0x" << std::hex << msg;
        forget(service);  // modem restarted: look the service up again next time
        return std::nullopt;
    }
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
        QmiResponse r;
        size_t off = 7, end = 7 + len;
        while (off + 3 <= end) {
            uint8_t t = buf[off];
            uint16_t l = buf[off + 1] | buf[off + 2] << 8;
            if (off + 3 + l > end) break;
            r.tlvs[t].assign(buf.begin() + off + 3, buf.begin() + off + 3 + l);
            off += 3 + l;
        }
        if (auto* res = r.tlv(0x02); res && res->size() >= 4) {
            r.result = (*res)[0] | (*res)[1] << 8;
            r.error = (*res)[2] | (*res)[3] << 8;
        }
        return r;
    }
    LOG(WARNING) << "QMI service " << service << " msg 0x" << std::hex << msg << ": no answer";
    forget(service);
    return std::nullopt;
}

}  // namespace axon7m::radio
