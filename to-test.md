# To test (needs a person at the phone)

Things that run on the phone but that only eyes, ears or hands can confirm.
Tick a box, or write what you saw/heard below it, and tell Claude.

All tests are in **Nura** with the drivers from 2026-11-09/10 (kernel patches
0010-0041, installed by hand on the dev phone; in images from
linux-zte-axon7 r21 / device-zte-axon7 r22 on). Log in over SSH or on the
console, `sudo` password as usual.

To get into Nura from LineageOS: reboot and pick **postmarketOS** in the boot
menu (Volume Down, then Power), or make it the default from Nura with
`sudo axon7-bootmenu default pmos 5` (back: `sudo axon7-bootmenu default los 5`).

## 1. Headphone audio (Hi-Fi DAC, AK4490)

Plug in wired headphones first. Start quietly.

```sh
alsaucm -c hw:0 set _verb HiFi set _enadev Headphones   # routes the player (hw:0,1) to the Hi-Fi DAC
amixer -c0 sset Digital 60%             # DAC volume (0-100 %)
speaker-test -D hw:0,1 -c 2 -r 48000 -t sine -f 440 -l 1
speaker-test -D hw:0,1 -c 2 -r 48000 -t wav -l 1   # says "Front Left" / "Front Right"
```

- [ ] A 440 Hz tone is audible
- [ ] "Front Left" comes out of the **left** ear, "Front Right" of the **right**
- [ ] No loud pop or click when playback starts or stops
- [ ] Volume changes with `amixer -c0 sset Digital 30%` / `80%`
- [ ] Music file: `aplay -D hw:0,1 some-48k-stereo.wav` sounds clean (no crackle, right speed/pitch)
- [ ] 44.1 kHz file: `aplay -D hw:0,1 some-44k1.wav` (speed/pitch right?)

With the Headphones device, nothing should come out of the speakers.

## 1b. Speakers (AK4961 + two TFA9890 amplifiers)

New 2026-11-09 night, kernel patches 0015-0018. The speakers are already
confirmed working through the phone's own microphone; what's left is how
they sound. **Start quietly**: the amplifiers run without NXP's speaker
protection profile (DSP bypass), so don't play loud for long.

```sh
alsaucm -c hw:0 set _verb HiFi set _enadev Speaker
speaker-test -D hw:0,1 -c 2 -r 48000 -t sine -f 440 -l 1   # rather loud test tone
speaker-test -D hw:0,1 -c 2 -r 48000 -t wav -l 1           # "Front Left" / "Front Right"
```

- [x] Sound comes out of the speakers (measured with the microphone)
- [ ] Both speakers (top and bottom grille) play
- [ ] Both speakers play (UCM sets both to the left channel for now, mono)
- [ ] Stereo, only if you like (quietly): `amixer -c0 cset name='Speaker Bottom Amp Input' Right`, then `speaker-test -D hw:0,1 -c 2 -t wav -l 1`: does "Front Right" come out of the bottom speaker? (In a measurement it stayed nearly silent; set it back with `... Left`.)
- [ ] No distortion or crackling at moderate volume
- [ ] Switching back to headphones works: `alsaucm -c hw:0 set _verb HiFi set _disdev Speaker set _enadev Headphones`

## 1b2. Earpiece

```sh
alsaucm -c hw:0 set _verb HiFi set _enadev Earpiece
speaker-test -D hw:0,1 -c 2 -r 48000 -t sine -f 440 -l 1   # hold the phone to your ear, quietly
```

- [ ] The sound comes out of the earpiece opening at the top, not the bottom speaker
- [ ] Back to speakers: `alsaucm -c hw:0 set _verb HiFi set _disdev Earpiece set _enadev Speaker`

## 1c. Microphone

```sh
alsaucm -c hw:0 set _verb HiFi set _enadev Mic
arecord -D hw:0,0 -f S16_LE -r 48000 -c 2 -d 5 /tmp/mic.wav   # speak into the bottom of the phone
aplay -D hw:0,1 /tmp/mic.wav                                  # play it back (speaker or headphones)
```

- [x] The microphone records (measured: vibration and speaker tone show up)
- [ ] Your voice is clear and loud enough (gain: `amixer -c0 cset name='MIC Gain 1L' 0..10`, 3 dB steps, default 5)
- [x] Two microphones: left channel = bottom, right channel = top (measured)
- [ ] Both channels sound alike when you speak from the front

Headset microphone (new 2026-11-10): plug in a headset with a microphone
(4-pin plug), then

```sh
alsaucm -c hw:0 set _verb HiFi set _enadev Headset
arecord -D hw:0,0 -f S16_LE -r 48000 -c 2 -d 5 /tmp/hs.wav   # speak into the headset
alsaucm -c hw:0 set _verb HiFi set _disdev Headset
```

- [ ] Your voice is on the left channel of /tmp/hs.wav (play it back quietly, or send it to Claude)

## 2. Vibration

```sh
sudo axon7-rumble 0xffff 1000    # full strength, 1 s
sudo axon7-rumble 0x4000 1000    # weaker
sudo axon7-rumble 0xffff 200     # short buzz
```

- [x] The phone vibrates (the microphone hears it, +30 dB)
- [ ] The weaker one is noticeably weaker
- [ ] It stops when it should (no buzzing on)

## 3. Flashlight (rear dual-tone flash, torch mode)

```sh
echo 10 | sudo tee /sys/class/leds/white:torch/brightness   # ZTE's default (~125 mA per LED)
echo 16 | sudo tee /sys/class/leds/white:torch/brightness   # brightest (200 mA per LED)
echo 1  | sudo tee /sys/class/leds/white:torch/brightness   # dimmest
echo 0  | sudo tee /sys/class/leds/white:torch/brightness   # off
```

- [ ] Light comes on
- [ ] Both LEDs light (one is white, one is amber-ish)
- [ ] Brightness changes between 1, 10 and 16 (each change blinks briefly, that's expected)
- [ ] 0 switches it off

## 4. Flip cover sensor (hall sensor)

Needs a magnetic flip cover or a small magnet. The sensor sits near the top
of the front, about where the cover's magnet would be.

```sh
sudo evtest   # pick "gpio-keys", watch for SW_LID
```

(If `evtest` is missing: `sudo apk add evtest`.)

- [ ] Closing the cover / magnet near: `SW_LID ... value 1`
- [ ] Opening / magnet away: `SW_LID ... value 0`
- [ ] Nothing else happens on close (no suspend, no hang): Nura ignores the lid for now

## 5. Battery and charging

Charging control is new (SMBCHG driver, 2026-11-10): 4.4 V float voltage,
up to 2 A. Watch the temperature the first few times.

```sh
cat /sys/class/power_supply/qcom-battery/{capacity,status,voltage_now,current_now,temp}
```

- [ ] Unplugged: status "Discharging", current positive (µA), capacity falls over time
- [ ] Charger plugged in while below ~95 %: status "Charging", current negative
- [ ] At 100 % on the charger: "Full" or "Not charging"
- [ ] Capacity roughly matches what LineageOS shows
- [ ] With a wall charger (not the PC) at ~50 %: `cat /sys/class/power_supply/qcom-smbchg-usb/{usb_type,input_current_limit}` shows DCP and more than 500 mA, `current_now` around -1500000 to -2000000
- [ ] The phone gets warm but not hot while charging (`temp` stays below ~420 = 42 °C)
- [ ] It stops at 100 % (status Full) and the voltage stays around 4.4 V

## 6. Cameras (raw, developers)

Confirmed: both cameras deliver raw pictures (README "Front camera" and
"Rear camera" have the commands). The rear camera has only been seen
lying on a table (torch reflection, colour bars), never a real scene.

- [ ] Rear camera, a real scene: stand the phone up with the back facing
      a bright window or lamp and tell Claude; it takes the picture over
      SSH (nothing to type)
- [ ] Focus: Claude takes a few pictures at different lens positions; one
      of them should be sharp for the distance of the scene

## 7. Motion sensors

New 2026-11-10. Measured only with the phone lying flat on a table.

```sh
sensor() {  # sensor accel|anglvel|magn: one second of samples, x y z per line
	n=qcom-smgr-$( [ $1 = accel ] && echo accel || { [ $1 = anglvel ] && echo gyro || echo mag; } )
	D=$(grep -l "^$n\$" /sys/bus/iio/devices/iio:device*/name); D=${D%/name}
	for c in x y z; do echo 1 | sudo tee $D/scan_elements/in_$1_${c}_en >/dev/null; done
	echo 0 | sudo tee $D/scan_elements/in_timestamp_en >/dev/null
	echo 1 | sudo tee $D/buffer/enable >/dev/null
	sudo timeout 1 cat /dev/${D##*/} | od -v -A n -t d4 -w12 | awk '{printf "%8.2f %8.2f %8.2f\n", $1/65536, $2/65536, $3/65536}' | tail -3
	echo 0 | sudo tee $D/buffer/enable >/dev/null
}
sensor accel
```

- [ ] Accelerometer: lying flat about 0 0 -10; standing upright, about 10 (or -10) moves to another axis
- [ ] Gyroscope (`sensor anglvel`): near 0 at rest, clearly larger while you turn the phone
- [ ] Compass (`sensor magn`): values change when you turn the phone flat on the table

Proximity and light (sensor next to the earpiece):

```sh
D=$(grep -l '^qcom-smgr-prox-light$' /sys/bus/iio/devices/iio:device*/name); D=${D%/name}
for c in proximity illuminance; do echo 1 | sudo tee $D/scan_elements/in_${c}_en >/dev/null; done
echo 0 | sudo tee $D/scan_elements/in_timestamp_en >/dev/null
echo 1 | sudo tee $D/buffer/enable >/dev/null
sudo timeout 1 cat /dev/${D##*/} | od -v -A n -t d4 -w8 | awk '{printf "proximity %d  light %.1f lux\n", $1, $2/65536}' | tail -2
echo 0 | sudo tee $D/buffer/enable >/dev/null
```

- [ ] Uncovered: proximity about 5; with a finger over the earpiece area: a much higher number (please note it)
- [ ] Light: a few hundred lux near a window, low in a dark room

Orientation as a desktop would see it (screen rotation):

```sh
monitor-sensor     # Ctrl+C to stop
```

- [ ] Upright (as you hold a phone): "Accelerometer orientation changed: normal"
- [ ] Turned left / right onto its long side: "left-up" / "right-up" (which is which?)
- [ ] Upside down: "bottom-up"
- [ ] Hand over the top of the screen: "Proximity value changed: 1"; tell Claude the
      proximity number from above with the hand there, to set the near level

## 8. NFC

Needs an NFC card or tag (bank card, transit card, NFC sticker). The
controller answers and starts searching (measured); reading a tag isn't
tested yet. Easiest with neard: `sudo apk add neard`, then

```sh
sudo nfctool -d nfc0 -1     # switch on
sudo nfctool -d nfc0 -p     # start polling, hold the card to the back
sudo nfctool -d nfc0 -0     # switch off
```

- [ ] A "Targets found" line appears when the card touches the back of the phone

## Afterwards

When kernel r8 is installed as a package, remove the hand-installed copies
so they don't override it:

```sh
sudo rm -r /lib/modules/7.3.1/extra /lib/modules/7.3.1/updates && sudo depmod -a
```
