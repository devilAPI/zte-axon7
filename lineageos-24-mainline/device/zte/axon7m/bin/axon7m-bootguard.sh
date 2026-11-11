#!/vendor/bin/sh
# Bring-up guard (milestone M1): a boot that hangs before adbd is otherwise only
# recoverable with the buttons. After 4 min without adbd (or 20 min without
# sys.boot_completed): process list and boot properties to the kernel log
# (pstore console, read in TWRP by axon7-los-test.sh), then reboot to recovery.
dump() {
	echo "axon7m-bootguard: $1" > /dev/kmsg
	{ ps -A -o PID,PPID,STAT,WCHAN:24,NAME; getprop | grep -E "init\.svc\.|sys\.boot|ro\.cold|sys\.usb|selinux"; } 2>&1 |
		while IFS= read -r l; do echo "guard: $l" > /dev/kmsg; done
	setprop sys.powerctl reboot,recovery
	sleep 30
	echo b > /proc/sysrq-trigger
}
sleep 240
[ "$(getprop init.svc.adbd)" = running ] || dump "no adbd after 240 s"
sleep 960
[ "$(getprop sys.boot_completed)" = 1 ] || dump "no boot_completed after 1200 s"
