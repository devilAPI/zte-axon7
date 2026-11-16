/*
 * cam2test: camera test through the Android camera service (NDK Camera2):
 *   cam2test list
 *   cam2test ID yuv WIDTH HEIGHT FRAMES OUT.yuv   (repeating YUV_420_888 request, last
 *                                                 frame written as NV12)
 *   cam2test ID jpeg WIDTH HEIGHT OUT.jpg [N]     (N preview-less still captures, default
 *                                                 15 so exposure settles; last one kept)
 * Runs as root (adb shell). Exercises cameraserver -> camera provider ->
 * camera HAL like an app would.
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#include <camera/NdkCameraCaptureSession.h>
#include <camera/NdkCameraDevice.h>
#include <camera/NdkCameraManager.h>
#include <media/NdkImage.h>
#include <media/NdkImageReader.h>
#include <dlfcn.h>

#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <thread>

static std::atomic<int> gFrames{0};
static std::atomic<bool> gSaved{false};
static const char* gOut;
static bool gJpeg;
static int gWanted;

static void saveImage(AImage* img) {
    FILE* f = fopen(gOut, "wb");
    if (!f) return;
    if (gJpeg) {
        uint8_t* d;
        int len;
        AImage_getPlaneData(img, 0, &d, &len);
        fwrite(d, 1, len, f);
        printf("jpeg %d bytes\n", len);
    } else {
        int32_t w, h;
        AImage_getWidth(img, &w);
        AImage_getHeight(img, &h);
        uint8_t *y, *u, *v;
        int ly, lu, lv, sy, su, ps;
        AImage_getPlaneData(img, 0, &y, &ly);
        AImage_getPlaneData(img, 1, &u, &lu);
        AImage_getPlaneData(img, 2, &v, &lv);
        AImage_getPlaneRowStride(img, 0, &sy);
        AImage_getPlaneRowStride(img, 1, &su);
        AImage_getPlanePixelStride(img, 1, &ps);
        for (int r = 0; r < h; r++) fwrite(y + r * sy, 1, w, f);
        for (int r = 0; r < h / 2; r++)
            for (int c = 0; c < w / 2; c++) {
                fputc(u[r * su + c * ps], f);
                fputc(v[r * su + c * ps], f);
            }
        printf("yuv %dx%d (y stride %d, uv stride %d, pixel stride %d) as NV12\n", w, h, sy,
               su, ps);
    }
    fclose(f);
}

static void onImage(void*, AImageReader* reader) {
    AImage* img = nullptr;
    if (AImageReader_acquireLatestImage(reader, &img) != AMEDIA_OK || !img) return;
    int n = ++gFrames;
    if (n >= gWanted && !gSaved.exchange(true)) saveImage(img);
    AImage_delete(img);
}

static void onDisconnected(void*, ACameraDevice*) { fprintf(stderr, "camera disconnected\n"); }
static void onError(void*, ACameraDevice*, int e) { fprintf(stderr, "camera error %d\n", e); }
static void onSessionClosed(void*, ACameraCaptureSession*) {}
static void onSessionReady(void*, ACameraCaptureSession*) {}
static void onSessionActive(void*, ACameraCaptureSession*) {}
static void onCaptureFailed(void*, ACameraCaptureSession*, ACaptureRequest*,
                            ACameraCaptureFailure* f) {
    fprintf(stderr, "capture failed: reason %d frame %lld\n", f->reason, (long long)f->frameNumber);
}

int main(int argc, char** argv) {
    /* the image reader's buffer queue lives here: cameraserver dequeues over binder */
    /* platform API (not in the NDK stubs): look it up at run time */
    if (void* bn = dlopen("libbinder_ndk.so", RTLD_NOW)) {
        auto setMax = reinterpret_cast<bool (*)(uint32_t)>(
                dlsym(bn, "ABinderProcess_setThreadPoolMaxThreadCount"));
        auto start = reinterpret_cast<void (*)()>(dlsym(bn, "ABinderProcess_startThreadPool"));
        if (setMax) setMax(2);
        if (start) start();
        else fprintf(stderr, "no ABinderProcess_startThreadPool\n");
    }
    ACameraManager* mgr = ACameraManager_create();
    ACameraIdList* ids = nullptr;
    if (ACameraManager_getCameraIdList(mgr, &ids) != ACAMERA_OK) {
        fprintf(stderr, "no camera list\n");
        return 1;
    }
    if (argc < 2 || !strcmp(argv[1], "list")) {
        for (int i = 0; i < ids->numCameras; i++) printf("camera %s\n", ids->cameraIds[i]);
        return 0;
    }
    if (argc < 6) return 2;
    const char* id = argv[1];
    gJpeg = !strcmp(argv[2], "jpeg");
    int w = atoi(argv[3]), h = atoi(argv[4]);
    gWanted = gJpeg ? (argc > 6 ? atoi(argv[6]) : 15) : atoi(argv[5]);
    gOut = gJpeg ? argv[5] : argv[6];

    AImageReader* reader = nullptr;
    if (AImageReader_new(w, h, gJpeg ? AIMAGE_FORMAT_JPEG : AIMAGE_FORMAT_YUV_420_888, 4,
                         &reader) != AMEDIA_OK) {
        fprintf(stderr, "image reader failed\n");
        return 1;
    }
    AImageReader_ImageListener l{nullptr, onImage};
    AImageReader_setImageListener(reader, &l);
    ANativeWindow* win = nullptr;
    AImageReader_getWindow(reader, &win);

    ACameraDevice_StateCallbacks dcb{nullptr, onDisconnected, onError};
    ACameraDevice* dev = nullptr;
    camera_status_t st = ACameraManager_openCamera(mgr, id, &dcb, &dev);
    if (st != ACAMERA_OK) {
        fprintf(stderr, "openCamera %s: %d\n", id, st);
        return 1;
    }
    ACaptureSessionOutputContainer* outs = nullptr;
    ACaptureSessionOutputContainer_create(&outs);
    ACaptureSessionOutput* out = nullptr;
    ACaptureSessionOutput_create(win, &out);
    ACaptureSessionOutputContainer_add(outs, out);
    ACameraCaptureSession_stateCallbacks scb{nullptr, onSessionClosed, onSessionReady,
                                             onSessionActive};
    ACameraCaptureSession* sess = nullptr;
    st = ACameraDevice_createCaptureSession(dev, outs, &scb, &sess);
    if (st != ACAMERA_OK) {
        fprintf(stderr, "createCaptureSession: %d\n", st);
        return 1;
    }
    ACaptureRequest* req = nullptr;
    ACameraDevice_createCaptureRequest(dev, gJpeg ? TEMPLATE_STILL_CAPTURE : TEMPLATE_PREVIEW,
                                       &req);
    ACameraOutputTarget* tgt = nullptr;
    ACameraOutputTarget_create(win, &tgt);
    ACaptureRequest_addTarget(req, tgt);
    ACameraCaptureSession_captureCallbacks ccb{};
    ccb.onCaptureFailed = onCaptureFailed;

    auto t0 = std::chrono::steady_clock::now();
    if (gJpeg) {
        /* preview-less captures so auto exposure can move; keep the last */
        for (int i = 0; i < gWanted && st == ACAMERA_OK; i++)
            st = ACameraCaptureSession_capture(sess, &ccb, 1, &req, nullptr);
    } else {
        st = ACameraCaptureSession_setRepeatingRequest(sess, &ccb, 1, &req, nullptr);
    }
    if (st != ACAMERA_OK) fprintf(stderr, "capture request: %d\n", st);
    for (int i = 0; i < 300 && !gSaved; i++) std::this_thread::sleep_for(std::chrono::milliseconds(100));
    double secs = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
    printf("%d frames in %.2f s (%.1f fps)%s\n", gFrames.load(), secs, gFrames / secs,
           gSaved ? "" : " - nothing saved");
    if (!gJpeg) ACameraCaptureSession_stopRepeating(sess);
    ACameraCaptureSession_close(sess);
    ACameraDevice_close(dev);
    AImageReader_delete(reader);
    ACameraManager_delete(mgr);
    return gSaved ? 0 : 1;
}
