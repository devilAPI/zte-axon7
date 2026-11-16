/*
 * lc-snap: libcamera capture test for the Axon 7 (no Android framework).
 *   lc-snap list
 *   lc-snap CAMERA_INDEX OUT.ppm [WIDTH HEIGHT] [FRAMES]
 * Configures one viewfinder stream (the simple pipeline's software ISP
 * gives RGB), captures FRAMES frames (default 30, so auto exposure can
 * settle) and writes the last one as a binary PPM. Prints the frame rate.
 * Build: NDK clang++ -std=c++20 against libcamera (scripts/libcamera-build.sh).
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#include <libcamera/libcamera.h>

#include <sys/mman.h>
#include <unistd.h>

#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <mutex>

using namespace libcamera;

static std::mutex gLock;
static std::condition_variable gCond;
static int gDone = 0;
static Request* gLast = nullptr;
static std::shared_ptr<Camera> gCam;
static int gWanted = 30;

static void requestComplete(Request* req) {
    if (req->status() == Request::RequestCancelled) return;
    std::lock_guard l(gLock);
    gDone++;
    gLast = req;
    if (gDone < gWanted) {
        req->reuse(Request::ReuseBuffers);
        gCam->queueRequest(req);
    }
    gCond.notify_all();
}

int main(int argc, char** argv) {
    auto cm = std::make_unique<CameraManager>();
    if (cm->start()) {
        fprintf(stderr, "camera manager failed\n");
        return 1;
    }
    auto cams = cm->cameras();
    if (argc < 2 || !strcmp(argv[1], "list")) {
        for (size_t i = 0; i < cams.size(); i++)
            printf("%zu: %s\n", i, cams[i]->id().c_str());
        return 0;
    }
    size_t idx = atoi(argv[1]);
    if (idx >= cams.size() || argc < 3) {
        fprintf(stderr, "no camera %zu (%zu found)\n", idx, cams.size());
        return 1;
    }
    gCam = cams[idx];
    if (gCam->acquire()) return 1;
    auto config = gCam->generateConfiguration({StreamRole::Viewfinder});
    StreamConfiguration& sc = config->at(0);
    printf("default: %s\n", sc.toString().c_str());
    if (argc >= 5) sc.size = Size(atoi(argv[3]), atoi(argv[4]));
    if (argc >= 6) gWanted = atoi(argv[5]);
    sc.pixelFormat = formats::BGR888;  // PPM byte order R G B
    sc.bufferCount = 4;
    auto st = config->validate();
    printf("validated (%d): %s\n", (int)st, sc.toString().c_str());
    if (st == CameraConfiguration::Invalid || gCam->configure(config.get())) {
        fprintf(stderr, "configure failed\n");
        return 1;
    }
    FrameBufferAllocator alloc(gCam);
    if (alloc.allocate(sc.stream()) < 0) {
        fprintf(stderr, "buffer allocation failed\n");
        return 1;
    }
    std::vector<std::unique_ptr<Request>> reqs;
    for (auto& b : alloc.buffers(sc.stream())) {
        auto r = gCam->createRequest();
        r->addBuffer(sc.stream(), b.get());
        reqs.push_back(std::move(r));
    }
    gCam->requestCompleted.connect(requestComplete);
    auto t0 = std::chrono::steady_clock::now();
    if (gCam->start()) {
        fprintf(stderr, "start failed\n");
        return 1;
    }
    for (auto& r : reqs) gCam->queueRequest(r.get());
    {
        std::unique_lock l(gLock);
        if (!gCond.wait_for(l, std::chrono::seconds(30), [] { return gDone >= gWanted; }))
            fprintf(stderr, "timeout: %d frames\n", gDone);
    }
    double secs = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
    printf("%d frames in %.2f s (%.1f fps)\n", gDone, secs, gDone / secs);
    Request* last;
    {
        std::lock_guard l(gLock);
        last = gLast;
    }
    int rc = 1;
    if (last) {
        FrameBuffer* fb = last->buffers().begin()->second;
        const FrameBuffer::Plane& p = fb->planes()[0];
        size_t len = p.offset + p.length;
        void* m = mmap(nullptr, len, PROT_READ, MAP_SHARED, p.fd.get(), 0);
        if (m != MAP_FAILED) {
            const uint8_t* d = static_cast<const uint8_t*>(m) + p.offset;
            FILE* f = fopen(argv[2], "wb");
            if (f) {
                fprintf(f, "P6\n%u %u\n255\n", sc.size.width, sc.size.height);
                for (unsigned y = 0; y < sc.size.height; y++)
                    fwrite(d + y * sc.stride, 1, sc.size.width * 3, f);
                fclose(f);
                printf("wrote %s (%ux%u, stride %u)\n", argv[2], sc.size.width, sc.size.height,
                       sc.stride);
                rc = 0;
            }
            munmap(m, len);
        }
    }
    gCam->stop();
    gCam->release();
    gCam.reset();
    cm->stop();
    return rc;
}
