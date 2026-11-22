#!/system/bin/sh
# Modem-only restart probe, fixed-window version (MODEM remoteproc0 only).
# Usage: modem-restart-probe2.sh ROUNDS [online|offline]
N=${1:-3}
MODE=${2:-offline}
O=/data/local/tmp/modem-agent2
mkdir -p "$O"
R=/sys/class/remoteproc/remoteproc0
for i in $(seq 1 "$N"); do
	echo stop > "$R/state" 2>/dev/null
	sleep 4
	dmesg -C
	t0=$(cut -d. -f1 /proc/uptime)
	echo start > "$R/state"
	if [ "$MODE" = online ]; then
		sleep 8
		/vendor/bin/axon7m-modem-online > "$O/${MODE}-${i}-online.txt" 2>&1
	fi
	sleep 75
	t1=$(cut -d. -f1 /proc/uptime)
	dmesg > "$O/${MODE}-${i}-dmesg.txt"
	n=$(dmesg | grep -c 'fatal error')
	echo "$MODE round $i: fatals=$n after $((t1-t0)) s state=$(cat "$R/state")" | tee -a "$O/summary.txt"
	sleep 8
done
