#!/system/bin/sh
# Test: give rmtfs a PRIVATE, writable EFS shadow in /data (never the phone's
# modemst1/2/fsg/fsc partitions), then restart ONLY the modem remoteproc.
O=/data/local/tmp/modem-efs-shadow
D=/data/vendor/axon7m-efs
mkdir -p "$O" "$D"
R=/sys/class/remoteproc/remoteproc0
kill $(pgrep -x rmtfs) 2>/dev/null
stop rmtfs 2>/dev/null
sleep 4
for pair in "modem_fs1 modemst1 4096" "modem_fs2 modemst2 4096" \
            "modem_fsg fsg 4096" "modem_fsc fsc 8"; do
	set -- $pair
	if [ ! -f "$D/$1" ]; then
		dd if=/dev/block/by-name/$2 of="$D/$1" bs=512 count=$3 2>/dev/null
	fi
	chmod 660 "$D/$1"
done
ls -l "$D" > "$O/files.txt"
nohup /vendor/bin/rmtfs -o "$D" -v > "$O/rmtfs.log" 2>&1 </dev/null &
sleep 3
echo "rmtfs=$(pgrep -x rmtfs)"
for i in 1 2 3; do
	echo stop > "$R/state" 2>/dev/null
	sleep 4
	dmesg -C
	t0=$(cut -d. -f1 /proc/uptime)
	echo start > "$R/state"
	sleep 70
	dmesg > "$O/dmesg-$i.txt"
	echo "round $i: fatals=$(dmesg | grep -c 'fatal error') after $(( $(cut -d. -f1 /proc/uptime) - t0 ))s"
	sleep 8
done
ls -l "$D" > "$O/files-after.txt"
# restore the image's rmtfs service, leave the modem running
kill -9 $(pgrep -x rmtfs) 2>/dev/null
sleep 1
start rmtfs
sleep 3
echo "restore: rmtfs=$(pgrep -x rmtfs) modem=$(cat $R/state)"
