/* sensread: enable each default sensor (accelerometer, gyroscope,
 * magnetometer, light, proximity) through the NDK sensor API
 * (sensorservice -> sensors HAL -> IIO -> SLPI) for SECONDS (default 2)
 * and print the event count, the rate and the first and last values.
 * Build:
 *   $NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android35-clang \
 *     -O2 -o sensread sensread.c -landroid -llog */
#include <android/looper.h>
#include <android/sensor.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static long long now_ns(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec * 1000000000LL + ts.tv_nsec;
}

int main(int argc, char **argv)
{
	double secs = argc > 1 ? atof(argv[1]) : 2;
	static const int types[] = { ASENSOR_TYPE_ACCELEROMETER, ASENSOR_TYPE_GYROSCOPE,
				     ASENSOR_TYPE_MAGNETIC_FIELD, ASENSOR_TYPE_LIGHT,
				     ASENSOR_TYPE_PROXIMITY };
	ASensorManager *sm = ASensorManager_getInstanceForPackage("sensread");
	ALooper *looper = ALooper_prepare(ALOOPER_PREPARE_ALLOW_NON_CALLBACKS);
	for (unsigned i = 0; i < sizeof(types) / sizeof(types[0]); i++) {
		const ASensor *s = ASensorManager_getDefaultSensor(sm, types[i]);
		if (!s) { printf("type %d: no sensor\n", types[i]); continue; }
		ASensorEventQueue *q = ASensorManager_createEventQueue(sm, looper, 1, NULL, NULL);
		int period = ASensor_getMinDelay(s) > 20000 ? ASensor_getMinDelay(s) : 20000;
		if (ASensorEventQueue_registerSensor(q, s, period, 0) < 0) {
			printf("%s: register failed\n", ASensor_getName(s));
			ASensorManager_destroyEventQueue(sm, q);
			continue;
		}
		long n = 0;
		ASensorEvent first = {0}, last = {0}, ev;
		long long end = now_ns() + (long long)(secs * 1e9);
		while (now_ns() < end) {
			ALooper_pollOnce(100, NULL, NULL, NULL);
			while (ASensorEventQueue_getEvents(q, &ev, 1) > 0) {
				if (!n) first = ev;
				last = ev;
				n++;
			}
		}
		double span = n > 1 ? (last.timestamp - first.timestamp) / 1e9 : 0;
		printf("%-24s %4ld events %6.1f Hz  first %9.3f %9.3f %9.3f  last %9.3f %9.3f %9.3f\n",
		       ASensor_getName(s), n, span > 0 ? (n - 1) / span : 0,
		       first.data[0], first.data[1], first.data[2], last.data[0], last.data[1], last.data[2]);
		ASensorEventQueue_disableSensor(q, s);
		ASensorManager_destroyEventQueue(sm, q);
	}
	return 0;
}
