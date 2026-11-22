#!/bin/sh
# Run on the phone (adb shell sh /data/local/tmp/check-snd.sh).
echo "== open test"
for d in /dev/snd/pcmC0D1p /dev/snd/pcmC0D0p; do
	if : <> "$d" 2>/dev/null; then echo "$d: open OK"; else echo "$d: open FAILED ($?)"; fi
done
echo "== fd owners"
for f in /proc/[0-9]*/fd/*; do
	t=$(readlink "$f" 2>/dev/null)
	case "$t" in /dev/snd/*) echo "$f -> $t";; esac
done
echo "== pcm state"
cat /proc/asound/pcm
echo "== audio processes"
ps -A | grep -i audio
echo "== controls"
tinymix -D 0 | grep -E 'Speaker|Receiver|Digital Playback|SLIMBUS_0_RX Audio Mixer MultiMedia2'
