#!/usr/bin/env python3
# axon7-nfc-test.py info|up|down|poll|stop [idx]: minimal NFC generic-netlink
# client for the mainline kernel stack (no neard needed). On 7.3.1 the NFC
# netlink commands are not capability-checked, so this works as a normal user.
import socket, struct, sys, os
NETLINK_GENERIC = 16
GENL_ID_CTRL, CTRL_CMD_GETFAMILY, CTRL_ATTR_FAMILY_ID, CTRL_ATTR_FAMILY_NAME = 0x10, 3, 1, 2
NFC_CMD_GET_DEVICE, NFC_CMD_DEV_UP, NFC_CMD_DEV_DOWN, NFC_CMD_START_POLL, NFC_CMD_STOP_POLL = 1, 2, 3, 6, 7
NFC_ATTR_DEVICE_INDEX, NFC_ATTR_DEVICE_NAME, NFC_ATTR_PROTOCOLS, NFC_ATTR_DEVICE_POWERED = 1, 2, 3, 12
NFC_ATTR_IM_PROTOCOLS = 13
NLMSG_ERROR, NLMSG_DONE = 2, 3
s = socket.socket(socket.AF_NETLINK, socket.SOCK_RAW, NETLINK_GENERIC)
s.bind((0, 0))
seq = [1]

def attr(t, data):
    l = 4 + len(data)
    return struct.pack('HH', l, t) + data + b'\0' * ((4 - l % 4) % 4)

def send(fam, cmd, attrs=b'', flags=0x1 | 0x4):
    seq[0] += 1
    body = struct.pack('BBH', cmd, 1, 0) + attrs
    s.send(struct.pack('IHHII', 16 + len(body), fam, flags, seq[0], 0) + body)
    return seq[0]

def recv_msgs(want_seq, dump=False):
    """Collect replies for want_seq; skip stale ACKs from earlier requests.

    For a dump the kernel sends ACK (if requested), the device messages and
    NLMSG_DONE; all of them must be consumed or the next command reads a
    left-over message from the socket.
    """
    out = []
    while True:
        d = s.recv(65536)
        o = 0
        while o + 16 <= len(d):
            l, t, fl, sq, pid = struct.unpack_from('IHHII', d, o)
            if sq != want_seq or l < 16:
                break
            if t == NLMSG_ERROR:
                err = struct.unpack_from('i', d, o + 16)[0]
                if err:
                    raise OSError(-err, os.strerror(-err))
                if not dump:
                    return out
            elif t == NLMSG_DONE:
                return out
            else:
                out.append(d[o + 20:o + l])
            o += (l + 3) & ~3
    return out

def attrs(b):
    r = {}
    o = 0
    while o + 4 <= len(b):
        l, t = struct.unpack_from('HH', b, o)
        r[t & 0x7fff] = b[o + 4:o + l]
        o += (l + 3) & ~3
    return r

family_msg = recv_msgs(send(GENL_ID_CTRL, CTRL_CMD_GETFAMILY,
                            attr(CTRL_ATTR_FAMILY_NAME, b'nfc\0')))[0]
fam = struct.unpack('H', attrs(family_msg)[CTRL_ATTR_FAMILY_ID][:2])[0]
cmd = sys.argv[1]
idx = int(sys.argv[2]) if len(sys.argv) > 2 else 0
dev = attr(NFC_ATTR_DEVICE_INDEX, struct.pack('I', idx))
if cmd == 'info':
    for m in recv_msgs(send(fam, NFC_CMD_GET_DEVICE, flags=0x1 | 0x4 | 0x300), dump=True):
        a = attrs(m)
        print('idx', struct.unpack('I', a[NFC_ATTR_DEVICE_INDEX])[0],
              'name', a[NFC_ATTR_DEVICE_NAME].rstrip(b'\0').decode(),
              'protocols 0x%x' % struct.unpack('I', a[NFC_ATTR_PROTOCOLS])[0],
              'powered', a.get(NFC_ATTR_DEVICE_POWERED, b'\0')[0])
elif cmd == 'up':
    recv_msgs(send(fam, NFC_CMD_DEV_UP, dev)); print('up ok')
elif cmd == 'down':
    recv_msgs(send(fam, NFC_CMD_DEV_DOWN, dev)); print('down ok')
elif cmd == 'poll':  # all initiator protocols the device reports
    protos = 0xfe
    recv_msgs(send(fam, NFC_CMD_START_POLL,
                   dev + attr(NFC_ATTR_IM_PROTOCOLS, struct.pack('I', protos))))
    print('poll started')
elif cmd == 'stop':
    recv_msgs(send(fam, NFC_CMD_STOP_POLL, dev)); print('poll stopped')
else:
    sys.exit('usage: axon7-nfc-test.py info|up|down|poll|stop [idx]')
