#!/bin/bash
# Final silent test on the main phone (LOS 24): 10 repeated 1 s playbacks
# with pauses 1-60 s, then playbacks after an ADSP restart.  Amplifiers are
# verified off before every playback, volume 0, WAV is digital silence.
set -u
export ANDROID_SERIAL=7e15695a
LOG=${1:?usage: $0 LOG}
: > "$LOG"
log() { printf '%s %s\n' "$(date +%FT%T)" "$*" | tee -a "$LOG"; }
ash() { timeout 30 adb shell "$1" 2>&1 | tr -d '\r'; }
WAV=/data/local/tmp/z.wav
PAUSES="1 2 3 5 10 20 30 60 5 1"

ampstate() { ash "tinymix -D 0 | grep -E '(Bottom Speaker Switch|Top Speaker Switch|Speaker Top Receiver Switch|Digital Playback Volume)'"; }
ampsoff() {
	for a in 'Bottom Speaker Switch' 'Top Speaker Switch' 'Speaker Top Receiver Switch'; do
		ash "tinymix -D 0 \"$a\" 0" >/dev/null
	done
	ash 'tinymix -D 0 "Digital Playback Volume" 0 0' >/dev/null
}
amps_off() { ! ampstate | grep -E 'Speaker Top Receiver Switch[[:space:]]+On'; }
route() { ash "tinymix -D 0 'SLIMBUS_0_RX Audio Mixer MultiMedia2' $1" >/dev/null; }
qd() { ash 'dmesg | grep -iE "q6asm|q6adm|q6afe|q6routing|apr|slim|timeout|timed out|Error queuing|CMD " | tail -12' | tr '\n' '|'; }
play() { # tag
	local tag=$1 out rc
	amps_off || { log "$tag: ABORT amplifier is on"; return 1; }
	route 1
	out=$(ash "timeout 12 /data/local/tmp/tinyplay $WAV -D 0 -d 1")
	rc=$?
	route 0
	log "$tag: rc=$rc out=$(echo "$out" | tr '\n' '|') amps=$(ampstate | tr '\n' ';')"
	log "$tag: pcm=$(ash 'cat /proc/asound/pcm' | tr '\n' ';') status=$(ash 'cat /proc/asound/card0/pcm1p/sub0/status 2>&1' | tr '\n' ';')"
	log "$tag: dmesg=$(qd)"
	return $rc
}

timeout 25 adb root >/dev/null 2>&1; sleep 2
log "id=$(ash id | cut -c1-24) battery=$(ash 'cat /sys/class/power_supply/qcom-battery/capacity')%"
log "uname=$(ash 'uname -v') card=$(ash 'cat /proc/asound/cards' | tr '\n' ';')"
log "rproc: $(ash 'for r in /sys/class/remoteproc/remoteproc*; do echo -n "$(cat $r/name)=$(cat $r/state) "; done')"
ash 'svc power stayon true' >/dev/null
ampsoff
log "amps before: $(ampstate | tr '\n' ';')"

# Is the PCM free while Android audio runs?
open=$(ash ': <> /dev/snd/pcmC0D1p 2>/dev/null && echo OK || echo BUSY')
log "pcmC0D1p open with audioserver running: $open"
if [ "$open" = BUSY ]; then
	log "stopping audioserver so tinyplay can have the PCM (test harness only)"
	ash 'stop audioserver' >/dev/null; sleep 2
fi

log "=== 10 repeated playbacks ==="
fail=0
n=0
for p in $PAUSES; do
	n=$((n + 1))
	play "play $n" || fail=$((fail + 1))
	log "--- pause ${p}s ---"
	sleep "$p"
done
log "repeated: $n plays, failures=$fail"

# --- ADSP restart ---
R=$(ash 'for r in /sys/class/remoteproc/remoteproc*; do [ "$(cat $r/name 2>/dev/null)" = adsp ] && echo $r; done' | head -1)
log "ADSP $R state=$(ash "cat $R/state")"
ash 'dmesg -c' >/dev/null
t0=$(date +%s)
out=$(ash "timeout 20 sh -c 'echo stop > $R/state'; echo rc=\$?; cat $R/state")
t1=$(date +%s)
log "ADSP stop after $((t1-t0)) s: $(echo "$out" | tr '\n' ';')"
if [ "$(ash "cat $R/state")" != offline ]; then
	log "stop did not complete (card open?); closing audioserver fds"
	ash 'stop audioserver' >/dev/null
	sleep 5
	log "state now: $(ash "cat $R/state")"
	[ "$(ash "cat $R/state")" = offline ] || ash "echo stop > $R/state"
	sleep 3
	log "state after fds closed: $(ash "cat $R/state")"
fi
log "stop dmesg: $(qd)"
log "start: $(ash "echo start > $R/state; echo rc=\$?")"
for i in $(seq 1 20); do
	card=$(ash 'cat /proc/asound/cards')
	echo "$card" | grep -q 'ZTE Axon 7' && break
	sleep 2
done
log "card after restart: $(ash 'cat /proc/asound/cards' | tr '\n' ';') state=$(ash "cat $R/state")"
ampsoff
play "after restart 1"
sleep 20
ampsoff
play "after restart 2 (+20s)"

log "=== restore ==="
route 0
ash 'tinymix -D 0 "Digital Playback Volume" 255 255' >/dev/null
ash 'start audioserver' >/dev/null; sleep 3
log "audioserver=$(ash 'getprop init.svc.audioserver') hal=$(ash 'getprop init.svc.vendor.audio-hal-aidl')"
log "final card=$(ash 'cat /proc/asound/cards' | tr '\n' ';') battery=$(ash 'cat /sys/class/power_supply/qcom-battery/capacity')% adb=$(timeout 10 adb get-state 2>&1)"
ash 'svc power stayon false' >/dev/null
log "=== done failures=$fail"
exit 0
