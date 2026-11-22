#!/bin/bash
# Off-device tests for axon7-audio-kick (fake sysfs/proc, fake timeout).
# Usage: test-audio-kick.sh [path-to-axon7-audio-kick]
set -u
SRC=${1:-$(dirname "$0")/../postmarketos/pmaports-local/device/testing/device-zte-axon7/axon7-audio-kick}
SRC=$(realpath "$SRC")
T=$(mktemp -d /tmp/audio-kick-test.XXXXXX)
trap 'rm -rf "$T"' EXIT
pass=0 fail=0

ok() { pass=$((pass + 1)); echo "PASS: $*"; }
no() { fail=$((fail + 1)); echo "FAIL: $*"; }
check() { if eval "$2"; then ok "$1"; else no "$1"; fi; }
rc() { cat "$T/rc"; }
has() { grep -q -- "$1" "$T/out"; }

# --- fake commands ---------------------------------------------------------
mkdir -p "$T/bin"
cat > "$T/bin/sleep" <<'EOF'
#!/bin/sh
: # the tests must not wait
EOF
cat > "$T/bin/timeout" <<'EOF'
#!/bin/sh
# fake timeout: first arg is the limit, the rest is the command.
# AXON7_TEST_MODE decides what stopping/starting the ADSP does.
R=$AXON7_TEST_ROOT
shift
case "$*" in
*"echo stop"*)
	case $AXON7_TEST_MODE in
	blocked) exit 124 ;;
	*) printf 'offline\n' > "$R/sys/class/remoteproc/remoteproc2/state" ;;
	esac ;;
*"echo start"*)
	[ "$AXON7_TEST_MODE" = nostart ] && exit 0
	printf 'running\n' > "$R/sys/class/remoteproc/remoteproc2/state"
	mkdir -p "$R/proc/asound"
	printf ' 0 [Z7]: apq8096 - ZTE Axon 7\n' > "$R/proc/asound/cards"
	printf '00-01: MultiMedia2 : playback 1 : capture 1\n' > "$R/proc/asound/pcm" ;;
esac
exit 0
EOF
cat > "$T/bin/loginctl" <<'EOF'
#!/bin/sh
exit 1 # no user session in the tests
EOF
chmod 755 "$T/bin/sleep" "$T/bin/timeout" "$T/bin/loginctl"

mkroot() {
	R="$T/root"
	rm -rf "$R"
	mkdir -p "$R/sys/class/remoteproc/remoteproc2" "$R/run" \
		"$R/sys/bus/slimbus/drivers/ak4961-slim/1dd:4961:2:0" "$R/proc/asound"
	printf 'adsp\n' > "$R/sys/class/remoteproc/remoteproc2/name"
	printf 'running\n' > "$R/sys/class/remoteproc/remoteproc2/state"
	printf ' 0 [Z7]: apq8096 - ZTE Axon 7\n' > "$R/proc/asound/cards"
	printf '00-01: MultiMedia2 : playback 1 : capture 1\n' > "$R/proc/asound/pcm"
}
noroot() { rm -f "$R/proc/asound/cards" "$R/proc/asound/pcm"; }

run() { # mode [extra VAR=VALUE ...]
	mode=$1; shift
	env PATH="$T/bin:$PATH" AXON7_AUDIO_ROOT="$R" AXON7_TEST_ROOT="$R" \
		AXON7_TEST_MODE="$mode" AXON7_AUDIO_CARD_WAIT=2 AXON7_AUDIO_TICK=1 \
		AXON7_AUDIO_STOP_WAIT=2 AXON7_AUDIO_BOOT_WAIT=2 "$@" \
		sh "$SRC" > "$T/out" 2>&1
	echo $? > "$T/rc"
}

# --- 1: a usable card: nothing is touched --------------------------------
mkroot
run ok
check "ready: exit 0" '[ "$(rc)" = 0 ]'
check "ready: no ADSP stop" '! has "stopping the ADSP"'
check "ready: no ADSP start" '! has "starting the ADSP"'

# --- 2: no card -> stop/start, card appears ------------------------------
mkroot; noroot
run ok
check "restart: exit 0" '[ "$(rc)" = 0 ]'
check "restart: stopped once" '[ "$(grep -c "stopping the ADSP" "$T/out")" = 1 ]'
check "restart: started once" '[ "$(grep -c "starting the ADSP" "$T/out")" = 1 ]'
check "restart: state running" '[ "$(cat "$R/sys/class/remoteproc/remoteproc2/state")" = running ]'
check "restart: reported usable" 'has "sound card usable after 1 ADSP restart"'

# --- 3: the stop blocks (open fd): never start ---------------------------
mkroot; noroot
run blocked
check "blocked stop: non-zero exit" '[ "$(rc)" != 0 ]'
check "blocked stop: stop attempted" 'has "stopping the ADSP"'
check "blocked stop: stop timeout logged" 'has "stop did not finish"'
check "blocked stop: no start" '! has "starting the ADSP"'
check "blocked stop: state unchanged" '[ "$(cat "$R/sys/class/remoteproc/remoteproc2/state")" = running ]'

# --- 4: card open -> refuse to stop --------------------------------------
mkroot; noroot
run ok AXON7_AUDIO_SND_BUSY=1
check "busy: non-zero exit" '[ "$(rc)" != 0 ]'
check "busy: no stop" '! has "stopping the ADSP"'
check "busy: logged in use" 'has "leaving the ADSP alone"'
check "busy: no start" '! has "starting the ADSP"'

# --- 5: stop works, the ADSP does not come back --------------------------
mkroot; noroot
run nostart
check "start fails: non-zero exit" '[ "$(rc)" != 0 ]'
check "start fails: logged not running" 'has "not running"'

# --- 6: --check ----------------------------------------------------------
mkroot
env PATH="$T/bin:$PATH" AXON7_AUDIO_ROOT="$R" sh "$SRC" --check > "$T/out" 2>&1
r=$?
check "check ready: exit 0" '[ "$r" = 0 ]'
check "check ready: says ready" 'has "the sound card is ready"'
noroot
env PATH="$T/bin:$PATH" AXON7_AUDIO_ROOT="$R" sh "$SRC" --check > "$T/out" 2>&1
r=$?
check "check not ready: exit 1" '[ "$r" = 1 ]'
check "check not ready: says NOT ready" 'has "the sound card is NOT ready"'

echo "----"
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
