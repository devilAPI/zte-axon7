/*
 * axon7m-modem-online: switch the Axon 7's modem to operating mode "online"
 * (radios and GPS on) once rmtfs has started it. Port of Nura's axon7-modem
 * (postmarketos/.../device-zte-axon7/axon7-modem, which uses qmicli) to plain
 * QMI over QRTR sockets, the framing of axon7-gps.
 *
 * QMI DMS (service 2): GET_OPERATING_MODE 0x002D -> TLV 0x01 u8 mode
 * (0 online, 1 low power, 2 factory test, 3 offline, 4 resetting, 5 shutting
 * down, 6 persistent low power, 7 mode-only low power), SET_OPERATING_MODE
 * 0x002E with TLV 0x01 u8 0. Result TLV 0x02: u16 result, u16 error.
 *
 * Runs until the modem has been online for STABLE seconds (it falls back to
 * low power while it boots) or LIMIT seconds have passed. Logs to the kernel
 * log (tag axon7m-modem). Exit 0 when online, 1 otherwise.
 */
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>
#include <linux/qrtr.h>

#ifndef AF_QIPCRTR
#define AF_QIPCRTR 42
#endif

#define DMS_SERVICE 2
#define DMS_GET_OPERATING_MODE 0x002D
#define DMS_SET_OPERATING_MODE 0x002E
#define LIMIT 420
#define STABLE 30

static void klog(const char *fmt, ...)
{
	char buf[256];
	va_list ap;
	int fd, n;

	va_start(ap, fmt);
	n = vsnprintf(buf, sizeof(buf) - 1, fmt, ap);
	va_end(ap);
	if (n < 0)
		return;
	if (n > (int)sizeof(buf) - 2)
		n = sizeof(buf) - 2;
	buf[n++] = '\n';
	fprintf(stderr, "axon7m-modem: %.*s", n, buf);
	fd = open("/dev/kmsg", O_WRONLY | O_CLOEXEC);
	if (fd >= 0) {
		dprintf(fd, "axon7m-modem: %.*s", n, buf);
		close(fd);
	}
}

static int now(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_BOOTTIME, &ts);
	return (int)ts.tv_sec;
}

/* QRTR name service lookup (control port), as libqrtr and axon7-gps do */
static int lookup(int service, struct sockaddr_qrtr *out)
{
	struct sockaddr_qrtr local, ctl;
	struct qrtr_ctrl_pkt pkt;
	socklen_t sl = sizeof(local);
	struct timeval tv = { 1, 0 };
	int fd, found = 0, end;

	fd = socket(AF_QIPCRTR, SOCK_DGRAM | SOCK_CLOEXEC, 0);
	if (fd < 0)
		return -errno;
	setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
	if (getsockname(fd, (struct sockaddr *)&local, &sl) < 0) {
		close(fd);
		return -errno;
	}
	memset(&pkt, 0, sizeof(pkt));
	pkt.cmd = QRTR_TYPE_NEW_LOOKUP;
	pkt.server.service = service;
	memset(&ctl, 0, sizeof(ctl));
	ctl.sq_family = AF_QIPCRTR;
	ctl.sq_node = local.sq_node;
	ctl.sq_port = QRTR_PORT_CTRL;
	if (sendto(fd, &pkt, sizeof(pkt), 0, (struct sockaddr *)&ctl, sizeof(ctl)) < 0) {
		close(fd);
		return -errno;
	}
	end = now() + 3;
	while (now() < end && !found) {
		ssize_t n = recv(fd, &pkt, sizeof(pkt), 0);

		if (n < (ssize_t)sizeof(pkt))
			continue;
		/* the list ends with an empty NEW_SERVER */
		if (pkt.cmd == QRTR_TYPE_NEW_SERVER && pkt.server.service == (uint32_t)service &&
		    pkt.server.port) {
			memset(out, 0, sizeof(*out));
			out->sq_family = AF_QIPCRTR;
			out->sq_node = pkt.server.node;
			out->sq_port = pkt.server.port;
			found = 1;
		} else if (pkt.cmd == QRTR_TYPE_NEW_SERVER && !pkt.server.service) {
			break;
		}
	}
	close(fd);
	return found ? 0 : -ENOENT;
}

/*
 * One QMI request, wait for its response. Returns the response payload
 * length (TLVs) in resp, or a negative errno.
 */
static int qmi_call(const struct sockaddr_qrtr *dms, uint16_t msg, const uint8_t *tlvs,
		    uint16_t tlvlen, uint8_t *resp, size_t resplen)
{
	static uint16_t txn;
	uint8_t req[64], buf[512];
	struct timeval tv = { 2, 0 };
	int fd, end, ret = -ETIMEDOUT;

	if (tlvlen > sizeof(req) - 7)
		return -EINVAL;
	fd = socket(AF_QIPCRTR, SOCK_DGRAM | SOCK_CLOEXEC, 0);
	if (fd < 0)
		return -errno;
	setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
	txn++;
	req[0] = 0;	/* request */
	req[1] = txn & 0xff; req[2] = txn >> 8;
	req[3] = msg & 0xff; req[4] = msg >> 8;
	req[5] = tlvlen & 0xff; req[6] = tlvlen >> 8;
	memcpy(req + 7, tlvs, tlvlen);
	if (sendto(fd, req, 7 + tlvlen, 0, (const struct sockaddr *)dms, sizeof(*dms)) < 0) {
		ret = -errno;
		close(fd);
		return ret;
	}
	end = now() + 5;
	while (now() < end) {
		ssize_t n = recv(fd, buf, sizeof(buf), 0);
		uint16_t rtxn, rmsg, rlen;

		if (n < 7)
			continue;
		rtxn = buf[1] | buf[2] << 8;
		rmsg = buf[3] | buf[4] << 8;
		rlen = buf[5] | buf[6] << 8;
		if (buf[0] != 2 || rtxn != txn || rmsg != msg)	/* 2: response */
			continue;
		if (rlen > n - 7)
			rlen = n - 7;
		if (rlen > resplen)
			rlen = resplen;
		memcpy(resp, buf + 7, rlen);
		ret = rlen;
		break;
	}
	close(fd);
	return ret;
}

/* value of TLV t (and its length), NULL if absent */
static const uint8_t *tlv_get(const uint8_t *p, int len, uint8_t t, uint16_t *tl)
{
	int i = 0;

	while (i + 3 <= len) {
		uint16_t l = p[i + 1] | p[i + 2] << 8;

		if (i + 3 + l > len)
			break;
		if (p[i] == t) {
			*tl = l;
			return p + i + 3;
		}
		i += 3 + l;
	}
	return NULL;
}

/* QMI result TLV 0x02: 0 on success, else the QMI error code (or -1) */
static int qmi_result(const uint8_t *p, int len)
{
	uint16_t l;
	const uint8_t *r = tlv_get(p, len, 0x02, &l);

	if (!r || l < 4)
		return -1;
	return (r[0] | r[1] << 8) ? (r[2] | r[3] << 8) : 0;
}

static int get_mode(const struct sockaddr_qrtr *dms)
{
	uint8_t resp[64];
	uint16_t l;
	const uint8_t *m;
	int n = qmi_call(dms, DMS_GET_OPERATING_MODE, NULL, 0, resp, sizeof(resp));

	if (n < 0 || qmi_result(resp, n))
		return -1;
	m = tlv_get(resp, n, 0x01, &l);
	return m && l >= 1 ? m[0] : -1;
}

static int set_online(const struct sockaddr_qrtr *dms)
{
	static const uint8_t tlv[] = { 0x01, 0x01, 0x00, 0x00 };	/* mode 0: online */
	uint8_t resp[64];
	int n = qmi_call(dms, DMS_SET_OPERATING_MODE, tlv, sizeof(tlv), resp, sizeof(resp));

	return n < 0 ? n : qmi_result(resp, n);
}

int main(void)
{
	struct sockaddr_qrtr dms;
	int start = now(), online_since = -1, switched = 0, last = -2, have = 0;

	while (now() - start < LIMIT) {
		int m;

		if (!have) {
			if (lookup(DMS_SERVICE, &dms) == 0) {
				have = 1;
				klog("DMS at %u:%u after %d s", dms.sq_node, dms.sq_port, now() - start);
			} else {
				sleep(3);
				continue;
			}
		}
		m = get_mode(&dms);
		if (m != last) {
			klog("operating mode %d", m);
			last = m;
		}
		if (m < 0) {
			have = 0;	/* modem restarted or gone: look the service up again */
			online_since = -1;
		} else if (m == 0) {
			if (online_since < 0)
				online_since = now();
			if (now() - online_since >= STABLE) {
				klog("modem online (switched %d time(s))", switched);
				return 0;
			}
		} else {
			int r;

			online_since = -1;
			r = set_online(&dms);
			switched++;
			if (r)
				klog("set online: error %d", r);
		}
		sleep(3);
	}
	klog("modem not online after %d s", LIMIT);
	return 1;
}
