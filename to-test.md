# To test (needs a person at the phone)

Things that run on the phone but that only eyes, ears or hands can confirm.
Tick a box, or write what you saw/heard below it, and tell Claude.

All tests are in **Nura** with the drivers from 2026-11-09/11 (kernel patches
0010-0043, installed by hand on the dev phone; in images from
linux-zte-axon7 r23 / device-zte-axon7 r22 on). Log in over SSH or on the
console, `sudo` password as usual.

To get into Nura from LineageOS: reboot and pick **postmarketOS** in the boot
menu (Volume Down, then Power), or make it the default from Nura with
`sudo axon7-bootmenu default pmos 5` (back: `sudo axon7-bootmenu default los 5`).

## Open now (2026-11-27): what only a person can do

In order of how much they unblock. No SIM card exists, so calls, SMS and
mobile data are not on this list. Tell Claude when you start an item; for
every phone item Claude does the flashing and the adb checks, you only do
the hands-and-eyes part.

### A. PC, no phone (10 min): Nura package build needs your sudo
`pmbootstrap build linux-zte-axon7 device-zte-axon7` (exact command in the
Nura r32 section below). The workers cannot type your password. Afterwards
Claude boot-tests Nura r32 on the main phone (Wi-Fi rescan, accelerometer).

### B. Second phone, plug it in: three install tests
Claude installs, you look at the screen. Battery above 50 %.
- [ ] **LineageOS 22.2 on the stock layout** (no vendor partition; branch
  `agent/stock22`), once its server build is done. Expect: installer says
  "stock layout", setup wizard appears, display/touch/Wi-Fi fine.
- [ ] **LineageOS 22.2 November security update**
  (`lineage-22.2-20261126`, security patch 2026-11-01): needs the vendor
  partition, so it goes on after the stock-layout test only if you agree to
  create one (Claude would use the sgdisk steps from INSTALL.md), or on any
  phone that already has it. Check Settings > About phone > Android
  security update = 2026-11-01.
- [ ] **LineageOS 24 standalone release zip** (`lineage-24-20261126`, 1.05 GB):
  same vendor-partition need. Expect: no boot menu, setup wizard, NFC toggle.
  Afterwards decide whether Claude may publish it as a **draft GitHub
  pre-release** (it will not publish without your OK).

### C. Main phone, you nearby: sleep kernel `icc` unplugged (15 min)
`icc` is the only sleep patch that survived suspend (rtc and clk hung the
phone). Deep sleep can only be measured with USB unplugged:
1. Say "start sleep icc unplugged". Claude writes the icc kernel and arms a
   60 s and a 600 s alarm.
2. Pull the USB cable when Claude says so; plug it back after ~11 minutes.
3. If the screen stays dark more than 5 minutes after replugging: hold
   Power ~10 s, pick TWRP in the boot menu, tell Claude.

### D. Nura, second charger chip SMB1351 (3 A charging), someone present
Driver exists (Nura patches 0056/0057) but is off by default until this
passes. Real 3 A wall charger, battery below 80 %.
1. `dmesg | grep smb1351` shows "input suspended"; baseline
   `cat /sys/class/power_supply/qcom-battery/current_now` (about -2000000).
2. `echo 1 | sudo tee /sys/module/smb1351_charger/parameters/enable`
3. Within a minute: dmesg "parallel charging on", `current_now` about
   -3000000.
4. Feel the phone every 5 minutes; `qcom-battery/temp` must stay at or
   below 400 (40 °C).
- **Stop** (`echo 0 | sudo tee .../enable`, unplug) if: too hot to hold,
  temperature above 40 °C, charger sags or the phone resets, I2C/charger
  errors in dmesg, more than 3.2 A, or above 4.25 V with the chip still on.
5. Unplug mid-charge: dmesg "parallel charging off". `sudo rmmod
   smb1351_charger`: normal 2 A charging continues.

### E. Display scaler (eyes only, LineageOS 24 or Nura)
Play a video in a small window and scroll Settings and the app drawer:
- [ ] no one-pixel smear at the edges, no seam down the middle of the screen
- [ ] app open/close animations without flicker at the screen edges

### F. For the A2017U reporter (issue #1), not for us
Ask them to run, with LineageOS 22.2 booted and USB debugging on:
`tools/axon7-cellular-diag.sh --rom los22` (read-only) and paste the output
into issue #1 after checking it for IMEI/ICCID (the script redacts them).

### Done without you (2026-11-26/27, for reference)
LOS 24 build 57/58 (Wi-Fi fixed, enforcing boots, NFC on, accelerometer 9.84
m/s²) passed on the main phone; TWRP 3.7.0/3.6.2/3.3.1 each stayed up 10 min
flashed on the second phone (restart not reproduced; 3.3.1-0 left flashed);
sleep: rtc and clk hang, icc passes on USB; build 59 (zero-denial enforcing)
builds and tests itself once the server is free.

## Nura r32 (2026-11-26): Wi-Fi and accelerometer checks

The r32 packages were prepared locally but were not built or booted in this
run: no phone was connected and the PC build stopped at noninteractive sudo
authentication. On 2026-11-26 the stale config checksum in the package was
fixed (the `CONFIG_QCOM_IPA2_LITE=m` line had been added without updating
`sha512sums`; all 63 patch sums verify). The two LineageOS 24 patches
0013/0014 (QSEED2 scaler, GPU DDR bandwidth) were already in the series as
Nura 0052/0053 since r27 and have identical patch-ids, so no new numbers
were added. The full series 0001-0063 was re-applied with `git am` on a
clean Linux 7.3.1 tree (63/63 clean; resulting tree `cf97ccf6e99f`,
identical to `aae3898ef`), and `make Image dtbs` with the Nura config built
both (Image 31605248 bytes, `msm8996-zte-axon7.dtb` 86296 bytes, 0 compiler
warnings).

**Build the packages (needs the PC sudo password, owner):**

```sh
# from the zte-axon7 repo root
D=~/.local/var/pmbootstrap/cache_git/pmaports/device/testing
rm -rf "$D"/{linux-zte-axon7,device-zte-axon7,firmware-zte-axon7}
cp -r postmarketos/pmaports-local/device/testing/* "$D"/
python3 "/media/devilapi/Secondary HDD 2TB/ai-worker/axon7/nurasync-build/pmbootstrap/pmbootstrap.py" \
      build --lax --arch aarch64 --force linux-zte-axon7 device-zte-axon7
```

The system `pmbootstrap` 3.10.3 is too old for this pmaports tree; the
3.12.1 clone above is the one that gets past that check and stops only at
`sudo` (the first call is `sudo cp` for the APKINDEX, before any compiling).
The local `~/.config/pmbootstrap_v3.cfg` names `xiaomi-miatoll`, but the
command builds one explicit package for `--arch aarch64` and installs
nothing, so the device setting does not choose what is built. The built
packages land in `~/.local/var/pmbootstrap/packages/edge/aarch64/`.
Then install a r32 image/boot package and check:

- [ ] Boot Nura, `journalctl -u axon7-firmware -u axon7-wifi-rescan -b`:
      the firmware service should list `board.bin` among the files from the
      modem partition; the rescan service should not print "no Wi-Fi chip on
      PCIe". It may print "ath10k_pci loaded after the rescan" on a boot where
      the link came up late. Do not post the SSID, password or MAC address.
- [ ] `ip link show wlan0`, then connect to a known network with `nmcli`:
      `nmcli device status` should show `connected`. On a boot with a late link
      this is the case that the new modprobe step is meant to rescue.
- [ ] Flat on the table, screen up, read the accelerometer magnitude from
      `iio-sensor-proxy` (`monitor-sensor`) or the raw sysfs values times
      `in_accel_scale`: expect about 9.8 m/s² (not 10.6). Turn the phone once
      by hand to check that the axis mapping still reports "face-up".
- [ ] `sudo dmesg | grep -iE 'ath10k|firmware.*fail|smgr_accel'` should have
      no new `ath10k` firmware errors. Redact any SSID/BSSID/MAC before
      pasting logs.

## A2017U (US) hardware checklist (2026-11-21)

For the reporter of [issue #1](https://github.com/devilAPI/zte-axon7/issues/1)
or anyone with an A2017U. **No phone in this project's test rack is an
A2017U**, so every item below is for a person with the US phone. Start with
`docs/variant-a2017u.md`; the shared scripts are read-only unless a step
explicitly says `--apply --yes`.

**Never** write `persist`, `modemst1/2`, `fsg`, `fsc`, `modem`, `aboot`,
`xbl` or any other bootloader partition for these tests. Back up EFS/persist
to a computer first. Do not cross-flash an A2017G/A2017U/A2017 EDL or modem
package. Do not post IMEI/MEID/ESN, SIM IDs (ICCID/IMSI), phone numbers,
Wi-Fi names (SSIDs) or MAC addresses; redact them from logs.

### A. Read-only baseline (TWRP or Android; no changes)

- [ ] `getprop ro.product.device` -> `ailsa_ii`; `getprop ro.product.model` -> A2017U; `getprop ro.lineage.version` and `getprop gsm.version.baseband` (baseband is the modem version, safe to post).
- [ ] `cat /dev/block/bootdevice/by-name/tz | tr -c '[:print:]' '\n' | grep QC_IMAGE_VERSION_STRING` -> `QC_IMAGE_VERSION_STRING=TZ.BF.4.0.1-00353`.
- [ ] `tools/axon7-preflight.sh --rom los22` (or `los24`/`nura`) -> paste the whole output. It reports the `/data` filesystem (ext4/f2fs), the vendor partition size and the TZ. From TWRP: `adb push tools/axon7-preflight.sh /tmp/ && adb shell sh /tmp/axon7-preflight.sh --rom los22`.
- [ ] `ls -l /dev/block/bootdevice/by-name/{system,vendor,userdata}` and `for p in system vendor userdata; do b=$(readlink -f /dev/block/bootdevice/by-name/$p); echo "$p $(( $(cat /sys/class/block/${b##*/}/size) / 2048 )) MiB"; done`.
- [ ] `tools/axon7-make-vendor.sh` (no `--apply`) -> paste the plan; it must show the phone's own sector numbers, not a copied example.
- [ ] `tools/axon7-cellular-diag.sh --rom los22` (or `--rom los24` on the LOS 24 multi-boot slot) -> paste the whole output. Read-only; no SIM needed; it detects the variant, the modem firmware version (`gsm.version.baseband`) and the radio stack (rild / rmtfs+qrtr+radio HAL). No FAIL lines + a baseband value means the modem/Radio came up far enough to answer.

If `--rom los22` says `FAIL /data is f2fs`: that is the issue-#1 trap. In
TWRP, **Wipe > Advanced Wipe > Data > Repair or Change File System > EXT4**
(or `mke2fs -t ext4` *erases internal storage*), then reboot to recovery and
run the check again. Do not flash a ROM while it still says f2fs.

If `--rom los24` says `FAIL no vendor partition`, or you want the vendor
partition for a 22.2 build that requires it, create it on purpose, after the
plan looks right and you have copied the printed GPT backup off the phone:
(`--rom los22` now only warns about a missing vendor: the stock-layout zip
from `agent/stock22` installs without one.)

```sh
tools/axon7-make-vendor.sh --apply --yes     # then reboot to recovery
```

(The script backs up the GPT, refuses an occupied partition 28 or a wrong
layout, and never touches EFS/persist/modem/bootloader.) Afterwards wipe
**System** before flashing, because the old ext4 filesystem is larger than
the shrunken partition.

### B. LineageOS 22.2 (the ROM the reporter already booted)

- [ ] Clean install per the XDA post (Format Data, **then check Data again and
      set EXT4 if needed**, wipe System/Vendor), flash `lineage-22.2-*-axon7.zip`.
- [ ] First boot: `adb logcat -b all -d > logcat.txt`, `adb shell dmesg > dmesg.txt`,
      `adb shell getprop > props.txt`; if it loops, grab `/sys/fs/pstore/`
      from TWRP right away.
- [ ] `adb shell getprop sys.boot_completed` -> 1; Settings shows Android 15.
- [ ] Cellular (only if you have a SIM and accept that this is experimental):
      - [ ] insert a known-good SIM in slot 1; `adb shell getprop gsm.version.baseband` (no IMEI).
      - [ ] `adb shell dumpsys telephony.registry > telephony.txt` and `adb logcat -b radio -d > radio.txt` (**redact ICCID/IMSI/phone number**).
      - [ ] Does Settings > About > SIM status show the carrier? Can you call a known number, send an SMS to yourself, and load a page over mobile data with Wi-Fi off?
      - [ ] Report exactly which of the three works; "SIM detected" alone is not "cellular works".
- [ ] Note whether `/data` stayed ext4 after the first boot (`tools/axon7-preflight.sh --rom los22` again).

### C. LineageOS 24 (multi-boot, untested on U)

- [ ] Only after the multi-boot layout and a vendor partition exist. Run `tools/axon7-preflight.sh --rom los24`; all of `boot`, `los_boot`, `los_metadata`, `los_data`, `system`, `vendor` must be present.
- [ ] Install by ADB sideload as in the XDA post; the installer verifies every write. First start 4-6 min.
- [ ] `adb logcat -b all -d`, `adb shell dmesg`; check the screen/GPU (a black screen usually means no `a530_zap` on vendor), Wi-Fi and sound route logs. No cellular is implemented; do not test calls as a pass/fail item.

### D. Nura (mainland Linux; untested on U)

- [ ] Write the sdcard image, flash `boot.img` in TWRP, first start. `journalctl -u axon7-firmware` and `sudo dmesg > dmesg.txt`; report whether the modem/DSP/GPU/Wi-Fi firmware was found (with or without a vendor partition).
- [ ] `cat /sys/class/power_supply/qcom-battery/capacity` before/after; no long run below 30 %.
- [ ] Cellular: `sudo qmicli -d qrtr://0 --uim-get-card-status` (redact ICCID/IMSI) and `sudo mmcli -L`/`-m 0`; say whether the modem is online and whether a SIM is seen. Calls/SMS/data remain **untested** until someone actually places a call / sends an SMS / transfers data.
- [ ] Wi-Fi and GPU: connect to a network (do not post the SSID/password), `glxinfo -B` or a GLES test; report the renderer (freedreno) and any firmware error.

### E. iOS 16 (alpha; untested on U)

- [ ] Follow `DEV-MULTIBOOT.md` (no downloads; build from the IPSW). The U's unlock/recovery step is the A2017U one above. There is no cellular support on this port; do not test it.
- [ ] Report: does the boot menu appear, does iOS reach the lock/home screen, does Wi-Fi rejoin, does touch work? `tools/sweet-log-pull.sh` in TWRP plus `/sys/fs/pstore/pmsg-ramoops-0`.

### F. Report template

```text
Model/revision: A2017U 4/64
ROM + build date:
TZ string:
TWRP version:
/data filesystem before/after: ext4 / f2fs
vendor: absent / <size> MiB / fs
preflight output (paste):
first boot: OK / loop (pstore attached)
cellular: not tested / SIM seen / call / SMS / data (which ones)
Nura: firmware found / modem online / Wi-Fi / GPU
notes:
```

## 0. From the unattended session (2026-11-14 evening)

**MAIN PHONE DOWN (2026-11-23 ~08:43), needs your hands:**

- [ ] The selinux worker's SELinux-enforcing test boot did not finish and the phone is off USB. Please hold **power ~10 s**, pick **TWRP** in the boot menu, leave it plugged in and tell Claude (the saved LineageOS boot image goes back from TWRP).

**MAIN PHONE DOWN AGAIN (2026-11-22 22:32), needs your hands:**

- [x] (fixed 2026-11-23: owner reset to TWRP, Claude restored the saved los_boot, LOS #31 boots) The sleep worker's guarded test kernel booted LineageOS, then hung in a CPU idle state about a minute later (no adb/fastboot since 22:32; the automatic restore cannot run on a hung phone). Please hold **power ~10 s**, pick **TWRP** in the boot menu, leave it plugged in and tell Claude; the saved LineageOS boot image is put back from TWRP. Deep-sleep kernel tests on the main phone are stopped until you are around.

**MAIN PHONE DOWN (2026-11-22 ~18:45), needs your hands:**

- [x] (fixed 2026-11-22 19:40: owner reset to TWRP, Claude restored the #31 LOS 24 kernel, boots) The main phone (the main phone) was off USB (no adb, no fastboot). The sleep worker wrote an untested test kernel into its **los_boot** partition and it did not boot. Please hold **power ~10 s**, then in the boot menu (Volume Down, Power) pick **TWRP**, leave it connected and tell Claude: a worker then restores the known-good LineageOS 24 boot image from TWRP over adb. Do **not** pick LineageOS first (it would start the broken test kernel again). Saved menu block: ai-worker/axon7/sleep/.kfast-sleep/misc-before.bin.
- [ ] Second phone: still in Nura without a sudo password. Booting it into TWRP (power 10 s, then Volume Down at start) or allowing a test sudo password unblocks the zip3 install test and the Nura-side driver tests.

**Blockers for the unattended work (2026-11-21 afternoon):**

- [x] **Second phone** back in TWRP (owner, 2026-11-21 ~16:30). Open question: may Claude set its own sudo password (stored only on this PC, ~/.config/axon7, never in the repo) in that phone's Nura install, so root tests over SSH work without asking? Until then tests boot test kernels with the debug initramfs from TWRP.
- [x] **Build server** back (owner restarted it, 2026-11-21 ~17:40).
- [x] **Second phone was stuck in fastboot (2026-11-21 ~17:55–18:30);
      owner power-reset it and reported TWRP at 18:31.** It had enumerated on USB as `18d1:d001 ZTE Axon 7`, but
      `fastboot devices` / `fastboot getvar product` do not see it at all
      ("waiting for any device") and `adb devices` lists only the main phone.
      The zip3 worker holds the phone lock and has tried fastboot commands and
      an SSH reboot (the latter cannot work in fastboot). Please hold the
      **power key for ~10 s** to force a power-off, then let it boot and tell
      Claude which state it reaches (TWRP, Nura, or fastboot again). Do not
      write any partitions. This blocks zip3's install test and all other
      second-phone work (ipa/sleep/accel).

**SIM card (2026-11-21):**

- [ ] **SIM card (2026-11-21, updated)**: please insert a known-good SIM in the main phone and tell Claude which slot. QMI on LineageOS 24 (and on Nura) reports both slots "card error 3, no ATR"; this modem firmware answers NOT_SUPPORTED to UIM GET_SLOT_STATUS and DMS UIM GET_STATE, so it cannot tell whether a card is physically present. Calls, SMS and mobile data on both systems wait on this. Details: lineageos-24-mainline/RIL-PLAN.md section 4.1.

**Boot menu:** while Claude works unattended the boot menu default is
**LineageOS** (any reset must end in a system Claude can reach over adb;
Nura needs its password). Your old setting was postmarketOS after 5 s. Back to
it from Nura: `sudo axon7-bootmenu default pmos 5` (the original block is
also saved as `ios/research/axon7/manual-boot/misc-before.bin`).

**Second phone (serial the second phone) runs Nura r25 now** (2026-11-15, from its
internal storage: the card image is in its userdata partition, boot.img with
two startup fixes for 4096-byte UFS sectors, see
ios/research/phone2/nura-userdata/). Boots, display on, touch bus at 400 kHz,
touch keys (F1A) present; GPU without firmware (this phone has no vendor
partition, a530_zap missing). Only you can do the touch part: on that phone,
swipe and type at the login, press the three touch keys, then tell Claude.
If typing works, Claude publishes the r25 draft (nura-latest).
Checked there without hands: 15 thermal zones at 30-40 C, a plain restart
comes back into Nura, Wi-Fi/modem/ADSP/SLPI firmware load; the GPU works
after the firmware fix of 11518fe (not in r25: on phones without a vendor
partition r25 leaves the GPU off).

**Second phone stuck at start (2026-11-20 ~02:00):** after about 70 test
restarts it stopped in the startup stage (initramfs) and has stayed there
since: USB networking answers ping, but no SSH and no telnet, which matches
the "Filesystem needs manual repair (fsck)" screen, where the startup waits
for a key. Please:

- [ ] Look at the second phone's screen. If it shows the fsck message, press Volume Up (the start continues); otherwise hold the power key ~10 s to restart. Then tell Claude, it repairs the file system over SSH.

**Second phone, r28 kernel (2026-11-19 evening):** suspend, the SMB1351
second charger chip and CPU idle states, checked without hands on the second
phone (ios/research/phone2/kernel-r27/RESULTS-r28.md): 7 suspend cycles with
an alarm wake (30 s to 5 min), USB, Wi-Fi, modem, touch and Bluetooth back
each time; the SMB1351 driver loads and, off by default, only holds the chip's
input suspended. Only you can do these:

- [ ] Wall charger (not a PC port), battery below about 80 %. The SMB1351 is off by default; switch it on for this test with one line, `echo 1 | sudo tee /sys/module/smb1351_charger/parameters/enable` (lasts until the next restart; permanently: `echo "options smb1351_charger enable=1" | sudo tee /etc/modprobe.d/smb1351.conf`, or `smb1351_charger.enable=1` on the kernel command line). Then `cat /sys/class/power_supply/smb1351-parallel/online` shows 1 within a minute and `sudo dmesg | grep smb1351` says "parallel charging on"; `cat /sys/class/power_supply/qcom-battery/current_now` is more negative than about -2000000 (more than 2 A into the battery). The phone must not get hot; unplug if it does
- [ ] Unplugged, `sudo systemctl suspend`: the screen goes dark; a short press of the power key wakes it
- [ ] Unplugged and suspended: plugging in a charger wakes it
- [ ] SIM: put a SIM card into the phone and run `sudo qmicli -d qrtr://0 --uim-get-card-status`: does slot 1 say "present" instead of "no-atr-received"?

**Second phone, r27 kernel (2026-11-19):** kernel 0049-0053 (display
scaler, GPU memory bandwidth, three crash fixes from LineageOS 24) run on the
second phone (7.3.1-t3+ in its boot partition), checked without hands
(ios/research/phone2/kernel-r27/RESULTS.md). One audio finding that r26
had too: in a test, a second short playback (1 s, tinyplay) about 20 s after
the first, or one started about 70 s after boot while Nura restarts the audio
processor, failed and the sound stayed off until a restart. Checked on the
same kernel series under LineageOS 24 on 2026-11-22: ten playbacks with 1-60 s
pauses and playbacks after an ADSP restart all work; the failure was the ADSP
restart racing a card that had just appeared (details and logs in
`postmarketos/README.md`, "Audio: repeated playback and the ADSP restart").
`device-zte-axon7` r31 (pkgrel 26) makes the start helper wait for a usable
card, never stops the ADSP under an open player and never starts a
half-stopped one.

- [ ] After r31: play ten short things in a row (or two songs, pause/resume between) and `sudo dmesg | grep -i q6`; no timeout/error lines and every playback starts. Then restart the ADSP by hand (`sudo sh -c 'echo stop > /sys/class/remoteproc/remoteproc2/state'; sleep 2; echo start > /sys/class/remoteproc/remoteproc2/state'`) while nothing is playing, wait for the card, and play again. If sound stays off, run `sudo /usr/libexec/axon7-audio-kick --check` and send the output plus `sudo dmesg | grep -iE 'q6|apr|slim'`.
- [ ] In a desktop that uses hardware planes (Phosh/phoc), a scaled video or window looks right (no seam or edge in the middle of the screen)

**Second phone, kernel 0047/0048 (2026-11-16 night):** the GPU fixes from
LineageOS 24 (vblank after a display timeout, shared GPU buffers) are in the
Nura kernel series (linux-zte-axon7 r26) and run on the second phone (test
kernel 7.3.1-t1+ in its boot partition). Checked without hands: no GPU faults
in 10 minutes of kmscube, no buffer leak, vblank interrupts keep coming, all
other drivers as before (ios/research/phone2/kernel-0047-0048/RESULTS.md).
That phone showed the "Your device is corrupt" screen at every start and
waited for a key; fixed with `adb reboot "dm-verity enforcing"` from TWRP.

- [ ] On the second phone: the screen shows Nura's console and buffyboard, touch and the three touch keys react
- [ ] After the r26 release: in Phosh, scroll and open/close apps for a few minutes; `sudo dmesg | grep -i "gpu fault"` prints nothing

**Nura r25** (draft release, built by GitHub after the push of 97fb832):
touchscreen fix (0044/0045), temperature sensors (tsens), plain reboot fix
(0046). Flash it, then:

- [ ] Typing on the on-screen keyboard works, quick taps register
- [ ] `cat /sys/class/thermal/thermal_zone*/type` lists cpu0-thermal ... gpu-top-thermal (about 14 zones); `cat /sys/class/thermal/thermal_zone*/temp` shows 30000-60000 (30-60 C)
- [ ] `sudo reboot` comes back into Nura (not TWRP), also after a `sudo systemctl reboot --reboot-argument=recovery` + reboot from TWRP
- [ ] Then publish the draft release on GitHub and paste the changelog from XDA-POST-NURA.md

**LineageOS 24** (build 31 + kernel from los24-kfast.sh, on the phone now):

- [x] Touch: quick taps and typing work (owner, 2026-11-14; 9.8 ms per report)
- [ ] Speaker sound: not possible yet, ringtones/alarms are silent (Vorbis decoder fails in LOS 24, Claude is on it)
- [ ] Wi-Fi: connect to your network once (Settings), tell Claude it worked or what it said
- [ ] Headphones: plug in while music plays (after the decoder fix), sound moves to the headphones
- [ ] **SIM card**: is a SIM in the phone (which slot)? The modem now runs in LineageOS 24 and reports both slots as "card error, no ATR" (QMI UIM, 2026-11-14). With a SIM inserted that would point to the SIM supply; with none it is just "empty". Just tell Claude yes/no and the slot.

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

## 9. Screen brightness

```sh
echo 20  | sudo tee /sys/class/backlight/994000.dsi.0/brightness
echo 255 | sudo tee /sys/class/backlight/994000.dsi.0/brightness
echo 160 | sudo tee /sys/class/backlight/994000.dsi.0/brightness
```

- [ ] The console gets dim, bright, and back to normal

## 10. Touch keys (the three keys under the screen)

```sh
sudo evtest   # pick "Synaptics S3718AR", then touch each key once
```

- [ ] Left key gives `KEY_BACK`, middle `KEY_HOMEPAGE`, right `KEY_APPSELECT`
  (write down the order if it differs)
- [ ] Each key gives one press (value 1) and one release (value 0), no repeats
- [ ] The key lights (if any) come on: there is no driver for them yet, so
  probably not

## 11. Headset / headphone detection (silent)

No sound needed. Watch the kernel log and the jack controls while plugging:

```sh
sudo dmesg -w | grep jack &       # prints "ak4961 ... jack: headset" etc.
watch -n1 'amixer -c0 cget iface=CARD,name="Headphone Jack" | tail -1; amixer -c0 cget iface=CARD,name="Mic Jack" | tail -1'
```

- [ ] Plug in a **headset** (with microphone): `jack: headset`, both controls `on` within ~1 s
- [ ] Unplug: `jack: unplugged`, both `off`
- [ ] Plug in **headphones** without microphone: `jack: headphones`, only `Headphone Jack` on (~1.5 s)
- [ ] Plugging slowly or wiggling the plug doesn't leave a wrong state after it is fully in

If it works, the sound settings can switch to headphones and the headset mic
by themselves (UCM jack controls, next step).

## Afterwards

When kernel r8 is installed as a package, remove the hand-installed copies
so they don't override it:

```sh
sudo rm -r /lib/modules/7.3.1/extra /lib/modules/7.3.1/updates && sudo depmod -a
```
