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
# Off-mode charging (the phone was empty and came up on USB power): no adbd
# runs there by design. Not a hang: charge to 25 %, then start normally (a
# warm reboot boots Android, not the charger). 2026-11-19: an empty battery
# came back in charger mode, the guard sent it to TWRP.
if [ "$(getprop ro.bootmode)" = charger ]; then
	cap() { for c in /sys/class/power_supply/*/capacity; do [ "$(cat ${c%/capacity}/type 2>/dev/null)" = Battery ] && cat $c && return; done; echo 0; }
	echo "axon7m-bootguard: charger mode, waiting for 25 %" > /dev/kmsg
	while [ "$(cap)" -lt 25 ]; do sleep 60; done
	echo "axon7m-bootguard: charger mode, battery $(cap) %: rebooting to Android" > /dev/kmsg
	setprop sys.powerctl reboot
	sleep 30
	echo b > /proc/sysrq-trigger
fi
sleep 240
[ "$(getprop init.svc.adbd)" = running ] || dump "no adbd after 240 s"
sleep 960
[ "$(getprop sys.boot_completed)" = 1 ] || dump "no boot_completed after 1200 s"
