/* planedump: write every DRM plane's scanned-out framebuffer to DIR/planeN.raw
 * (format line in DIR/planeN.txt): what the panel really shows, independent
 * of SurfaceFlinger's screencap. Needs root (GETFB2 handles). Build:
 *   $NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android35-clang \
 *     -O2 -static -o planedump planedump.c
 * Convert: PIL Image.frombuffer("RGBA", (w, h), data, "raw", "RGBA", pitch, 1). */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <drm/drm.h>
#include <drm/drm_mode.h>

int main(int argc, char **argv)
{
	const char *dir = argc > 1 ? argv[1] : "/data/local/tmp";
	int fd = open("/dev/dri/card0", O_RDWR | O_CLOEXEC);
	if (fd < 0) { perror("card0"); return 1; }
	struct drm_set_client_cap cap = { DRM_CLIENT_CAP_UNIVERSAL_PLANES, 1 };
	ioctl(fd, DRM_IOCTL_SET_CLIENT_CAP, &cap);
	struct drm_mode_get_plane_res res = {0};
	if (ioctl(fd, DRM_IOCTL_MODE_GETPLANERESOURCES, &res)) { perror("planeres"); return 1; }
	uint32_t *ids = calloc(res.count_planes, 4);
	res.plane_id_ptr = (uintptr_t)ids;
	ioctl(fd, DRM_IOCTL_MODE_GETPLANERESOURCES, &res);
	for (unsigned i = 0; i < res.count_planes; i++) {
		struct drm_mode_get_plane p = { .plane_id = ids[i] };
		if (ioctl(fd, DRM_IOCTL_MODE_GETPLANE, &p)) continue;
		printf("plane %u crtc %u fb %u\n", ids[i], p.crtc_id, p.fb_id);
		if (!p.fb_id) continue;
		struct drm_mode_fb_cmd2 fb = { .fb_id = p.fb_id };
		if (ioctl(fd, DRM_IOCTL_MODE_GETFB2, &fb)) { perror("getfb2"); continue; }
		printf("  %ux%u fmt %.4s pitch %u off %u mod 0x%llx flags %u handle %u\n", fb.width, fb.height,
		       (char *)&fb.pixel_format, fb.pitches[0], fb.offsets[0], (unsigned long long)fb.modifier[0], fb.flags, fb.handles[0]);
		struct drm_prime_handle ph = { .handle = fb.handles[0], .flags = DRM_CLOEXEC | DRM_RDWR };
		if (ioctl(fd, DRM_IOCTL_PRIME_HANDLE_TO_FD, &ph)) { perror("prime"); continue; }
		size_t len = (size_t)fb.pitches[0] * fb.height + fb.offsets[0];
		void *m = mmap(NULL, len, PROT_READ, MAP_SHARED, ph.fd, 0);
		if (m == MAP_FAILED) { perror("mmap"); close(ph.fd); continue; }
		char path[256];
		snprintf(path, sizeof path, "%s/plane%u.raw", dir, ids[i]);
		FILE *f = fopen(path, "wb");
		if (f) { fwrite(m, 1, len, f); fclose(f); }
		snprintf(path, sizeof path, "%s/plane%u.txt", dir, ids[i]);
		f = fopen(path, "w");
		if (f) { fprintf(f, "%u %u %.4s %u %u 0x%llx\n", fb.width, fb.height, (char *)&fb.pixel_format,
				 fb.pitches[0], fb.offsets[0], (unsigned long long)fb.modifier[0]); fclose(f); }
		munmap(m, len); close(ph.fd);
	}
	return 0;
}
