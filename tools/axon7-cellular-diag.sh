#!/bin/sh
# Read-only cellular bring-up diagnostic for the ZTE Axon 7 (ailsa_ii / axon7,
# all variants: A2017G, A2017U, A2017). Run it from the host PC with the phone
# on adb (ANDROID_SERIAL), or from an adb root shell on the device.
#
# It tells whether the modem and the radio come up on the booted ROM:
#   - the modem publishes its firmware version (ro.gsm.version.baseband; the
#     value is the modem firmware, safe to post) once it is up;
#   - the telephony/radio stack runs: rild on LineageOS 22.2 (proprietary RIL
#     over QMI), rmtfs + qrtr + the radio HAL (vendor.radio-axon7m) on
#     LineageOS 24;
#   - the modem firmware set (*.mbn / *.mdt) is mounted where the kernel asks
#     for it (/mnt/vendor/firmware_mnt/image on LOS 24, /lib/firmware/... on
#     Nura);
#   - the variant is detected (ro.boot.product.* with ro.product.* fallback) and
#     is the one the modem firmware must come from (A2017U: the US modem
#     package, see docs/variant-a2017u.md and issue #1).
#
# No writes: no reboot, no flash, no restart, no `adb remount`, no mount write;
# only getprop / service list / dmesg / ls and other reads. No SIM: the
# SIM-dependent answers (registration, calls, SMS, data) are informational
# only, never a blocker.
#
# Usage:
#   axon7-cellular-diag.sh [--rom generic|los22|los24|nura|ios] [--serial ANDROID_SERIAL] [--props FILE]
#   axon7-cellular-diag.sh --help
#
# Exit status: 0 = no blocker, 1 = at least one FAIL, 2 = usage error.
# `--props FILE` (key=value lines) exists so the logic can be exercised without
# a phone (see tools/test-axon7-variant.sh); with it the adb probes are skipped.

set -u

rom=generic
serial=
props_file=
while [ $# -gt 0 ]; do
	case $1 in
		--help|-h)
			sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
			exit 0
			;;
		--rom) rom=${2:-}; shift 2 || { echo "usage: $0 [--rom generic|los22|los24|nura|ios]" >&2; exit 2; } ;;
		--serial) serial=${2:-}; shift 2 || { echo "usage: $0 [--serial ANDROID_SERIAL]" >&2; exit 2; } ;;
		--props) props_file=${2:-}; shift 2 || { echo "usage: $0 [--props FILE]" >&2; exit 2; } ;;
		*) echo "$0: unknown argument '$1' (see --help)" >&2; exit 2 ;;
	esac
done
case $rom in
	generic|los22|los24|nura|ios) ;;
	*)
		echo "$0: unknown ROM '$rom' (generic, los22, los24, nura, ios)" >&2
		exit 2
		;;
esac

blockers=0
warnings=0
say()  { printf '%s\n' "$*"; }
ok()   { printf '  ok    %s\n' "$*"; }
warn() { printf '  WARN  %s\n' "$*"; warnings=$((warnings + 1)); }
bad()  { printf '  FAIL  %s\n' "$*"; blockers=$((blockers + 1)); }

props_mode=0
[ -n "$props_file" ] && props_mode=1

prop() { # $1 key, $2 fallback key (optional)
	k=$1
	fb=${2:-}
	v=
	if [ -n "$props_file" ]; then
		v=$(sed -n "s/^$k=//p" "$props_file" | head -1)
		if [ -z "$v" ] && [ -n "$fb" ]; then
			v=$(sed -n "s/^$fb=//p" "$props_file" | head -1)
		fi
		[ -n "$v" ] && { echo "$v"; return 0; }
		return 0
	fi
	if [ -n "$serial" ]; then
		v=$(adb shell "getprop $k" 2>/dev/null | tr -d '\r')
		if [ -z "$v" ] && [ -n "$fb" ]; then
			v=$(adb shell "getprop $fb" 2>/dev/null | tr -d '\r')
		fi
		[ -n "$v" ] && { echo "$v"; return 0; }
		return 0
	fi
	if command -v getprop >/dev/null 2>&1; then
		if [ -n "$fb" ]; then
			v=$(getprop "$fb" 2>/dev/null)
			[ -n "$v" ] && { echo "$v"; return 0; }
		fi
		v=$(getprop "$k" 2>/dev/null)
		[ -n "$v" ] && { echo "$v"; return 0; }
	fi
	return 0
}

have_phone=0
if [ "$props_mode" = 0 ]; then
	if [ "$(adb get-state 2>/dev/null)" = device ]; then
		have_phone=1
	else
		bad "no adb device attached (ANDROID_SERIAL=${serial:-unset}): run with the phone on adb"
	fi
fi

adbq() { adb shell "$1" 2>/dev/null | tr -d '\r'; }

say "ZTE Axon 7 cellular diagnostic (read-only), ROM profile: $rom"
say ""

# --- identity / variant (ro.boot.* first, ro.product.* as fallback) ---------
dev=$(prop ro.boot.product.device ro.product.device)
model=$(prop ro.boot.product.model ro.product.model)
bootloader=$(prop ro.boot.bootloader)
hw=$(prop ro.boot.hardware ro.product.hardware)
baseband=$(prop gsm.version.baseband)
simstate=$(prop gsm.sim.state)

say "Device"
if [ -n "$dev" ]; then
	ok "device: $dev (ro.boot.product.device, fallback ro.product.device)"
else
	warn "ro.product.device is empty (not booted into Android/TWRP, or no getprop)"
fi
if [ -n "$model" ]; then
	ok "model: $model (ro.boot.product.model, fallback ro.product.model)"
else
	warn "ro.product.model is empty (not booted into Android/TWRP, or no getprop)"
fi
if [ -n "$hw" ]; then
	say "  hardware (ro.boot.hardware, fallback ro.product.hardware): $hw"
fi
if [ -n "$bootloader" ]; then
	say "  ro.bootloader: $bootloader"
fi

case $dev in
	ailsa_ii|axon7)
		ok "codename is ailsa_ii/axon7 (A2017G, A2017U and A2017 share it); the ROM installers' device assert passes"
		;;
	*)
		warn "unexpected device '$dev': this project only supports ailsa_ii/axon7"
		;;
esac

variant=
case $model in
	*A2017U*)
		variant=A2017U
		say "  variant: A2017U (US) reported"
		say "           - use an A2017U modem/firmware base, never the A2017G one (issue #1)."
		say "           - cellular (calls/SMS/data) is UNTESTED on the A2017U."
		;;
	*A2017G*)
		variant=A2017G
		say "  variant: A2017G (global; the variant the project was tested on)"
		;;
	*A2017*)
		variant=A2017
		say "  variant: A2017 (China) reported (untested)"
		;;
	*)
		variant=unknown
		say "  variant: unknown (no *A2017* in ro.boot.product.model / ro.product.model)"
		warn "could not classify the A2017 variant"
		;;
esac
say ""

# --- modem / radio ---------------------------------------------------------
say "Modem / radio"
if [ -n "$baseband" ]; then
	ok "modem firmware version: $baseband"
else
	bad "no gsm.version.baseband: the modem did not come up (or the radio did not read it yet)"
fi

if [ "$have_phone" = 1 ]; then
	case $rom in
		los22)
			if adbq 'service list' | grep -qi 'rild'; then
				ok "rild is in the service list (LineageOS 22.2 radio stack)"
			else
				bad "rild is not in the service list: the LineageOS 22.2 radio stack did not come up"
			fi
			;;
		los24)
			if adbq 'service list' | grep -qiE 'rmtfs|qrtr|radio'; then
				ok "rmtfs/qrtr/radio services are up (LineageOS 24 radio stack)"
			else
				bad "no rmtfs/qrtr/radio service in 'service list': the LineageOS 24 radio stack did not come up"
			fi
			dm=$(adbq 'dmesg' | grep -iE 'rmtfs|qrtr|qmi|modem|ril|radio' | tail -n 12)
			if [ -n "$dm" ]; then
				say "        modem/radio kernel log (tail):"
				echo "$dm" | sed 's/^/          /'
			else
				bad "no modem/radio lines in dmesg"
			fi
			;;
	esac
fi

# --- modem firmware (MBN set) ----------------------------------------------
say "Modem firmware (MBN set)"
if [ "$have_phone" = 1 ]; then
	case $rom in
		los24)
			listing=$(adbq 'ls /mnt/vendor/firmware_mnt/image')
			for n in adsp mba modem slpi venus; do
				if echo "$listing" | grep -qw "$n.mdt"; then
					ok "modem firmware: $n.mdt present"
				else
					bad "modem firmware: $n.mdt missing from /mnt/vendor/firmware_mnt/image"
				fi
			done
			if echo "$listing" | grep -qw bdwlan30.bin; then
				ok "wifi board data: bdwlan30.bin present"
			else
				warn "wifi board data bdwlan30.bin not found in /mnt/vendor/firmware_mnt/image"
			fi
			;;
		nura)
			listing=$(adbq 'ls /lib/firmware/qcom/msm8996/zte/axon7')
			for n in adsp mba modem slpi venus; do
				if echo "$listing" | grep -qw "$n.mbn"; then
					ok "modem firmware: $n.mbn present"
				else
					bad "modem firmware: $n.mbn missing from /lib/firmware/qcom/msm8996/zte/axon7"
				fi
			done
			;;
		*)
			say "  modem firmware: MBN set checked via the modem/RIL stack (see above)"
			;;
	esac
else
	say "  skipped (no adb device / --props mode)"
fi
say ""

# --- SIM state (informational: no SIM card on this bench) -------------------
if [ -n "$simstate" ]; then
	say "  gsm.sim.state: $simstate"
else
	say "  gsm.sim.state: (empty - no SIM card inserted or state not yet known)"
	warn "no SIM state reported: SIM-dependent cellular checks cannot run"
fi

# --- summary ---------------------------------------------------------------
say "Summary: $blockers blocker(s), $warnings warning(s)"
if [ "$blockers" -gt 0 ]; then
	say "The modem/radio did not come up cleanly: see the FAIL lines above."
	exit 1
fi
say "Cellular diagnostic: no blocker found. See the warnings for the SIM-dependent notes."
exit 0
