/*
 * lc-manual: libcamera capture with manual exposure and gain (Axon 7).
 *   lc-manual CAMERA_INDEX OUT.ppm WIDTH HEIGHT FRAMES EXPOSURE_US GAIN
 * Uses the simple pipeline's software ISP (BGR888 output), sets AeEnable=false,
 * ExposureTime and AnalogueGain on every request and prints the exposure and
 * gain reported by the camera after each completed frame. Two runs with
 * different settings on a static scene show whether the sensor integrates
 * real light (signal scales with exposure/gain) instead of returning a fixed
 * image. Build like lc-snap against the NDK libcamera in libcamera-build.sh.
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
static int32_t gExposureUs = 20000;
static float gGain = 1.0f;

static void requestComplete(Request* req) {
    if (req->status() == Request::RequestCancelled) return;
    auto exp = req->metadata().get(controls::ExposureTime);
    auto gain = req->metadata().get(controls::AnalogueGain);
    if (gDone < 3 || gDone == gWanted - 1)
        printf("frame %d: exposure %s us, gain %s\n", gDone,
               exp ? std::to_string(*exp).c_str() : "n/a",
               gain ? std::to_string(*gain).c_str() : "n/a");
    std::lock_guard l(gLock);
    gDone++;
    gLast = req;
    if (gDone < gWanted) {
        req->reuse(Request::ReuseBuffers);
        req->controls().set(controls::AeEnable, false);
        req->controls().set(controls::ExposureTime, gExposureUs);
        req->controls().set(controls::AnalogueGain, gGain);
        gCam->queueRequest(req);
    }
    gCond.notify_all();
}

int main(int argc, char** argv) {
    if (argc < 8) {
        fprintf(stderr, "usage: %s ID OUT.ppm W H FRAMES EXPOSURE_US GAIN\n", argv[0]);
        return 2;
    }
    size_t idx = atoi(argv[1]);
    gWanted = atoi(argv[5]);
    gExposureUs = atoi(argv[6]);
    gGain = atof(argv[7]);

    auto cm = std::make_unique<CameraManager>();
    if (cm->start()) {
        fprintf(stderr, "camera manager failed\n");
        return 1;
    }
    auto cams = cm->cameras();
    if (idx >= cams.size()) {
        fprintf(stderr, "no camera %zu (%zu found)\n", idx, cams.size());
        return 1;
    }
    gCam = cams[idx];
    printf("camera %s\n", gCam->id().c_str());
    if (gCam->acquire()) return 1;
    auto config = gCam->generateConfiguration({StreamRole::Viewfinder});
    StreamConfiguration& sc = config->at(0);
    sc.size = Size(atoi(argv[3]), atoi(argv[4]));
    sc.pixelFormat = formats::BGR888;
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
        r->controls().set(controls::AeEnable, false);
        r->controls().set(controls::ExposureTime, gExposureUs);
        r->controls().set(controls::AnalogueGain, gGain);
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
        if (!gCond.wait_for(l, std::chrono::seconds(45), [] { return gDone >= gWanted; }))
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
