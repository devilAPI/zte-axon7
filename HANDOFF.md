# Handoff: ZTE Axon 7 (A2017G), Nura + LineageOS 24 on mainline Linux

State of 2026-11-14. Written for continuing the work on another PC with
Claude Code. Section 1 is the prompt to paste; the rest is the reference it
points to.

## 1. Prompt for Claude Code on the other PC

```
You are continuing the bring-up of the ZTE Axon 7 (A2017G) on mainline
Linux 7.3.1: "Nura" (postmarketOS-based, branch main) and LineageOS 24
(AOSP 17) on the same kernel (branch lineageos-24-mainline). Read
HANDOFF.md in github.com/devilAPI/zte-axon7 (main) first, then
lineageos-24-mainline/PLAN.md on the lineageos-24-mainline branch (the run
table at the end is the history). Set up the checkouts as in HANDOFF.md
section 3. Rules (HANDOFF.md section 2) are binding: quiet hours, no
passwords in files or commits, ETAs in every status update, no SLPI
restarts. Current task: LineageOS 24 performance (HANDOFF.md section 5.1),
then the open items in order. Work unattended on the phone; the test loop
(ios/tools/los24-run.sh) needs no hands on the phone. Commit with clear
messages; push only when asked.
```

## 2. Rules from the owner

- **Quiet hours 03:00-17:30 (local time, CET):** no audible tests (speaker,
  earpiece, tones, speaker-to-mic loopbacks); vibration only short and weak.
  Outside that window loud tests are fine. Schedule sound tests for 18:30.
  Builds during quiet hours use `AXON7_SPEAKER_MUTE=1` (speaker and earpiece
  amplifiers stay off in the mixer routes).
- **Status updates always give ETAs** (build ~25 min incremental, test run
  ~15 min, kernel + image ~35 min).
- **Never commit passwords.** Nura's sudo password comes from the
  environment variable `PMOS_SUDO_PASS`; the Nura SSH password via an
  `SSH_ASKPASS` helper outside the repo. Never send the owner's email address
  to outside services.
- **Never restart the SLPI remoteproc** (sensor DSP) on mainline: stop/start
  never brings it back and the SoC freezes until a forced power-off (runs 24,
  twice). Restarting the ADSP is fine (Nura uses it, see 5.4).
- Unattended LineageOS tests: no human interaction with the phone needed or
  expected. The owner may still use the phone during a hold run.
- Don't `pkill -f <pattern>` from a shell whose own command line contains the
  pattern (it kills itself, exit 143/144).
- Every user-visible Nura change gets a line in the changelog
  (XDA-POST-NURA.md "Changelog", newest date first).

## 3. Checkouts, machines, access

| What | Where |
|---|---|
| Main repo | `github.com/devilAPI/zte-axon7`, branch `main` (Nura: `postmarketos/`, docs, XDA posts) |
| LineageOS 24 tree | same repo, branch `lineageos-24-mainline` (dir `lineageos-24-mainline/`: device tree, kernel patches, AOSP patches, scripts, PLAN.md) |
| Test tooling | submodule `ios` = `github.com/devilAPI/ios-sailfish`, branch `axon7` (`tools/axon7-los-test.sh`, `tools/los24-*.sh`) |
| Build server | `root@compiler` (192.168.178.78, home network only: needs the VPN). Builds run as user `build` in tmux session `los24build` |
| Phone | USB: Nura answers on `user@172.16.42.1` (SSH), TWRP and LineageOS on adb |

```
git clone --recurse-submodules https://github.com/devilAPI/zte-axon7.git
cd zte-axon7 && git -C ios checkout axon7
git worktree add ../axon7-los24-wt lineageos-24-mainline   # LOS 24 work happens here
```

Keep the worktree out of /tmp (tmpfs: a reboot wiped it once). Sync the device
tree to the server from the worktree root:
`bash lineageos-24-mainline/scripts/server-sync-device.sh`.

VPN note: if Tailscale is up it routes 192.168.178.0/24 itself and the server
is unreachable; `tailscale down` while working (it was off before).

### Build commands (on the server, as `build`)

```
S=/srv/los24/axon7/repo/lineageos-24-mainline/scripts
# kernel (v7.3.1 + Nura patch series from main + lineageos-24-mainline/kernel/patches) then image:
ssh root@compiler 'su - build -c "tmux new -d -s los24build \"$S/kernel-build.sh all > /srv/los24/logs/kernel.log 2>&1 && AXON7_SPEAKER_MUTE=1 $S/los24-build.sh droid\""'
# image only (device tree / AOSP patch changes):
ssh root@compiler 'su - build -c "tmux new -d -s los24build \"AXON7_SPEAKER_MUTE=1 $S/los24-build.sh droid\""'
```

`los24-build.sh` applies `lineageos-24-mainline/aosp/<project>/*.patch` once,
takes extra `m` targets as arguments (build single modules first to catch
compile errors in ~5 min), logs to `/srv/los24/logs/build-latest.log`
(ends with `build-exit N`). Default GPU stack is Mesa (`AXON7_GPU=mesa`).

### Test loop (from the `ios` checkout, phone in Nura on USB)

```
export PMOS_SUDO_PASS=...          # Nura sudo password, from the owner
export SSH_ASKPASS=~/bin/askpass-nura   # prints the Nura SSH password (outside the repo)
tools/los24-run.sh 29 28           # wait for build 29, fetch as delta of 28, test, restore Nura
LOS_HOLD=600 PROBE=tools/los24-perfprobe.sh tools/los24-run.sh 29 28   # keep LOS up, measure performance
```

`axon7-los-test.sh` flow: Nura saves its boot + boot menu -> TWRP writes
system/vendor (delta), los_boot, a test boot image and a one-shot boot menu
entry -> LineageOS boots, settles (setup wizard), collects logs
(`logs/los24-m1a-N-{run,hw,audio,dmesg,logcat,...}.txt`, screenshot) ->
TWRP restores boot + menu and pulls pstore -> Nura. If LineageOS freezes the
script waits up to 30 min for TWRP/Nura (a forced power-off by the owner lets
it continue). `LOS_RESTORE=1 tools/axon7-los-test.sh research/los24-build-N
los24-m1a-N` from TWRP only restores Nura. Kernel panics/freezes: the next
boot's `/sys/fs/pstore/console-ramoops` holds the frozen boot's log (pull it
in TWRP before anything else boots).

Small NDK tools (built with the server's NDK
`/srv/los24/tools/android-ndk-r30`, binaries in `ios/research/axon7/bin/`,
pushed by the test): `tools/aarec.c` (AAudio capture level), `tools/aaplay.c`
(AAudio tone, AUDIBLE), `tools/sensread.c` (5 sensors through sensorservice),
`tools/planedump.c` (dump the scanned-out DRM planes) in the LOS tree.

## 4. Where things stand (LineageOS 24, build 28)

| Area | State |
|---|---|
| Boot | Boots to the setup wizard and launcher, SELinux permissive. Kernel patches: 0002 (PID 1 fs_struct for Android init), 0003 (DRM CRTC fence race BUG_ON -> warning; fixed a panic ~3 min after boot) |
| GPU | Mesa freedreno FD530 (GLES 3.1), minigbm `nocompression` (linear), RenderEngine + HWUI `skiagl` |
| Display | drm_hwcomposer on DPU (`msm.prefer_mdp5=0`), dual-DSI command-mode Samsung S6E3HA3 1440x2560. **Slow, see 5.1** |
| Backlight | ueventd now gives `system` the brightness/bl_power files (build 28), but the slider does not change the value yet (stays 211) |
| Wi-Fi | scans (goldfish legacy HAL, `BOARD_WLAN_DEVICE := emulator`); association with a real network seen in a dmesg (owner connected); not tested by script |
| Bluetooth | turns on |
| Audio | AIDL default HAL with our patches: 0001 (q6asm period steps), 0002 (mixer routes per device from `/vendor/etc/audio_routes.conf`, wired devices, earpiece). Mic capture works (AAudio). Mixer route log `applyMixerRoute: card 0 route mic (4 controls, 0 failed)`. Jack input device present; `config_useDevInputEventForAudioJack` via RRO FrameworksResAxon7m. **Speaker playback never heard yet** (quiet-hour builds are muted) |
| Sensors | all 5 work through sensorservice (BMI160 accel/gyro 49 Hz, AK09915 mag, RPR0521 light/proximity); sns-reg serves `/persist/sensors/sns.reg`. Accel magnitude 8 % high, same raw values on Nura |
| Keys | touch keys deliver Back/Home/App switch; Home is disabled by the setup wizard only |
| Modem, camera, GPS, fingerprint, NFC | not done in LOS 24 (camera: 0 devices) |

## 5. Open work, in order

### 5.1 LineageOS 24 performance (owner: "performance in LOS is bad")

Measured (runs 27p, 28; `ios/logs/los24-m1a-27p-perf.txt`, PLAN.md row
"Performance, run 27p"):
- CPU at max (cpufreq-dt, schedutil), GPU devfreq reaches 624 MHz, real GPU
  (not llvmpipe).
- After setup: device composition (2 HWC planes), but the screen updates at
  exactly 30 fps (present2present 33 ms). Apps: post2acquire (queueBuffer to
  GPU done) ~20 ms per frame, the same at 133 and 624 MHz and with
  `debug.mesa.fd.mesa.debug=sysmem` -> not GPU execution time, probably
  waiting (buffer release fences from the command-mode panel?).
- Client composition (notification shade, animations, setup wizard):
  RenderEngine 48-90 ms per composite, 11-20 fps.
- HW vsync works: drm_hwcomposer's DRM_IOCTL_WAIT_VBLANK returns every
  15-16 ms, commits are non-blocking (<1 ms). The earlier "No Last HW vsync"
  was sampled with the screen off.
- `wm size 1080x1920` made apps fast (2 ms) but forces client composition
  (drm_hwc cannot scale): worse overall. Reverted.

Next steps:
1. Find out what the 20 ms are: GPU job timing via ftrace. The msm GPU
   tracepoints were not under `events/msm/` on the build-28 kernel
   (`tools/los24-perfprobe.sh` now lists the available event dirs); check
   CONFIG_FTRACE/event naming, else use perfetto with `gpu` + `sched` + fence
   events. Compare dequeueBuffer waits (HWUI `dequeueBuffer` in a perfetto/
   atrace capture) with GPU busy time.
2. Depending on that: more buffers / SF timing (`ro.surface_flinger.*`,
   `debug.sf.*` durations), DPU command-mode release-fence timing in the
   kernel, UBWC on DPU (minigbm currently forces linear: was needed for MDP5),
   devfreq tuning.
3. Backlight slider (value stays 211): check which path drm_hwcomposer uses
   and whether the framework talks to it (lights HAL?).

### 5.2 Audible speaker test (18:30 or later, never in quiet hours)

Build without `AXON7_SPEAKER_MUTE` (unmuted `audio_routes.conf`), then in
LineageOS: `aaplay 2 1000 -20` (`/data/local/tmp`), check
`applyMixerRoute: ... route speaker`, ALSA errors, the owner listens. Then
earpiece (in-call/communication mode) and headphones (owner plugs in).

### 5.3 Other LineageOS 24 items

SELinux policy (everything runs permissive; the sensors HAL has no domain),
Wi-Fi association test (needs credentials from the owner), modem
(rmtfs/qrtr), camera, accelerometer scale (kernel, shared with Nura), owner
tests: headphone plug, touch keys after setup.

### 5.4 Nura

- `device-zte-axon7` r23 on main (not in an image yet): `axon7-audio-kick`
  restarts the ADSP if the sound card is missing 45 s after boot (tested by
  hand on the phone). Changelog line is in XDA-POST-NURA.md.
- The DRM CRTC fence race (LOS kernel patch 0003) is in Nura's kernel too;
  only userspace that asks fence names (Android HWUI) hits it. Consider
  moving 0003 into Nura's series.

## 6. History in one paragraph

LOS 24 reached the setup wizard on 2026-11-11 (run 14b). 2026-11-12:
Mesa + skiagl gave a clean screen (run 19), Wi-Fi scan (18), audio routes and
capture (20-23), sensors (24-26: sns-reg fdsan crash, SLPI restart freeze,
then the CRTC fence panic fixed by kernel patch 0003), mixer routes per
device (27), performance analysis (27p) and the backlight permission fix
(28). Details and every run: `lineageos-24-mainline/PLAN.md`.
