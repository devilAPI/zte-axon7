#!/axon7/bin/busybox sh
# M0b front end: runs before Android's init (kernel cmdline rdinit=/axon7/init),
# packed by make-m0b-recovery.sh as a second cpio after the recovery ramdisk.
#
# Gives the same bring-up access as Nura's test initramfs, independent of
# whether Android's recovery ever brings up adb:
#   - USB network (NCM + ACM gadget "axon7fe", 18d1:d001), 172.16.42.1,
#     DHCP for the host, telnet on port 23 (busybox shell, no password)
#   - the APSS watchdog held by busybox `watchdog` (60 s): if userspace
#     freezes, the phone resets warm and the test shim sends it to TWRP with
#     this boot's kernel log in /sys/fs/pstore/console-ramoops-0
#   - "axon7-fe: alive <uptime>" in the kernel log every 10 s
# then exec's Android's /init (first stage, recovery mode). Busybox lives in
# /axon7/bin only; the Android root stays as built (plus /lib for musl).
#
# Kernel cmdline knobs: axon7.hold=N waits N s (or until /axon7/run/go
# exists) before starting Android; axon7.noandroid stays in busybox.
# adb instead of telnet afterwards: /axon7/adb-handover (frees the UDC).
# Read-only towards the phone's storage: mounts nothing from UFS or SD.

B=/axon7/bin
/axon7/bin/busybox --install -s $B
ln -sf /axon7/bin/busybox-extras $B/telnetd
ln -sf /axon7/bin/busybox-extras $B/udhcpd
export PATH=$B:/system/bin
R=/axon7/run

mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
mkdir -p /dev/pts
mount -t devpts devpts /dev/pts
mount -t configfs configfs /sys/kernel/config

log() {
	echo "axon7-fe: $*" > /dev/kmsg
}

log "front end started, kernel $(uname -r), cmdline: $(cat /proc/cmdline)"

if [ -c /dev/watchdog0 ]; then
	watchdog -T 60 -t 10 /dev/watchdog0 && log "watchdog0 held by busybox (60 s)"
else
	log "no /dev/watchdog0"
fi

( while true; do
	echo "axon7-fe: alive $(cut -d' ' -f1 /proc/uptime 2>/dev/null)" > /dev/kmsg 2>/dev/null
	sleep 10
done ) &

G=/sys/kernel/config/usb_gadget/axon7fe
setup_gadget() {
	mkdir -p $G || return 1
	echo 0x18D1 > $G/idVendor
	echo 0xD001 > $G/idProduct
	mkdir -p $G/strings/0x409
	echo "ZTE" > $G/strings/0x409/manufacturer
	echo "Axon 7 LineageOS 24 M0b" > $G/strings/0x409/product
	echo "axon7-m0b" > $G/strings/0x409/serialnumber
	mkdir -p $G/functions/ncm.usb0 $G/functions/acm.usb0
	mkdir -p $G/configs/c.1/strings/0x409
	echo "NCM + ACM" > $G/configs/c.1/strings/0x409/configuration
	echo 500 > $G/configs/c.1/MaxPower
	ln -s $G/functions/ncm.usb0 $G/configs/c.1/
	ln -s $G/functions/acm.usb0 $G/configs/c.1/
	i=0
	while [ -z "$(ls /sys/class/udc 2>/dev/null)" ] && [ $i -lt 30 ]; do
		sleep 1
		i=$((i + 1))
	done
	UDC=$(ls /sys/class/udc | head -n1)
	[ -n "$UDC" ] || { log "no UDC"; return 1; }
	echo "$UDC" > $G/UDC
	log "gadget bound to $UDC"
}

setup_network() {
	IF=$(cat $G/functions/ncm.usb0/ifname 2>/dev/null)
	[ -n "$IF" ] || IF=usb0
	ip link set lo up
	ip addr add 172.16.42.1/24 dev "$IF"
	ip link set "$IF" up
	cat > $R/udhcpd.conf <<-EOF
	start 172.16.42.2
	end 172.16.42.2
	interface $IF
	option subnet 255.255.255.0
	lease_file $R/udhcpd.leases
	EOF
	touch $R/udhcpd.leases
	udhcpd $R/udhcpd.conf
	telnetd -b 172.16.42.1:23 -l $B/sh
	log "network up on $IF: telnet 172.16.42.1"
}

mkdir -p $R
setup_gadget && setup_network

cat > /axon7/adb-handover <<EOF
#!$B/sh
# give the UDC to Android's recovery gadget (g1, adbd): telnet ends here
echo "" > /config/usb_gadget/axon7fe/UDC
/system/bin/setprop sys.usb.config none
sleep 2
/system/bin/setprop sys.usb.config adb
EOF
chmod 0755 /axon7/adb-handover

hold=$(sed -n 's/.*axon7\.hold=\([0-9]*\).*/\1/p' /proc/cmdline)
if [ -n "$hold" ]; then
	log "holding up to $hold s (touch $R/go to continue)"
	i=0
	while [ $i -lt "$hold" ] && [ ! -e $R/go ]; do
		sleep 1
		i=$((i + 1))
	done
fi
if grep -q "axon7\.noandroid" /proc/cmdline; then
	log "axon7.noandroid: staying in busybox"
	while true; do sleep 3600; done
fi

# Android's first stage mounts its own /dev, /proc, /sys, configfs (/config):
# hand over a root without ours (open files and the gadget stay)
log "exec Android init (/init -> $(readlink /init))"
umount -l /sys/kernel/config /dev/pts /dev /sys /proc 2>/dev/null
exec /init
