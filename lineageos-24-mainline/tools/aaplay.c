/* aaplay: play a sine tone through AAudio (audioserver -> audio HAL -> ALSA)
 * for SECONDS (default 1) at FREQ Hz (default 1000) and AMPLITUDE in dBFS
 * (default -20), then print what the stream reported (underruns, frames).
 * An audible test of the Android playback path: only outside quiet hours.
 * Build:
 *   $NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android35-clang \
 *     -O2 -o aaplay aaplay.c -laaudio -lm */
#include <aaudio/AAudio.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char **argv)
{
	double secs = argc > 1 ? atof(argv[1]) : 1, freq = argc > 2 ? atof(argv[2]) : 1000;
	double db = argc > 3 ? atof(argv[3]) : -20, amp = 32767 * pow(10, db / 20);
	AAudioStreamBuilder *b; AAudioStream *s;
	AAudio_createStreamBuilder(&b);
	AAudioStreamBuilder_setDirection(b, AAUDIO_DIRECTION_OUTPUT);
	AAudioStreamBuilder_setSampleRate(b, 48000);
	AAudioStreamBuilder_setChannelCount(b, 2);
	AAudioStreamBuilder_setFormat(b, AAUDIO_FORMAT_PCM_I16);
	AAudioStreamBuilder_setPerformanceMode(b, AAUDIO_PERFORMANCE_MODE_NONE);
	aaudio_result_t r = AAudioStreamBuilder_openStream(b, &s);
	if (r) { printf("open: %s\n", AAudio_convertResultToText(r)); return 1; }
	int ch = AAudioStream_getChannelCount(s), rate = AAudioStream_getSampleRate(s);
	printf("opened: rate %d ch %d burst %d buffer %d, %.0f Hz %.0f dBFS %.1f s\n", rate, ch,
	       AAudioStream_getFramesPerBurst(s), AAudioStream_getBufferCapacityInFrames(s), freq, db, secs);
	if ((r = AAudioStream_requestStart(s))) { printf("start: %s\n", AAudio_convertResultToText(r)); return 1; }
	short buf[960 * 8];
	long total = 0, want = (long)(rate * secs);
	double ph = 0, step = 2 * M_PI * freq / rate;
	while (total < want) {
		int n = want - total < 960 ? (int)(want - total) : 960;
		for (int i = 0; i < n; i++, ph += step) {
			/* 10 ms fade in and out: no clicks */
			long t = total + i;
			double g = t < rate / 100 ? (double)t / (rate / 100) : want - t < rate / 100 ? (double)(want - t) / (rate / 100) : 1;
			short v = (short)(amp * g * sin(ph));
			for (int c = 0; c < ch; c++) buf[i * ch + c] = v;
		}
		r = AAudioStream_write(s, buf, n, 2000000000LL);
		if (r < 0) { printf("write: %s\n", AAudio_convertResultToText(r)); break; }
		if (r == 0) { printf("write: timeout\n"); break; }
		total += r;
	}
	printf("frames %ld written, underruns %d\n", total, AAudioStream_getXRunCount(s));
	AAudioStream_requestStop(s); AAudioStream_close(s);
	return 0;
}
