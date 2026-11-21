/*
 * qmi-raw: one QMI request over QRTR, response TLVs as hex; decodes UIM
 * GET_CARD_STATUS (0x2f), UIM GET_SLOT_STATUS (0x47) and DMS UIM state
 * (0x25). Usage: qmi-raw SERVICE MSGID [TLV bytes in hex]
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

static int lookup(unsigned service, struct sockaddr_qrtr *out)
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
	pkt.server.service = service;
	ctl.sq_family = AF_QIPCRTR;
	ctl.sq_node = local.sq_node;
	ctl.sq_port = QRTR_PORT_CTRL;
	if (sendto(fd, &pkt, sizeof(pkt), 0, (struct sockaddr *)&ctl, sizeof(ctl)) < 0)
		return -1;
	/* the list ends with an empty NEW_SERVER */
	while (recv(fd, &pkt, sizeof(pkt), 0) >= (ssize_t)sizeof(pkt)) {
		if (pkt.cmd != QRTR_TYPE_NEW_SERVER || !pkt.server.service)
			break;
		if (pkt.server.service == service && !found) {
			out->sq_family = AF_QIPCRTR;
			out->sq_node = pkt.server.node;
			out->sq_port = pkt.server.port;
			found = 1;
		}
	}
	close(fd);
	return found ? 0 : -1;
}

static void card_status(const uint8_t *v, int len)
{
	static const char *cs[] = { "absent", "present", "error" };
	static const char *as[] = { "unknown", "detected", "PIN1 required", "PUK1 required",
				    "check personalization", "PIN1 blocked", "illegal", "ready" };
	static const char *at[] = { "unknown", "SIM", "USIM", "RUIM", "CSIM", "ISIM" };
	int i = 8, cards, c, a;

	if (len < 9)
		return;
	printf("primary GW app: slot %u app %u (0xffff: none)\n", v[1], v[0]);
	cards = v[i++];
	for (c = 0; c < cards && i + 6 <= len; c++) {
		int apps = v[i + 5];

		printf("slot %d: card %s", c + 1, v[i] < 3 ? cs[v[i]] : "?");
		if (v[i] == 2)
			printf(" (error code %u)", v[i + 4]);
		printf(", %d app(s)\n", apps);
		i += 6;
		for (a = 0; a < apps && i + 7 <= len; a++) {
			int aidlen = v[i + 6], p = i + 7 + aidlen;

			if (p + 7 > len)
				return;
			printf("  app %d: %s, %s, PIN1 state %u (0 unknown, 1 enabled not verified, "
			       "2 verified, 3 disabled, 4 blocked, 5 permanently blocked), "
			       "%u PIN / %u PUK tries left\n", a, v[i] < 6 ? at[v[i]] : "?",
			       v[i + 1] < 8 ? as[v[i + 1]] : "?", v[p + 1], v[p + 2], v[p + 3]);
			i = p + 7;
		}
	}
}

static uint32_t le32(const uint8_t *p)
{
	return p[0] | p[1] << 8 | p[2] << 16 | (uint32_t)p[3] << 24;
}

/* qril_uim.qmi: physical_slot_state{u32 card_state, u32 slot_state,
 * u8 logical_slot, u8 *iccid(u8)}; card state: 0 unknown, 1 absent, 2
 * present. physical_slot_info{u32 card_protocol, u8 valid_apps,
 * u8 *atr(u8)[32], u8 is_euicc}. */
static void slot_status(const uint8_t *v, int len)
{
	static const char *cs[] = { "unknown", "absent", "present" };
	int i = 0, n = len ? v[i++] : 0, s;

	printf("slot state: %d physical slot(s)\n", n);
	for (s = 0; s < n && i + 10 <= len; s++) {
		int iccid_len = v[i + 9], k;

		if (i + 10 + iccid_len > len)
			return;
		printf("  physical slot %d: card %s (%u), slot state %u, logical slot %u, ICCID",
		       s + 1, le32(v + i) < 3 ? cs[le32(v + i)] : "?", le32(v + i),
		       le32(v + i + 4), v[i + 8]);
		for (k = 0; k < iccid_len; k++)
			printf("%c", v[i + 10 + k] ? v[i + 10 + k] : '?');
		printf("\n");
		i += 10 + iccid_len;
	}
}

static void slot_info(const uint8_t *v, int len)
{
	int i = 0, n = len ? v[i++] : 0, s;

	printf("slot info: %d physical slot(s)\n", n);
	for (s = 0; s < n && i + 7 <= len; s++) {
		int atr_len = v[i + 5], k;

		if (i + 6 + atr_len + 1 > len)
			return;
		printf("  physical slot %d: card protocol %u, valid apps 0x%02x, ATR(%d):",
		       s + 1, le32(v + i), v[i + 4], atr_len);
		for (k = 0; k < atr_len; k++)
			printf(" %02x", v[i + 6 + k]);
		printf(", eUICC %u\n", v[i + 6 + atr_len]);
		i += 6 + atr_len + 1;
	}
}

int main(int argc, char **argv)
{
	struct sockaddr_qrtr svc = { 0 };
	struct timeval tv = { 5, 0 };
	uint8_t req[512], buf[4096];
	unsigned service, msg;
	int fd, tlvlen = 0, i, len;
	ssize_t n;

	if (argc < 3) {
		fprintf(stderr, "usage: %s SERVICE MSGID [TLV hex bytes]\n", argv[0]);
		return 2;
	}
	service = strtoul(argv[1], NULL, 0);
	msg = strtoul(argv[2], NULL, 0);
	for (i = 3; i < argc && tlvlen < (int)sizeof(req) - 7; i++)
		req[7 + tlvlen++] = strtoul(argv[i], NULL, 16);
	if (lookup(service, &svc)) {
		fprintf(stderr, "service %u not found on QRTR (modem up?)\n", service);
		return 1;
	}
	printf("service %u at %u:%u\n", service, svc.sq_node, svc.sq_port);
	fd = socket(AF_QIPCRTR, SOCK_DGRAM, 0);
	setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
	req[0] = 0;				/* 0 request, 2 response, 4 indication */
	req[1] = 1; req[2] = 0;			/* transaction id */
	req[3] = msg & 0xff; req[4] = msg >> 8;
	req[5] = tlvlen & 0xff; req[6] = tlvlen >> 8;
	if (sendto(fd, req, 7 + tlvlen, 0, (struct sockaddr *)&svc, sizeof(svc)) < 0) {
		perror("sendto");
		return 1;
	}
	do {
		n = recv(fd, buf, sizeof(buf), 0);
		if (n < 7) {
			fprintf(stderr, "no response\n");
			return 1;
		}
	} while (buf[0] != 2 || (unsigned)(buf[3] | buf[4] << 8) != msg);
	len = buf[5] | buf[6] << 8;
	if (len > n - 7)
		len = n - 7;
	for (i = 7; i + 3 <= 7 + len; ) {
		int t = buf[i], l = buf[i + 1] | buf[i + 2] << 8, k;

		if (i + 3 + l > 7 + len)
			break;
		printf("TLV 0x%02x len %d:", t, l);
		for (k = 0; k < l; k++)
			printf(" %02x", buf[i + 3 + k]);
		printf("\n");
		if (t == 0x02 && l >= 4)
			printf("result %u, QMI error %u\n", buf[i + 3] | buf[i + 4] << 8,
			       buf[i + 5] | buf[i + 6] << 8);
		if (service == 11 && msg == 0x2f && t == 0x10)
			card_status(buf + i + 3, l);
		if (service == 11 && msg == 0x47 && t == 0x10)
			slot_status(buf + i + 3, l);
		if (service == 11 && msg == 0x47 && t == 0x11)
			slot_info(buf + i + 3, l);
		i += 3 + l;
	}
	return 0;
}
