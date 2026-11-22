#!/system/bin/sh
# Modem-only restart probe (MODEM remoteproc0 only; never SLPI/ADSP).
# Usage: modem-restart-probe.sh ROUNDS [online|offline]
# Each round: stop/start remoteproc0, optionally set it online like the image
# service does, watch up to 100 s for a fatal error. Logs land in
# /data/local/tmp/modem-agent/ on the phone.
N=${1:-4}
MODE=${2:-online}
O=/data/local/tmp/modem-agent
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
	crashed=0
	for s in $(seq 1 100); do
		if dmesg | grep -q 'fatal error'; then crashed=1; break; fi
		sleep 1
	done
	t1=$(cut -d. -f1 /proc/uptime)
	dmesg > "$O/${MODE}-${i}-dmesg.txt"
	echo "$MODE round $i: crashed=$crashed after $((t1-t0)) s state=$(cat "$R/state")" | tee -a "$O/summary.txt"
	sleep 10
done
