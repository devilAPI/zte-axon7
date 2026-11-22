#!/system/bin/sh
# Restart rmtfs (read-only, no -s) with timestamped verbose logging, then
# start ONLY the modem remoteproc by hand. Never touches SLPI/ADSP.
O=/data/local/tmp/modem-rmtfs-trace
mkdir -p "$O"
R=/sys/class/remoteproc/remoteproc0
stop rmtfs
sleep 5
rm -f "$O/rmtfs-ts.log"
setsid /system/bin/sh -c '/vendor/bin/rmtfs -o /dev/block/by-name -P -r -v 2>&1 | while IFS= read -r l; do echo "$(cut -d. -f1 /proc/uptime) $l"; done' >"$O/rmtfs-ts.log" 2>&1 </dev/null &
sleep 3
dmesg -C
t0=$(cut -d. -f1 /proc/uptime)
echo start > "$R/state"
sleep 100
dmesg > "$O/dmesg.txt"
echo "uptime start=$t0 end=$(cut -d. -f1 /proc/uptime) state=$(cat "$R/state") fatals=$(dmesg | grep -c 'fatal error')"
# do NOT stop the modem: leave it running; restore the vendor service
kill -9 $(pgrep -x rmtfs) 2>/dev/null
sleep 1
start rmtfs
sleep 3
echo "after restore: rmtfs=$(pgrep -x rmtfs) modem=$(cat "$R/state")"
