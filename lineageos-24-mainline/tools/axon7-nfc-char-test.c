/*
 * Small root-only test client for the gated PN5xx raw NFC char driver.
 *
 * Build (on root@compiler):
 *   NDK=/srv/los24/tools/android-ndk-r30/toolchains/llvm/prebuilt/linux-x86_64/bin
 *   $NDK/aarch64-linux-android30-clang -static -O2 -Wall -o axon7-nfc-char-test \
 *       lineageos-24-mainline/tools/axon7-nfc-char-test.c
 *
 * Run on the main phone under LineageOS 24 with a kernel booted with
 * pn5xx_raw=1 (and adb root):
 *   adb push axon7-nfc-char-test /data/local/tmp/
 *   adb shell /data/local/tmp/axon7-nfc-char-test /dev/nq-nci
 *
 * This only sends NCI_CORE_RESET / NCI_CORE_INIT and dumps the replies.
 * No payment, no eSE, no tag and no RF field is used.
 */
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#define PN544_MAGIC 0xE9
#define PN5XX_SET_PWR _IOW(PN544_MAGIC, 0x01, unsigned int)
#define P61_GET_PWR_STATUS _IOR(PN544_MAGIC, 0x03, unsigned int)

static volatile sig_atomic_t timed_out;

static void on_alarm(int sig)
{
	(void)sig;
	timed_out = 1;
}

static void dump(const char *tag, const unsigned char *buf, ssize_t len)
{
	ssize_t i;

	printf("%s (%zd):", tag, len);
	for (i = 0; i < len; i++)
		printf(" %02x", buf[i]);
	printf("\n");
	fflush(stdout);
}

/* The driver's read() waits for the IRQ; alarm() bounds a wedged controller. */
static ssize_t read_frame(int fd, unsigned char *buf, size_t size, int seconds)
{
	ssize_t n;

	timed_out = 0;
	alarm(seconds);
	n = read(fd, buf, size);
	alarm(0);
	if (n < 0 && timed_out) {
		printf("read: timed out after %d s\n", seconds);
		return -ETIMEDOUT;
	}
	return n;
}

int main(int argc, char **argv)
{
	const char *node = argc > 1 ? argv[1] : "/dev/nq-nci";
	const unsigned char reset[] = { 0x20, 0x00, 0x01, 0x00 };
	const unsigned char init[] = { 0x20, 0x01, 0x00 };
	unsigned char buf[512];
	unsigned int pwr = 99;
	int fd, ok = 1;
	ssize_t n;

	signal(SIGALRM, on_alarm);
	printf("node=%s\n", node);
	fd = open(node, O_RDWR);
	if (fd < 0) {
		perror("open");
		return 1;
	}

	if (ioctl(fd, P61_GET_PWR_STATUS, &pwr) < 0)
		perror("P61_GET_PWR_STATUS (optional)");
	else
		printf("P61_GET_PWR_STATUS: 0x%x\n", pwr);

	/* Power mode 1 = NCI operation (VEN high, FW download GPIO low). */
	if (ioctl(fd, PN5XX_SET_PWR, 1) < 0) {
		perror("PN5XX_SET_PWR(1)");
		close(fd);
		return 1;
	}
	printf("PN5XX_SET_PWR(1): ok\n");

	n = write(fd, reset, sizeof(reset));
	printf("NCI_CORE_RESET cmd: wrote %zd/%zu\n", n, sizeof(reset));
	if (n == (ssize_t)sizeof(reset)) {
		n = read_frame(fd, buf, sizeof(buf), 5);
		if (n > 0) {
			dump("NCI_CORE_RESET rsp", buf, n);
			if (n >= 5 && buf[0] == 0x40 && buf[1] == 0x00)
				printf("nci_ver=0x%02x config_status=0x%02x\n",
				       buf[3], buf[4]);
			else
				ok = 0;
		} else {
			ok = 0;
		}
	} else {
		ok = 0;
	}

	n = write(fd, init, sizeof(init));
	printf("NCI_CORE_INIT cmd: wrote %zd/%zu\n", n, sizeof(init));
	if (n == (ssize_t)sizeof(init)) {
		n = read_frame(fd, buf, sizeof(buf), 5);
		if (n > 0) {
			dump("NCI_CORE_INIT rsp", buf, n);
			if (n >= 6 && buf[0] == 0x40 && buf[1] == 0x01)
				printf("status=0x%02x:nci_ver=0x%02x\n",
				       buf[3], buf[4]);
			else
				ok = 0;
		} else {
			ok = 0;
		}
	} else {
		ok = 0;
	}

	if (ioctl(fd, PN5XX_SET_PWR, 0) < 0)
		perror("PN5XX_SET_PWR(0)");
	else
		printf("PN5XX_SET_PWR(0): ok\n");
	close(fd);
	printf("RESULT: %s\n", ok ? "PASS" : "FAIL");
	return ok ? 0 : 1;
}
