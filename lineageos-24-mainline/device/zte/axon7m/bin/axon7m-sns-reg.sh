#!/vendor/bin/sh
# Sensor registry server for the SLPI (sensor DSP), as Nura's axon7-sns-reg:
# the SLPI asks for its registry before it offers the Sensor Manager. The
# registry comes from the phone's own calibrated /persist/sensors/sns.reg.
log() { echo "axon7m-sns-reg: $*" > /dev/kmsg; }
out=/data/vendor/sensors/registry.conf
src=/mnt/vendor/persist/sensors/sns.reg
mkdir -p /data/vendor/sensors
if [ ! -s $out ]; then
	[ -s $src ] || { log "no $src"; exit 1; }
	/vendor/bin/sns-reg-generator $src > $out.new && mv $out.new $out ||
		{ log "generator failed"; exit 1; }
	log "$(grep -c '^[0-9]' $out) keys from $src"
fi
exec /vendor/bin/sns-reg $out
