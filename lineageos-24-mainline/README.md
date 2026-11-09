# LineageOS 24 (Android 17) on mainline Linux for the ZTE Axon 7

Developer work in progress, nothing to flash yet. The plan, decisions and
sources: [PLAN.md](PLAN.md). The 4.4-kernel LineageOS 22.2 port is in
[../lineageos-22.2](../lineageos-22.2); the mainline kernel comes from Nura
([../postmarketos](../postmarketos)).

| Path | Contents |
| --- | --- |
| `PLAN.md` | plan: LineageOS 24 facts, prior art, kernel/boot/partitions, HAL per hardware block, milestones, risks |
| `kernel/android-axon7m.config` | Android config fragment merged over Nura's kernel config |
| `kernel/patches/` | Android-specific kernel patches on top of Nura's series (none yet) |
| `scripts/kernel-build.sh` | server: build the 7.3.1 + Nura kernel with the fragment, stage Image/DTB/modules |
| `scripts/kernel-config-check.sh` | lists fragment options that did not land in the final .config |
| `scripts/server-sync-device.sh` | PC: copy these files to the server and into the Android tree |
| `device/zte/axon7m/` | LineageOS device tree (codename `axon7m`) |
| `manifest/axon7m.xml` | repo local manifest |

## Build server (`root@compiler`, user `build`)

| What | Where | How |
| --- | --- | --- |
| LineageOS 24.0 source | `/srv/los24/lineage-24.0` (depth 1) | `tmux new -d -s los24sync /srv/los24/sync.sh`, log `/srv/los24/logs/repo-sync.log` (rerun to resume) |
| Kernel tree | `/srv/los24/kernel/linux` (v7.3.1 + Nura 0001-0018, branch `axon7-android`) | `/srv/los24/axon7/repo/lineageos-24-mainline/scripts/kernel-build.sh [setup\|config\|build\|stage\|all]`, log `/srv/los24/logs/kernel-build.log` |
| Kernel output | `/srv/los24/kernel/out`, staged in `/srv/los24/kernel/prebuilt` | |
| Reference trees | `/srv/los24/ref` | outside the Android tree on purpose |

`/srv/aosp` (LineageOS 22.2) is not touched by any of this.

Android build (once the sync is done; first build about 4-6 h, later ones
much less):

```sh
lineageos-24-mainline/scripts/server-sync-device.sh       # on the PC
ssh root@compiler
su - build
cd /srv/los24/lineage-24.0 && source build/envsetup.sh
breakfast axon7m            # or: lunch lineage_axon7m-<release>-userdebug
m bootimage recoveryimage   # M0
m                           # M1: super.img etc.
```
