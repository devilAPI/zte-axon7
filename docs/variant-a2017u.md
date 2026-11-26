# A2017U (US) notes: what differs from the A2017G

The project was developed on an **A2017G** (global, 4 GB / 64 GB). All
values in [hardware.md](hardware.md) and [bootloader.md](bootloader.md) were
measured on that phone. This page collects what is known about the **A2017U**
(US / North America) and what is still unverified, from
[issue #1](https://github.com/devilAPI/zte-axon7/issues/1) (a user with an
A2017U 4/64 who booted LineageOS 22.2) and the public sources at the bottom.

**Nothing here was verified on A2017U hardware by the project.** Treat the
"reported" rows as claims to test, not as facts.

## The three models

| Model | Market | Codename | Status here |
| --- | --- | --- | --- |
| A2017G | Europe / global | `ailsa_ii` / `axon7` | the phone the project is tested on |
| A2017U | US / North America | `ailsa_ii` / `axon7` | user-reported working for LineageOS 22.2; everything else untested |
| A2017 | China | `ailsa_ii` / `axon7` | untested |

All three share the same SoC, display, touch, cameras, Wi-Fi/BT/NFC, PMICs
and UFS layout. They differ in **modem/band firmware, the stock software
build and the EFS contents** (a forum statement, not a ZTE document). Because
TWRP and the ROM assert on `ailsa_ii`/`axon7`, the A2017U passes the existing
installers' device checks.

## What is confirmed vs. only reported

| Item | State |
| --- | --- |
| A2017U/A2017G/A2017 share codename `ailsa_ii`/`axon7`; TWRP is `twrp-*-ailsa_ii.img` | confirmed: TWRP download name, LineageOS wiki, our own A2017G |
| LineageOS 22.2 requires TrustZone `TZ.BF.4.0.1-00353` (Oreo bootstack) | confirmed in the zip's updater-script and [FLASHING-PLAN](../lineageos-22.2/FLASHING-PLAN.md) |
| LineageOS 22.2 mounts `/data` **ext4 only** (`fileencryption=ice,quota`) | confirmed in the device-tree fstab patches (`lineageos-22.2/port-22.2/`) |
| The community vendor partition is 512 MiB from the **end of system**; this is the configuration LineageOS 16-18.1/22.2 expects | confirmed: Oki's PARTY thread, our A2017G layout |
| A2017U **stock B35 has no fastboot endpoint**; `adb reboot bootloader` does not expose one | reported (issue #1) |
| An EDL flash of the **B15-NEW aboot + fbop** restores `fastboot oem unlock`; **B29 alone was not enough** | reported (issue #1); the XDA EDL packages are documented to "unlock fastboot operations" |
| A bootstack/EDL package can overwrite recovery, so **TWRP must be flashed again afterwards** | reported (issue #1); matches how the EDL packages carry their own recovery |
| **Gotcha 1: TWRP formats /data as f2fs, fstab requires ext4**<br>TWRP 3.7.0_9-0 `Format Data` can leave **f2fs** on userdata.<br>LineageOS 22.2's fstab mounts `/data` as `ext4` with `fileencryption=ice,quota`. f2fs then fails with `invalid magic`, first stage leaves `/` read-only, apexd cannot create `/data/apex/sessions` and aborts, and `reboot_on_failure` restarts the phone in a loop. It looks like a bootloader fault but is a filesystem mismatch.<br>Fix: in TWRP, **Wipe > Advanced Wipe > Data > Repair or Change File System > EXT4**, or from TWRP's terminal (this erases internal storage):<br>`mke2fs -t ext4 /dev/block/bootdevice/by-name/userdata`<br>Then check again; do not trust the previous "Format Data" result. | reported (issue #1) |
| **Gotcha 2: PARTY is no longer obtainable**<br>The link in the install notes (AFH `fid=1322778262903995063`) has no mirrors, and the XDA attachment is not archived. The equivalent with TWRP's own `sgdisk`: with the real sector numbers of partition 13 (system, 4096-byte sectors), `sgdisk --delete=13 /dev/block/sde`, recreate 13 from its start to `old_end-131072`, and create 28 from `old_end-131071` to `old_end` named `vendor`. Then reboot to recovery. Do not copy sector numbers from another phone.<br>`tools/axon7-make-vendor.sh` does the sector arithmetic and all of the above safety checks. It prints a **read-only plan by default**; `--apply --yes` writes, after saving the old GPT. It refuses a wrong layout, an occupied partition 28, or an existing vendor partition. It never writes EFS/persist/modem/bootloader. | reported (issue #1); the PARTY thread still exists but the download is dead |
| LineageOS 22.2-20261109 boots on A2017U (Android 15, orange verified boot, bootloader unlocked) | reported (issue #1) |
| **Cellular is UNTESTED on A2017U**; the reporter says the U variant uses a different modem path | reported (issue #1). Do not claim calls/SMS/data work |

## Bootloader and fastboot on the A2017U

The A2017G instructions in [bootloader.md](bootloader.md) assume fastboot is
reachable. On stock A2017U B35 it is not:

1. `adb reboot bootloader` never shows a fastboot device; the phone boots
   Android again instead.
2. The route that worked for the reporter was an **EDL** flash (9008 mode:
   phone off, hold Volume Up + Volume Down, plug in USB) of the **B15-NEW
   aboot and fbop** from the archived full EDL package. That restores
   `fastboot oem unlock`. **B29 alone was not enough.** The public
   A2017U EDL packages (`A2017U_B15-NEW_TWRP_EDL`, `A2017U_B15-NEW_FULL_EDL`,
   `A2017U_FASTBOOT_UNLOCK_EDL`) are documented in the XDA thread below.
3. Unlocking wipes userdata. Enable "OEM unlocking" in Developer options
   before starting.
4. The package writes its own recovery. **Flash TWRP back afterwards**
   (`fastboot flash recovery twrp-*-ailsa_ii.img`, or Install > Install Image
   in the package's TWRP) and check the version in TWRP's title bar.
5. Confirm the result before flashing a ROM:

   ```sh
   cat /dev/block/bootdevice/by-name/tz | tr -c '[:print:]' '\n' | grep QC_IMAGE_VERSION_STRING
   getprop ro.product.device      # ailsa_ii in TWRP
   ```

   The first line must contain `TZ.BF.4.0.1-00353` for LineageOS 22.2.

**Do not flash an A2017G EDL/bootstack on an A2017U** (and vice versa). Use
the package for the model, and a **model-specific modem**. The universal
Oreo bootstack is shared, the modem is not.

## `/data` must be ext4 for LineageOS 22.2

The trap reported in issue #1:

- TWRP 3.7.0_9-0 `Format Data` can leave **f2fs** on userdata.
- LineageOS 22.2's fstab mounts `/data` as `ext4` with
  `fileencryption=ice,quota`. f2fs then fails with `invalid magic`, first
  stage leaves `/` read-only, apexd cannot create `/data/apex/sessions` and
  aborts, and `reboot_on_failure` restarts the phone in a loop. It looks like
  a bootloader fault but is a filesystem mismatch.
- Fix: in TWRP, **Wipe > Advanced Wipe > Data > Repair or Change File
  System > EXT4**, or from TWRP's terminal (this erases internal storage):

  ```sh
  mke2fs -t ext4 /dev/block/bootdevice/by-name/userdata
  ```

  Then check again; do not trust the previous "Format Data" result.
- Run `tools/axon7-preflight.sh --rom los22` before flashing. It reads the
  ext4/f2fs superblock magic read-only and refuses with the exact message if
  userdata is f2fs.

Nura and iOS do not use userdata this way, and LineageOS 24 uses `los_data`
in its own slot; the ext4 requirement is specific to the LineageOS 22.2
standalone layout.

## Replacing the dead PARTY tool with `sgdisk`

PARTY created the 512 MiB vendor partition from the **end of system**. The
same change can be made with TWRP's own `sgdisk`. **Use the phone's real
sector numbers**; the ones in examples are from another phone.

`/dev/block/sde` on the Axon 7 uses **4096-byte sectors**, so 512 MiB is
**131072 sectors**. The issue's formula is, with `S` = system start and
`E` = system end (before the change):

```sh
sgdisk -p /dev/block/sde        # read S (start) and E (end) for partition 13 "system"
S=...                           # the real numbers from the line above, never from another phone
E=...
sgdisk --backup=/sdcard/axon7-gpt.bin /dev/block/sde
sgdisk --delete=13 /dev/block/sde
sgdisk --new=13:$S:$((E-131072)) --change-name=13:system /dev/block/sde
sgdisk --new=28:$((E-131071)):$E --change-name=28:vendor /dev/block/sde
```

Then **reboot to recovery** so the kernel reloads the table. Notes:

- Check that partition 28 is free before creating it; if it exists, stop.
- The commands change only the GPT of `sde`. They do not touch boot,
  recovery, aboot/xbl/tz, modem, persist or EFS.
- The old ext4 filesystem on system is now larger than its partition. Wipe
  **System** before flashing (the ROM writes a fresh filesystem), or
  `e2fsck -f` + `resize2fs` it while it is unmounted. Do not boot a ROM from
  the shrunken partition without doing one of these.
- If the table write is interrupted, restore the backup:
  `sgdisk --load-backup=/sdcard/axon7-gpt.bin /dev/block/sde`.
- The vendor node must appear before flashing:
  `ls -l /dev/block/bootdevice/by-name/vendor` (TWRP also has the platform
  path `/dev/block/platform/soc/624000.ufshc/by-name/vendor`).

`tools/axon7-make-vendor.sh` does the sector arithmetic and all of the above
safety checks. It prints a **read-only plan by default**; `--apply --yes`
writes, after saving the old GPT. It refuses a non-4096-sector disk, an
unexpected partition layout, an occupied partition 28, or an existing vendor
partition. It never writes EFS/persist/modem/bootloader.

## Per-ROM status on A2017U

| ROM | A2017U notes |
| --- | --- |
| **iOS 16** (alpha) | Untested. The boot shim/iOS root are the same; unlock the bootloader first (the B35 no-fastboot route above), then follow [DEV-MULTIBOOT.md](../DEV-MULTIBOOT.md). GPU zap firmware is read from `vendor/firmware` or, without a vendor partition, from `system/vendor/firmware`; the guide already has that fallback. iOS has no cellular support on this port, so there is nothing to claim there. |
| **Nura** (mainline Linux) | Untested on U. It does not need fastboot or the vendor partition: `boot.img` and the microSD image go through TWRP, and at first start it copies firmware from the phone's `modem`, `vendor` (or `system`) partitions read-only. Use an **A2017U modem/firmware** base. Calls/SMS/data are unverified on the U; Nura's cellular status is independent of the model and still open. |
| **LineageOS 22.2** | The only ROM with an A2017U report: 22.2-20261109 boots (4 GB / 64 GB, Android 15, orange verified boot, TZ.BF.4.0.1-00353). Requires the Oreo bootstack, the 512 MiB vendor partition and **ext4** userdata. SIM/calls/data untested on U. Read [XDA-POST-LINEAGEOS.md](../XDA-POST-LINEAGEOS.md) and run the preflight. |
| **LineageOS 24** (mainline) | Untested on U. It is a multi-boot-only TWRP zip: it needs the `axon7-tripleboot-gpt` layout and a vendor partition for the GPU zap firmware (from LineageOS 16-18.1/22.2). Its own `ci/update-binary` already accepts `ailsa_ii`/`axon7`/`A2017U` and checks the partition sizes and read-back before touching anything. No radio HAL yet, so cellular is not applicable. |

## Before flashing: shared checks

```sh
tools/axon7-preflight.sh --rom los22     # or los24, nura, ios, generic
```

Read-only; exit 1 if it finds a blocker (f2fs where ext4 is required, missing
vendor, missing multi-boot partitions, wrong TZ for 22.2). Run it in TWRP or
as root. It is one script for all four ROMs, deliberately not copied into
each tree.

The hardware-only checks (real first boot, modem path, calls/SMS/data, TZ
effects) are in [to-test.md](../to-test.md), section "A2017U".

## Sources

Confirmed/project sources:

1. [LineageOS wiki: ZTE Axon 7 (axon7)](https://wiki.lineageos.org/devices/axon7/) and [install page](https://wiki.lineageos.org/devices/axon7/install/) — codename, TWRP/fastboot install, unlock guide link.
2. [TWRP for the Axon 7 (`ailsa_ii`)](https://dl.twrp.me/ailsa_ii/) — the recovery name all variants use.
3. [LineageOS 22.2 release notes](../lineageos-22.2/ci/release-notes.md), [FLASHING-PLAN.md](../lineageos-22.2/FLASHING-PLAN.md) and the device-tree patches in [`lineageos-22.2/port-22.2/`](../lineageos-22.2/port-22.2/) — TZ assert, ext4 `/data`, vendor requirement.
4. [Oki, \[TOOL\]\[TREBLE\] PARTY v0.5](https://xdaforums.com/t/tool-treble-party-v0-5-vendor-partition-manager-2018-08-31.3831517/) — 512 MB from the end of system is the recommended layout; the AFH `fid=1322778262903995063` download is dead.
5. [DrakenFX, A2017x universal bootstack thread](https://xdaforums.com/t/best-boostack-a2017g-or-universal-for-installing-pie-roms.4051497/) and [androidsage's LineageOS 15.1 article](https://www.androidsage.com/2018/06/06/lineage-os-15-1-for-axon-7-android-8-1-oreo-download/) — universal Oreo bootstack **plus a model-specific modem** (A2017/A2017G/A2017U).
6. [jcadduono, \[EDL\]\[A2017/A2017U\] Emergency DL Mode TWRP + Unlock + Upgrade](https://xdaforums.com/t/edl-a2017-a2017u-emergency-dl-mode-twrp-unlock-upgrade.3553514/) — the A2017U/A2017 EDL packages (`B15-NEW_TWRP_EDL`, `B15-NEW_FULL_EDL`, `FASTBOOT_UNLOCK_EDL`, `B29_TWRP_EDL`) are documented to "unlock fastboot operations"; explicit warning not to use them on A2017G.
7. [DrakenFX, unlock guide (A2017U/A2017)](https://xdaforums.com/t/guide-how-to-unlock-bootloader-stay-stock-a2017u-a2017.3461165/) — `fbop`/`aboot` backup and flash, `fastboot oem unlock`, data wipe.

Reported by the A2017U owner (unverified by us):

8. [devilAPI/zte-axon7 issue #1](https://github.com/devilAPI/zte-axon7/issues/1) — B35 has no fastboot; B15-NEW aboot+fbop via EDL; B29 not enough; bootstack overwrites recovery; TWRP 3.7 f2fs trap; dead PARTY link and the working `sgdisk` commands; 22.2 boot report and TZ; cellular untested.
