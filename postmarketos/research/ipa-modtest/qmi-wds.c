/* Minimal QMI over QRTR client (kernel wire format: 7-byte header).
 * Usage: qmi-wds NODE PORT CMD [hex-payload]
 * Default: WDS Get Packet Service Status (service on port 41, cmd 0x20). */
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

#define AF_QIPCRTR 42
struct sockaddr_qrtr {
	unsigned short sq_family;
	uint32_t sq_node;
	uint32_t sq_port;
};
struct qmi_header {
	uint8_t type;
	uint16_t txn_id;
	uint16_t msg_id;
	uint16_t msg_len;
} __attribute__((packed));

int main(int argc, char **argv)
{
	unsigned int node = (argc > 1) ? strtoul(argv[1], 0, 0) : 0;
	unsigned int port = (argc > 2) ? strtoul(argv[2], 0, 0) : 41;
	unsigned int cmd = (argc > 3) ? strtoul(argv[3], 0, 0) : 0x20;
	struct sockaddr_qrtr dst = { AF_QIPCRTR, node, port }, src;
	struct timeval tv = { 6, 0 };
	unsigned char tx[64], rx[256];
	socklen_t slen = sizeof(src);
	int fd, n, txlen = 7, i;

	if (argc > 4) {
		const char *h = argv[4];
		while (h[0] && h[1] && txlen < (int)sizeof(tx)) {
			char b[3] = { h[0], h[1], 0 };
			tx[txlen++] = (unsigned char)strtoul(b, 0, 16);
			h += 2;
		}
	}
	fd = socket(AF_QIPCRTR, SOCK_DGRAM, 0);
	if (fd < 0) { perror("socket"); return 1; }
	if (setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv)) < 0) {
		perror("setsockopt"); return 1;
	}
	memset(tx, 0, sizeof(tx));
	tx[0] = 0;                        /* QMI_REQUEST */
	tx[1] = 0x01; tx[2] = 0x00;       /* transaction id 1 */
	tx[3] = cmd & 0xff; tx[4] = cmd >> 8;
	tx[5] = (txlen - 7) & 0xff; tx[6] = (txlen - 7) >> 8;
	n = sendto(fd, tx, txlen, 0, (struct sockaddr *)&dst, sizeof(dst));
	printf("send node=%u port=%u cmd=0x%04x n=%d\n", node, port, cmd, n);
	if (n != txlen) return 1;
	n = 0;
	for (int attempt = 0; attempt < 12; attempt++) {
		memset(rx, 0, sizeof(rx));
		int r = recvfrom(fd, rx, sizeof(rx), 0, (struct sockaddr *)&src, &slen);
		if (r < 7) { printf("recv[%d] r=%d errno=%d\n", attempt, r, errno); continue; }
		struct qmi_header *hh = (struct qmi_header *)rx;
		printf("recv[%d] from %u:%u n=%d type=0x%02x txn=0x%04x cmd=0x%04x len=%u\n",
		       attempt, src.sq_node, src.sq_port, r, hh->type, hh->txn_id,
		       hh->msg_id, hh->msg_len);
		if (hh->type == 2 && hh->txn_id == 1 && hh->msg_id == cmd) { n = r; break; }
	}
	printf("matching response n=%d", n);
	if (n >= 7) {
		struct qmi_header *h = (struct qmi_header *)rx;
		printf(" type=0x%02x txn=0x%04x cmd=0x%04x len=%u",
		       h->type, h->txn_id, h->msg_id, h->msg_len);
		printf(" raw=");
		for (i = 0; i < n && i < 24; i++) printf("%02x", rx[i]);
		/* TLVs: type, u16 len, value; first result TLV has type 2 */
		for (i = 7; i + 3 <= n; ) {
			unsigned int tl = rx[i + 1] | (rx[i + 2] << 8);
			printf(" tlv%02x=", rx[i]);
			for (unsigned int j = 0; j < tl && i + 3 + j < n; j++)
				printf("%02x", rx[i + 3 + j]);
			i += 3 + tl;
		}
	}
	printf("\n");
	close(fd);
	return (n >= 7 && rx[0] == 2) ? 0 : 1;
}
