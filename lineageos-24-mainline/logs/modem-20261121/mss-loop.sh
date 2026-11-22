#!/system/bin/sh
# modem restart loop: N rounds of stop/start + online, 120 s watch each;
# QRTR name-service trace + dmesg per round in /data/local/tmp/mss/
N=${1:-5}; O=/data/local/tmp/mss; mkdir -p $O; T=/sys/kernel/tracing; R=/sys/class/remoteproc/remoteproc0
for i in $(seq 1 $N); do
  echo 0 > $T/tracing_on; echo > $T/trace; echo 4096 > $T/buffer_size_kb; echo 0 > $T/events/enable
  echo 1 > $T/events/qrtr/enable
  echo stop > $R/state 2>/dev/null; sleep 3
  dmesg -C; echo 1 > $T/tracing_on
  t0=$(cut -d. -f1 /proc/uptime)
  echo start > $R/state
  sleep 8; /vendor/bin/axon7m-modem-online > $O/online-$i.txt 2>&1
  crashed=0
  for s in $(seq 1 112); do
    dmesg | grep -qiE "fatal error|crash|recover" && { crashed=1; break; }
    sleep 1
  done
  t1=$(cut -d. -f1 /proc/uptime)
  echo 0 > $T/tracing_on
  cat $T/trace > $O/trace-$i.txt; dmesg > $O/dmesg-$i.txt
  echo "round $i: crashed=$crashed after $((t1-t0)) s state=$(cat $R/state)" | tee -a $O/summary.txt
  sleep 15
done
