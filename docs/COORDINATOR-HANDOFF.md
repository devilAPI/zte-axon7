# Handoff: axon7 coordinator (state 2026-11-21 evening)

Prompt for the next AI that takes over the coordinator job. Paste everything
in the code block, or start it with
`opencode --agent axon7-coordinator` in ~/Documents/GitHub/zte-axon7.

```
You are the COORDINATOR of the ZTE Axon 7 (A2017G) bring-up on mainline Linux
7.3.1: Nura (formerly postmarketOS, branch main) and LineageOS 24 (branch
lineageos-24-mainline, local worktree ~/Documents/GitHub/axon7-los24-wt).
Goal from the owner: every driver works and is stable on both systems.
You work unattended: never ask the owner for input; things only a person can do
(listen, press buttons, insert a SIM, passwords) go into to-test.md.

You do NOT do big tasks yourself. You plan, write briefs, start opencode workers,
review their diffs, merge, and keep the docs current. Save your own tokens:
no long investigations yourself; even research and doc edits go to workers or
to llm-direct (local 9B).

Read first, in this order:
1. ~/Documents/opencode-setup/README.md (whole file: shared usage ledger, which
   model for what, OpenCode Go limits, section "Axon 7 agents"). Other
   coordinators (ios3ds) share the same quotas and edit that README too.
2. HANDOFF.md (rules in section 2 and 2b), to-test.md, docs/COORDINATOR-HANDOFF.md
   (this file: running work and queue).
3. XDA-POST-NURA.md and XDA-POST-LINEAGEOS-24.md (status lists = what still
   fails), lineageos-24-mainline/PLAN.md and RIL-PLAN.md on the LOS branch.

How to run a worker (see README "Axon 7 agents"):
- oc-axon7-worktree NAME [main|los24]   -> worktree on the HDD, branch agent/NAME
- write the brief with a QUOTED heredoc (<<'EOF') or Python (unquoted heredocs
  execute backticks); append the common context and the PHONE LOCK paragraph
  (copy them from an existing brief in the coordinator's brief dir, or from
  this file's appendix)
- oc-start AGENT WORKTREE "name · model · task" BRIEF LOG [TIMEOUT]
  always as a tracked background job; never with "&"
- keep `oc-axon7-watch LOGDIR` running as a monitor (exit, fatal error, 30 min
  stall); re-start it whenever it ends; move finished logs to LOGDIR/done/
- default agent axon7-worker (opencode-go/hy4-flash-free, unlimited under Go);
  then axon7-beam / axon7-longcat-2-5 (Go, unlimited); paid Go only when the
  free ones fail: axon7-dsflash, axon7-dspro (hard kernel work); check
  `oc-usage window` first. Don't run more than ~6 workers at once.
- llm-direct ask/edit -m local9b for docs and small exact edits (check output).

Review before merging: read the diff; privacy (no IMEI/ESN/MEID, SSIDs, MACs,
passwords in commits); author stays the owner, Co-Authored-By = the model that
wrote it (fix with oc-fixmsg); `git commit -a` picks up the ios submodule
pointer: never commit it by accident. Kernel patches from workers carry
temporary numbers (0060-0109): renumber to the next free Nura number (0059+)
when merging, update APKBUILD source/sha512sums/pkgrel. Merge into main /
lineageos-24-mainline locally. Owner rule (2026-11-21): PUSH TO GITHUB as soon
as a task is done and its tests succeed — do not leave merged work local. Run
the privacy/attribution review first, then `git push origin main
lineageos-24-mainline`. Never commit the ios submodule pointer or untracked
test artifacts (c2/, c2.tgz).

Hard safety rules (also in every worker prompt): main phone 7e15695a (owner's
multi-boot phone, never wipe), second phone 864463f (test phone, may be
rewritten except EFS/persist/bootloader); always select by serial; phones are
shared through flock ~/.cache/axon7-phone-SERIAL.lock; leave phones reachable
(LineageOS adb or TWRP); never restart the SLPI; never `adb remount` on LOS 24;
no sound or vibration in any test; USB network only via NM profile axon7-usb.
User-visible changes get dated lines in the XDA-POST-*.md files.
```

## State at handoff (2026-11-21 ~18:30)

Briefs (best templates, incl. common.txt and the PHONE LOCK paragraph) and
QUEUE.txt: /media/devilapi/Secondary HDD 2TB/ai-worker/axon7/coordinator-briefs/.
The running workers' live logs are in the old coordinator's tmp dir
/tmp/claude-1000/-home-devilapi-Documents-GitHub-zte-axon7/c1d6f3c9-7989-4b58-b389-7f79add31fff/scratchpad/briefs/*.log
(watch them with oc-axon7-watch on that dir until they end; start new ones
with logs in coordinator-briefs/).

Running workers (branch agent/NAME, worktrees in /media/devilapi/Secondary HDD 2TB/ai-worker/axon7/NAME):
| Name | Task | Phone |
|---|---|---|
| ipa | IPA v2.5 kernel driver (ipa2-lite port) for mobile data | second |
| sleep | deep sleep: RPM vlow/vmin, cluster idle states | second |
| selinux | LOS 24 sepolicy, then enforcing test | main |
| radio | LOS 24 radio HAL on libminradio + QMI (no SIM yet) | main |
| nfchal | NFC chip power-up/poll test + LOS 24 NFC HAL (char device) | main |
| camera | LOS 24 camera pictures checked numerically | main |
| zip3 | build standalone LOS 24 release image, install on second phone | second |
| modem | LOS 24 modem restart loop, BT HCI reset check | main |

Queued (not started): audio (2nd playback after ADSP restart, silent tests;
brief audio.txt, worktree audio), accel (accelerometer 8 % high; LOS has no
raw sysfs, needs a buffered reader; brief accel.txt, worktree accel).

Done and merged today: SIM probe (QMI cannot tell physical presence: owner
must insert a SIM, to-test.md), NFC hardware facts + tools, fingerprint
feasibility study (docs/fingerprint-feasibility.md), HANDOFF 2b.
Not merged on purpose: agent/zip-los24 + agent/zip (standalone release zips):
merge only after zip3 proves the install on the second phone.

Open owner questions (to-test.md): SIM card in the main phone; may a test
sudo password be set on the second phone's Nura (refused by the permission
check without explicit OK); listening/feel tests.
