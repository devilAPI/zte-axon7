// SPDX-License-Identifier: GPL-2.0-only
/*
 * axon7-nfc-netlink.c - minimal generic-netlink client for the kernel NFC stack.
 *
 * Usage: axon7-nfc-netlink info|up|down|poll|stop [device index]
 *
 * Built for Android with the NDK for the LineageOS 24 test (the Nura
 * equivalent is postmarketos/tools/axon7-nfc-test.py). No neard needed:
 * the tool only sends NCI commands to the kernel's nfc0 device and checks
 * that the kernel acknowledges them.
 */

#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <linux/netlink.h>
#include <linux/genetlink.h>

#define NETLINK_GENERIC 16

/* linux/nfc.h (uapi) values, kept here so the NDK sysroot is enough */
#define NFC_CMD_GET_DEVICE 1
#define NFC_CMD_DEV_UP 2
#define NFC_CMD_DEV_DOWN 3
#define NFC_CMD_START_POLL 6
#define NFC_CMD_STOP_POLL 7
#define NFC_ATTR_DEVICE_INDEX 1
#define NFC_ATTR_DEVICE_NAME 2
#define NFC_ATTR_PROTOCOLS 3
#define NFC_ATTR_POWERED 12
#define NFC_ATTR_IM_PROTOCOLS 13

static int fd;
static uint16_t family;
static uint32_t seq;

static uint16_t attr_len(size_t payload)
{
	return (uint16_t)((4 + payload + 3) & ~3);
}

/* Append a netlink attribute (type, length, payload, padding). */
static void put_attr(char *buf, size_t *pos, uint16_t type,
		     const void *payload, size_t len)
{
	struct nlattr a = { .nla_len = attr_len(len), .nla_type = type };

	memcpy(buf + *pos, &a, sizeof(a));
	memcpy(buf + *pos + sizeof(a), payload, len);
	memset(buf + *pos + sizeof(a) + len, 0, a.nla_len - sizeof(a) - len);
	*pos += a.nla_len;
}

/* Send a request and wait for the netlink ACK (error 0 = success). */
static int request(uint8_t cmd, const char *attrs, size_t attr_len_total)
{
	char buf[4096];
	struct nlmsghdr *nh = (struct nlmsghdr *)buf;
	struct genlmsghdr *gh = (struct genlmsghdr *)(nh + 1);
	size_t body = sizeof(*gh) + attr_len_total;
	int ret = 0;

	memset(buf, 0, sizeof(buf));
	nh->nlmsg_len = NLMSG_LENGTH(body);
	nh->nlmsg_type = family;
	nh->nlmsg_flags = NLM_F_REQUEST | NLM_F_ACK;
	nh->nlmsg_seq = ++seq;
	gh->cmd = cmd;
	gh->version = 1;
	if (attr_len_total && attrs)
		memcpy((char *)gh + sizeof(*gh), attrs, attr_len_total);

	if (send(fd, buf, nh->nlmsg_len, 0) < 0) {
		perror("send");
		return -1;
	}

	for (;;) {
		ssize_t n = recv(fd, buf, sizeof(buf), 0);
		size_t off;

		if (n < 0) {
			if (errno == EINTR)
				continue;
			perror("recv");
			return -1;
		}
		for (off = 0; off + sizeof(*nh) <= (size_t)n;
		     off += NLMSG_ALIGN(nh->nlmsg_len)) {
			nh = (struct nlmsghdr *)(buf + off);
			if (nh->nlmsg_len < sizeof(*nh) ||
			    off + nh->nlmsg_len > (size_t)n)
				break;
			if (nh->nlmsg_type == NLMSG_ERROR) {
				struct nlmsgerr *e = (struct nlmsgerr *)(nh + 1);

				if (nh->nlmsg_len < NLMSG_LENGTH(sizeof(*e)))
					continue;
				if (e->error) {
					fprintf(stderr, "cmd %u: %s\n", cmd,
						strerror(-e->error));
					ret = -1;
				}
				return ret;
			}
		}
	}
}

static int resolve_family(void)
{
	char attrs[64], buf[4096];
	size_t pos = 0;
	const char name[] = "nfc";
	struct nlmsghdr *nh;
	ssize_t n;
	size_t off;

	put_attr(attrs, &pos, CTRL_ATTR_FAMILY_NAME, name, sizeof(name));
	family = GENL_ID_CTRL;
	memset(buf, 0, sizeof(buf));
	nh = (struct nlmsghdr *)buf;
	nh->nlmsg_len = NLMSG_LENGTH(sizeof(struct genlmsghdr) + pos);
	nh->nlmsg_type = GENL_ID_CTRL;
	nh->nlmsg_flags = NLM_F_REQUEST | NLM_F_ACK;
	nh->nlmsg_seq = ++seq;
	((struct genlmsghdr *)(nh + 1))->cmd = CTRL_CMD_GETFAMILY;
	((struct genlmsghdr *)(nh + 1))->version = 1;
	memcpy((char *)(nh + 1) + sizeof(struct genlmsghdr), attrs, pos);

	if (send(fd, buf, nh->nlmsg_len, 0) < 0) {
		perror("send");
		return -1;
	}

	n = recv(fd, buf, sizeof(buf), 0);
	if (n <= 0) {
		perror("recv");
		return -1;
	}
	for (off = 0; off + sizeof(*nh) <= (size_t)n;
	     off += NLMSG_ALIGN(nh->nlmsg_len)) {
		struct genlmsghdr *gh;
		struct nlattr *a;
		size_t alen;

		nh = (struct nlmsghdr *)(buf + off);
		if (nh->nlmsg_len < sizeof(*nh) || off + nh->nlmsg_len > (size_t)n)
			break;
		if (nh->nlmsg_type == NLMSG_ERROR)
			continue;
		gh = (struct genlmsghdr *)(nh + 1);
		alen = nh->nlmsg_len - NLMSG_LENGTH(sizeof(*gh));
		for (a = (struct nlattr *)((char *)gh + sizeof(*gh));
		     (char *)a + sizeof(*a) <= (char *)gh + sizeof(*gh) + alen;
		     a = (struct nlattr *)((char *)a + NLMSG_ALIGN(a->nla_len))) {
			if (a->nla_len < sizeof(*a))
				break;
			if (a->nla_type == CTRL_ATTR_FAMILY_ID) {
				uint16_t id;

				memcpy(&id, (char *)a + sizeof(*a), sizeof(id));
				family = id;
				return 0;
			}
		}
	}
	fprintf(stderr, "NFC generic netlink family not found\n");
	return -1;
}

int main(int argc, char **argv)
{
	struct sockaddr_nl addr;
	char attrs[64];
	uint32_t index = 0, protocols;
	size_t pos;
	const char *cmd;

	if (argc < 2 || argc > 3) {
		fprintf(stderr, "usage: %s info|up|down|poll|stop [index]\n", argv[0]);
		return 2;
	}
	cmd = argv[1];
	if (argc == 3)
		index = (uint32_t)strtoul(argv[2], NULL, 0);

	memset(&addr, 0, sizeof(addr));
	addr.nl_family = AF_NETLINK;
	fd = socket(AF_NETLINK, SOCK_RAW, NETLINK_GENERIC);
	if (fd < 0 || bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
		perror("netlink socket");
		return 1;
	}
	if (resolve_family())
		return 1;

	pos = 0;
	put_attr(attrs, &pos, NFC_ATTR_DEVICE_INDEX, &index, sizeof(index));
	if (!strcmp(cmd, "info")) {
		/* GET_DEVICE is a dump: the ACK itself is enough for a probe. */
		if (request(NFC_CMD_GET_DEVICE, attrs, pos))
			return 1;
		printf("nfc%u: GET_DEVICE ok (family %u)\n", index, family);
		return 0;
	}
	if (!strcmp(cmd, "up")) {
		if (request(NFC_CMD_DEV_UP, attrs, pos))
			return 1;
		printf("nfc%u: DEV_UP ok\n", index);
		return 0;
	}
	if (!strcmp(cmd, "down")) {
		if (request(NFC_CMD_DEV_DOWN, attrs, pos))
			return 1;
		printf("nfc%u: DEV_DOWN ok\n", index);
		return 0;
	}
	if (!strcmp(cmd, "stop")) {
		if (request(NFC_CMD_STOP_POLL, attrs, pos))
			return 1;
		printf("nfc%u: STOP_POLL ok\n", index);
		return 0;
	}
	if (!strcmp(cmd, "poll")) {
		protocols = 0xfe; /* all initiator protocols, as in the Nura test */
		put_attr(attrs, &pos, NFC_ATTR_IM_PROTOCOLS, &protocols,
			 sizeof(protocols));
		if (request(NFC_CMD_START_POLL, attrs, pos))
			return 1;
		printf("nfc%u: START_POLL ok (protocols 0x%x)\n", index, protocols);
		return 0;
	}
	fprintf(stderr, "unknown command %s\n", cmd);
	return 2;
}
