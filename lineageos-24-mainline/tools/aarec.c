/* aarec: record SECONDS (default 1) from the default input through AAudio
 * (audioserver -> audio HAL -> ALSA) and print the level per channel: an
 * unattended check of the Android capture path (recording only). Build:
 *   $NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android35-clang \
 *     -O2 -o aarec aarec.c -laaudio -lm */
#include <aaudio/AAudio.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char **argv)
{
	int secs = argc > 1 ? atoi(argv[1]) : 1;
	AAudioStreamBuilder *b; AAudioStream *s;
	AAudio_createStreamBuilder(&b);
	AAudioStreamBuilder_setDirection(b, AAUDIO_DIRECTION_INPUT);
	AAudioStreamBuilder_setSampleRate(b, 48000);
	AAudioStreamBuilder_setChannelCount(b, 2);
	AAudioStreamBuilder_setFormat(b, AAUDIO_FORMAT_PCM_I16);
	AAudioStreamBuilder_setPerformanceMode(b, AAUDIO_PERFORMANCE_MODE_NONE);
	aaudio_result_t r = AAudioStreamBuilder_openStream(b, &s);
	if (r) { printf("open: %s\n", AAudio_convertResultToText(r)); return 1; }
	printf("opened: rate %d ch %d burst %d buffer %d\n", AAudioStream_getSampleRate(s),
	       AAudioStream_getChannelCount(s), AAudioStream_getFramesPerBurst(s), AAudioStream_getBufferCapacityInFrames(s));
	if ((r = AAudioStream_requestStart(s))) { printf("start: %s\n", AAudio_convertResultToText(r)); return 1; }
	int ch = AAudioStream_getChannelCount(s), total = 0, want = 48000 * secs;
	short buf[960 * 8]; double sum[8] = {0}; int peak[8] = {0};
	while (total < want) {
		r = AAudioStream_read(s, buf, 960, 2000000000LL);
		if (r < 0) { printf("read: %s\n", AAudio_convertResultToText(r)); break; }
		if (r == 0) { printf("read: timeout\n"); break; }
		for (int i = 0; i < r * ch; i++) { int c = i % ch, v = abs(buf[i]); sum[c] += (double)v * v; if (v > peak[c]) peak[c] = v; }
		total += r;
	}
	for (int c = 0; c < ch && total; c++)
		printf("ch %d rms %.1f dBFS %.1f peak %d\n", c, sqrt(sum[c] / total), 20 * log10(sqrt(sum[c] / total) / 32768 + 1e-12), peak[c]);
	printf("frames %d\n", total);
	AAudioStream_requestStop(s); AAudioStream_close(s);
	return 0;
}
