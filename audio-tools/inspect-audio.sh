#!/bin/bash
# Read-only audio/APR state inspection on the main phone (run under phone lock).
export ANDROID_SERIAL=${SERIAL:-7e15695a}
LOG=$1
: > "$LOG"
log() { printf '%s %s\n' "$(date +%FT%T)" "$*" | tee -a "$LOG"; }
a() { timeout 25 adb shell "$1" 2>&1 | tr -d '\r'; }
timeout 20 adb root >/dev/null 2>&1; sleep 2
log "uptime=$(a 'uptime') battery=$(a 'cat /sys/class/power_supply/qcom-battery/capacity')%"
log "card: $(a 'cat /proc/asound/cards' | tr '\n' ';')"
log "rproc: $(a 'for r in /sys/class/remoteproc/remoteproc*; do echo $(basename $r)=$(cat $r/name 2>/dev/null):$(cat $r/state 2>/dev/null); done' | tr '\n' ' ')"
log "modules:"; a 'cat /proc/modules | grep -E "q6|snd_soc|slim" | head -20' >> "$LOG"
log "q6 platform drivers:"; a 'ls -l /sys/bus/platform/drivers/ | grep -E "q6|dai"' >> "$LOG"
for d in q6asm-dai q6afe-dai q6adm; do
	log "driver $d devices: $(a "ls /sys/bus/platform/drivers/$d 2>/dev/null" | tr '\n' ' ')"
done
log "pcm subdev status: $(a 'cat /proc/asound/card0/pcm1p/sub0/status' | tr '\n' ';')"
log "open check: $(a /data/local/tmp/opencheck /dev/snd/pcmC0D1p /dev/snd/pcmC0D0p /dev/snd/controlC0 | tr '\n' ';')"
log "fd owners:"; a 'for f in /proc/[0-9]*/fd/*; do t=$(readlink $f 2>/dev/null); case $t in /dev/snd/*) echo $f -> $t;; esac; done' >> "$LOG"
log "dmesg q6/APR/slim:"; a 'dmesg | grep -iE "q6|apr|slim|ak4961|pcm|audio|asoc" | tail -60' >> "$LOG"
log "mixer amps: $(a 'tinymix -D 0 | grep -E "Speaker Switch|Receiver Switch" | tr "\n" ";")"
log "routes: $(a 'cat /vendor/etc/audio_routes*.conf 2>/dev/null | grep -iE "speaker|amp" | head -20' | tr '\n' ';')"
