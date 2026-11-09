# To test (needs a person at the phone)

Things that run on the phone but that only eyes, ears or hands can confirm.
Tick a box, or write what you saw/heard below it, and tell Claude.

All tests are in **Nura** with the drivers from 2026-11-09 (kernel patches
0010-0016, installed by hand on the dev phone; in images from
linux-zte-axon7 r9 / device-zte-axon7 r14 on). Log in over SSH or on the
console, `sudo` password as usual.

To get into Nura from LineageOS: reboot and pick **postmarketOS** in the boot
menu (Volume Down, then Power), or make it the default from Nura with
`sudo axon7-bootmenu default pmos 5` (back: `sudo axon7-bootmenu default los 5`).

## 1. Headphone audio (Hi-Fi DAC, AK4490)

Plug in wired headphones first. Start quietly.

```sh
alsaucm -c hw:0 set _verb HiFi          # routes the player to the Hi-Fi DAC
amixer -c0 sset Digital 60%             # DAC volume (0-100 %)
speaker-test -D hw:0,0 -c 2 -r 48000 -t sine -f 440 -l 1
speaker-test -D hw:0,0 -c 2 -r 48000 -t wav -l 1   # says "Front Left" / "Front Right"
```

- [ ] A 440 Hz tone is audible
- [ ] "Front Left" comes out of the **left** ear, "Front Right" of the **right**
- [ ] No loud pop or click when playback starts or stops
- [ ] Volume changes with `amixer -c0 sset Digital 30%` / `80%`
- [ ] Music file: `aplay -D hw:0,0 some-48k-stereo.wav` sounds clean (no crackle, right speed/pitch)
- [ ] 44.1 kHz file: `aplay -D hw:0,0 some-44k1.wav` (speed/pitch right?)

With the Headphones device, nothing should come out of the speakers.

## 1b. Speakers (AK4961 + two TFA9890 amplifiers)

New 2026-11-09 night, kernel patches 0015/0016. **Start very quietly**: the
amplifiers run without NXP's speaker protection profile (DSP bypass), so
don't play loud for long.

```sh
alsaucm -c hw:0 set _verb HiFi set _enadev Speaker
speaker-test -D hw:0,0 -c 2 -r 48000 -t sine -f 440 -l 1   # rather loud: test tone at full scale
speaker-test -D hw:0,0 -c 2 -r 48000 -t wav -l 1           # "Front Left" / "Front Right"
```

- [ ] Sound comes out of the speakers at all
- [ ] Both speakers (top and bottom grille) play
- [ ] "Front Left" comes from the speaker on the left when the phone is held sideways with the volume keys up (if it's swapped, say so: the amp order 0x34/0x35 is a guess)
- [ ] No distortion or crackling at moderate volume
- [ ] Switching back to headphones works: `alsaucm -c hw:0 set _verb HiFi set _disdev Speaker set _enadev Headphones`

## 2. Vibration

```sh
sudo axon7-rumble 0xffff 1000    # full strength, 1 s
sudo axon7-rumble 0x4000 1000    # weaker
sudo axon7-rumble 0xffff 200     # short buzz
```

- [ ] The phone vibrates
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

## 5. Battery (already confirmed, just watch it)

```sh
cat /sys/class/power_supply/qcom-battery/{capacity,status,voltage_now,current_now,temp}
```

- [ ] Unplugged: status "Discharging", current positive (µA), capacity falls over time
- [ ] Charger plugged in while below ~95 %: status "Charging", current negative
- [ ] At 100 % on the charger: "Full" or "Not charging"
- [ ] Capacity roughly matches what LineageOS shows

## Afterwards

When kernel r8 is installed as a package, remove the hand-installed copies
so they don't override it:

```sh
sudo rm -r /lib/modules/7.3.1/extra /lib/modules/7.3.1/updates && sudo depmod -a
```
