#!/vendor/bin/sh
# The SLPI asks sns-reg for its registry while it boots, long before Android
# starts sns-reg (post-fs-data). Without an answer it offers no sensors: if
# no qcom-smgr IIO device shows up, restart the SLPI once now that sns-reg
# runs (the remedy that also brings back a silent ADSP, see PLAN.md).
log() { echo "axon7m-slpi-kick: $*" > /dev/kmsg; }
have() { grep -qs qcom-smgr-accel /sys/bus/iio/devices/iio:device*/name; }
i=0
while [ $i -lt 30 ]; do have && { log "sensors up after ${i} s"; exit 0; }; sleep 1; i=$((i + 1)); done
for r in /sys/class/remoteproc/remoteproc*; do
	case "$(cat $r/name 2>/dev/null)" in
	*slpi*)
		log "no sensors after ${i} s: restarting $(cat $r/name)"
		echo stop > $r/state; sleep 1; echo start > $r/state
		;;
	esac
done
i=0
while [ $i -lt 30 ]; do have && { log "sensors up ${i} s after the SLPI restart"; exit 0; }; sleep 1; i=$((i + 1)); done
log "still no sensors"
