/*
 * qmi-failure: ask a subsystem's SSCTL QMI service for its failure reason.
 *
 * Usage: qmi-failure [INSTANCE]   (default 18 = the modem on the Axon 7)
 * The response's TLV 0x10 is the modem's own text, e.g. from SMEM.
 * SPDX-License-Identifier: Apache-2.0
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>
#include <linux/qrtr.h>

#ifndef AF_QIPCRTR
#define AF_QIPCRTR 42
#endif
#define SSCTL_SERVICE 43
#define SSCTL_GET_FAILURE_REASON 0x22

static int lookup(unsigned instance, struct sockaddr_qrtr *out)
{
	struct sockaddr_qrtr local, ctl = { 0 };
	struct qrtr_ctrl_pkt pkt = { 0 };
	socklen_t sl = sizeof(local);
	struct timeval tv = { 2, 0 };
	int fd = socket(AF_QIPCRTR, SOCK_DGRAM, 0), found = 0;

	if (fd < 0 || getsockname(fd, (struct sockaddr *)&local, &sl) < 0)
		return -1;
	setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
	pkt.cmd = QRTR_TYPE_NEW_LOOKUP;
	pkt.server.service = SSCTL_SERVICE;
	ctl.sq_family = AF_QIPCRTR;
	ctl.sq_node = local.sq_node;
	ctl.sq_port = QRTR_PORT_CTRL;
	if (sendto(fd, &pkt, sizeof(pkt), 0, (struct sockaddr *)&ctl, sizeof(ctl)) < 0)
		return -1;
	while (recv(fd, &pkt, sizeof(pkt), 0) >= (ssize_t)sizeof(pkt)) {
		if (pkt.cmd != QRTR_TYPE_NEW_SERVER || !pkt.server.service)
			break;
		fprintf(stderr, "candidate service %u instance %u node %u port %u\n",
			pkt.server.service, pkt.server.instance,
			pkt.server.node, pkt.server.port);
		if (pkt.server.service == SSCTL_SERVICE &&
		    (pkt.server.instance >> 8) == instance && !found) {
			out->sq_family = AF_QIPCRTR;
			out->sq_node = pkt.server.node;
			out->sq_port = pkt.server.port;
			found = 1;
		}
	}
	close(fd);
	return found ? 0 : -1;
}

int main(int argc, char **argv)
{
	struct sockaddr_qrtr svc = { 0 };
	struct timeval tv = { 3, 0 };
	uint8_t req[7] = { 0, 1, 0, SSCTL_GET_FAILURE_REASON, 0, 0, 0 };
	uint8_t buf[4096];
	unsigned instance = argc > 1 ? strtoul(argv[1], NULL, 0) : 18;
	ssize_t n;
	int fd, len, i;

	if (lookup(instance, &svc)) {
		fprintf(stderr, "SSCTL instance %u not on QRTR\n", instance);
		return 1;
	}
	printf("SSCTL %u at %u:%u\n", instance, svc.sq_node, svc.sq_port);
	fd = socket(AF_QIPCRTR, SOCK_DGRAM, 0);
	setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
	if (sendto(fd, req, sizeof(req), 0, (struct sockaddr *)&svc, sizeof(svc)) < 0) {
		perror("sendto");
		return 1;
	}
	do {
		n = recv(fd, buf, sizeof(buf), 0);
		if (n < 7) {
			fprintf(stderr, "no response\n");
			return 1;
		}
	} while (buf[0] != 2 || (buf[3] | buf[4] << 8) != SSCTL_GET_FAILURE_REASON);
	len = buf[5] | buf[6] << 8;
	if (len > n - 7)
		len = n - 7;
	for (i = 7; i + 3 <= 7 + len;) {
		int t = buf[i], l = buf[i + 1] | buf[i + 2] << 8, k;

		if (i + 3 + l > 7 + len)
			break;
		printf("TLV 0x%02x len %d:", t, l);
		for (k = 0; k < l; k++)
			printf(" %02x", buf[i + 3 + k]);
		printf("\n");
		if (t == 0x02 && l >= 4)
			printf("  result %u, QMI error %u\n", buf[i + 3] | buf[i + 4] << 8,
			       buf[i + 5] | buf[i + 6] << 8);
		if (t == 0x10 && l >= 4)
			printf("  reason: %.*s\n", l - 4, (char *)buf + i + 7);
		i += 3 + l;
	}
	return 0;
}
