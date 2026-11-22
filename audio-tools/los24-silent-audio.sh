#!/bin/bash
# Silent repeated-playback test on LineageOS 24 (main phone).
# All amplifiers stay off; the WAV is digital silence; volume is 0.
# Usage: los24-silent-audio.sh LOG Pause1 Pause2 ...
set -u
SERIAL=${SERIAL:-7e15695a}
export ANDROID_SERIAL=$SERIAL
LOG=$1; shift
PAUSES=("$@")
: > "$LOG"
log() { printf '%s %s\n' "$(date +%FT%T)" "$*" | tee -a "$LOG"; }
ash() { timeout 25 adb shell "$1" 2>&1 | tr -d '\r'; }
ampstate() { ash "tinymix -D 0 | grep -E '(Bottom Speaker Switch|Top Speaker Switch|Speaker Top Receiver Switch|Digital Playback Volume)'"; }
check_amps() {
	local s; s=$(ampstate)
	log "AMP CHECK: $(echo "$s" | tr '\n' ';')"
	if echo "$s" | grep -E '(Bottom Speaker Switch|Top Speaker Switch|Speaker Top Receiver Switch)[[:space:]]+On' | grep -q .; then
		log "ABORT: an amplifier switch is On"
		return 1
	fi
	if ! echo "$s" | grep -q 'Digital Playback Volume.*0 0'; then
		log "ABORT: playback volume is not 0"
		return 1
	fi
	return 0
}
timeout 20 adb root >/dev/null 2>&1; sleep 2
log "serial=$SERIAL uname=$(ash 'uname -v') battery=$(ash 'cat /sys/class/power_supply/qcom-battery/capacity')%"
ash 'id' | grep -q root || { log "ERROR: adb root required"; ash 'id' >> "$LOG"; exit 1; }
log "card: $(ash 'cat /proc/asound/cards' | tr '\n' ';')"
log "tools: $(ash 'ls -l /data/local/tmp/tinyplay /data/local/tmp/z.wav' | tr '\n' ';')"
for c in 'Digital Playback Volume 0 0' 'Bottom Speaker Switch 0' 'Top Speaker Switch 0' 'Speaker Top Receiver Switch 0'; do
	log "SET: $c -> $(ash "tinymix -D 0 $c")"
done
ash 'dmesg -c' >/dev/null
log "=== start: ${#PAUSES[@]} playbacks ==="
fail=0
for i in "${!PAUSES[@]}"; do
	check_amps || { fail=1; break; }
	# Route: same path the muted LOS build uses, MultiMedia2 -> SLIMBUS_0_RX.
	ash 'tinymix -D 0 "SLIMBUS_0_RX Audio Mixer MultiMedia2" 1' >/dev/null
	timeout 25 adb shell 'timeout 10 /data/local/tmp/tinyplay /data/local/tmp/z.wav -D 0 -d 1' > /tmp/audio-play.out 2>&1
	rc=$?
	out=$(tr -d '\r' < /tmp/audio-play.out)
	state=$(ash 'cat /proc/asound/pcm | grep -i Multimedia')
	amps=$(ampstate | grep -E 'Switch' | tr '\n' ';')
	log "play $((i+1)): rc=$rc out=$(echo "$out" | tr '\n' '|')"
	log "play $((i+1)): pcm=$(echo "$state" | tr '\n' ';') amps=$amps"
	err=$(ash 'dmesg | grep -iE "q6asm|q6adm|q6afe|q6routing|apr|slimbus|ngd|ak4961|stream reg|memory_map|CMD_|Error queuing|I2S|codec" | tail -12' | tr '\n' '|')
	log "play $((i+1)): dmesg=$err"
	[ $rc -eq 0 ] || fail=1
	echo "$out" | grep -qiE 'error|fail' && fail=1
	echo "$err" | grep -qiE 'timeout|error|fail|oops|warn' && fail=$((fail+1))
	ash 'tinymix -D 0 "SLIMBUS_0_RX Audio Mixer MultiMedia2" 0' >/dev/null
	p=${PAUSES[$i]}
	log "--- pause ${i+1}: ${p}s ---"
	sleep "$p"
done
ash 'tinymix -D 0 "SLIMBUS_0_RX Audio Mixer MultiMedia2" 0' >/dev/null
ash 'tinymix -D 0 "Digital Playback Volume" 255 255' >> "$LOG" 2>&1
log "DONE fail=$fail card=$(ash 'cat /proc/asound/cards' | tr '\n' ';')"
log "battery end=$(ash 'cat /sys/class/power_supply/qcom-battery/capacity')%"
ash 'svc power stayon false' >/dev/null
exit 0
