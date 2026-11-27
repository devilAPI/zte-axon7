# Flash test 2026-11-27: stock-layout zip on the second Axon 7 (ABORTED)

Zip: lineage-22.2-20261126-UNOFFICIAL-axon7.zip, sha256 55112f26...581cc8 (verified after copy).
Phone: second Axon 7 in TWRP 3.3.1-0, ZTE stock partition table.

| Check | Result |
|---|---|
| by-name: system (6442450944 B), boot (67108864 B = 64 MiB), no vendor | PASS |
| updater-script has A2017U/A2017 model strings | FAIL: assert only checks ro.product.device / ro.build.product == ailsa_ii or axon7 (no model-string check) |
| axon7-layout.sh prints "Layout: stock", exit 0 | FAIL: exit 1, "system is 6442450944 bytes; the ROM image needs 5905580032" |
| Flash / boot / stability checks | NOT RUN (stopped before writing anything; phone untouched, still in TWRP) |

## Bug found

In TWRP 3.3.1's shell (BusyBox 1.22.1) `[ A -ge B ]` with values above 2^32 compares wrongly:
`[ 6442450944 -ge 5905580032 ]` is false, as is `-gt`. `$((a-b))` is fine (64-bit). So the
layout check rejects a 6 GiB system partition that is big enough, and the installer would abort
with E3010 before writing (safe, but the zip cannot install on this phone as built).

Workarounds verified on the phone: `[ $((a/1048576)) -ge $((b/1048576)) ]` and
`[ "$((a>=b))" = 1 ]` both return true. Apply to every byte comparison in
ci/axon7-layout.sh (boot_b, sys_b). ci/test-layout.sh runs on the PC's 64-bit shell,
which is why it did not catch this.
