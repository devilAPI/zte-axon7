# Audio test tools (Axon 7, main phone under LineageOS 24)

Silent only: every script plays digital silence with the TFA9890 speaker
switch verified `Off` and `Digital Playback Volume 0 0`; nothing is unmuted.
Take the phone lock for a test session and leave LineageOS reachable:

```sh
flock -w 900 ~/.cache/axon7-phone-7e15695a.lock ./audio-tools/los24-repeated-audio.sh /tmp/audio.log
```

Prerequisites on the phone (already there on the test builds): a static
`tinyplay` at `/data/local/tmp/tinyplay` and a 1 s 48 kHz stereo 16-bit
silence WAV at `/data/local/tmp/z.wav`.

- `los24-silent-audio.sh LOG pause...` – N silent playbacks with those
  pauses, amplifier check before each one.
- `los24-repeated-audio.sh LOG` – ten playbacks with 1-60 s pauses, then an
  ADSP stop/start and two more playbacks (the 2026-11-22 test).
- `inspect-audio.sh LOG` – read-only state: card, PCMs, remoteprocs,
  modules, q6/APR/SLIMbus dmesg.
- `check-snd.sh` – read-only open/fd/PCM/mixer check, run on the phone.
- `test-audio-kick.sh [path]` – off-device tests for
  `device-zte-axon7/axon7-audio-kick` with a fake sysfs/proc (23 checks).

The results referenced in `postmarketos/README.md` are in the shared test
checkout under `ios/logs/audio-20261122-los-*.txt` (not committed here).
