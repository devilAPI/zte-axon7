#!/vendor/bin/sh
# Static ALSA mixer routes for the "ZTE Axon 7" card, from Nura's UCM
# (device-zte-axon7 ucm-zte-axon7-HiFi.conf): the HiFi verb, the Speaker
# device (MultiMedia2 = hw:0,1 -> SLIMbus 0 -> AK4961 -> both TFA9890) and
# the Mic device (AIN1 bottom + AIN2 top -> SLIMbus 0 TX -> MultiMedia1 =
# hw:0,0). The AIDL audio HAL (primary module) opens CARD_0_DEV_1 for the
# speaker and CARD_0_DEV_0 for the built-in mic and sets no routes itself.
# Headphones (AK4490 on QUAT_MI2S) and the earpiece need switching in the
# HAL: milestone M3.
log() { echo "axon7m-audio: $*" > /dev/kmsg; }

# the card comes up after the ADSP firmware has booted
i=0
while [ ! -e /dev/snd/controlC0 ] && [ $i -lt 60 ]; do sleep 1; i=$((i + 1)); done
[ -e /dev/snd/controlC0 ] || { log "no sound card after ${i} s"; exit 1; }

fail=0
m() {
	/vendor/bin/tinymix "$1" "$2" > /dev/null 2>&1 || { fail=$((fail + 1)); log "failed: '$1' = $2"; }
}
# HiFi verb
m 'PORT2 Sync Domain' slimbus
m 'SDTO2 Source Selector' SBI1
m 'Speaker Top Amp Input' Left
m 'Speaker Bottom Amp Input' Left
m 'Speaker Top Receiver Switch' 0
m 'Mic_1L input Selector' AIN1
m 'Mic_1R input Selector' AIN2
m 'SBO1L Source Selector' ADC1
m 'CP1 Clock Mode' 500kHz
m 'MIC Gain 1L' 5
m 'MIC Gain 1R' 5
# Speaker (muted in test builds made for quiet hours: AXON7_SPEAKER_MUTE=1)
if [ "$(getprop ro.vendor.axon7m.speaker_mute)" = 1 ]; then
	m 'Bottom Speaker Switch' 0
	m 'Top Speaker Switch' 0
	log "speaker muted (ro.vendor.axon7m.speaker_mute=1)"
else
	m 'Bottom Speaker Switch' 1
	m 'Top Speaker Switch' 1
fi
m 'SLIMBUS_0_RX Audio Mixer MultiMedia2' 1
# Mic
m 'MultiMedia1 Mixer SLIMBUS_0_TX' 1
log "routes set after ${i} s, ${fail} failed"
