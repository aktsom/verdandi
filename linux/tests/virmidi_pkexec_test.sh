#!/bin/bash
# linux/tests/virmidi_pkexec_test.sh: lua/core/virmidi.lua start_load / load_status / load_detail with a REAL shell and a FAKE pkexec (a script on the PATH that
# waits, then loads the "module" (a folder), exits with a code, hangs, or is not there): the page's state follows what the command does, in the background, and ends
# in "ok" (loaded), a plain failure reason (cancelled, no agent, modprobe failed, timeout, no pkexec). prints "name: ok" / "name: FAIL ...", exit 1 if any failed.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/sys"
cat > "$T/bin/pkexec" <<'FAKE'
#!/bin/sh
# the fake polkit client: pkexec modprobe snd-virmidi midi_devs=1. FAKE_MODE (file) says what the person does at the dialog
mode="$(cat "$FAKE_DIR/mode")"
echo "$@" > "$FAKE_DIR/pkexec.args"
case "$mode" in
ok) sleep 1; mkdir -p "$FAKE_DIR/sys/snd_virmidi"; echo live > "$FAKE_DIR/sys/snd_virmidi/initstate"; exit 0 ;;
cancel) sleep 1; exit 126 ;;
agent) sleep 1; exit 127 ;;
fail) sleep 1; exit 1 ;;
slow) sleep 30; exit 0 ;;
esac
FAKE
chmod +x "$T/bin/pkexec"
FAIL=0
ok() { echo "$1: ok"; }
bad() { echo "$1: FAIL $2"; FAIL=1; }
run_case() { # name mode path-with-pkexec(1|0) expected
    local name="$1" mode="$2" have="$3" want="$4" out
    rm -rf "$T/sys/snd_virmidi" "$T/done" "$T/status"
    echo "$mode" > "$T/mode"
    if [ "$have" = 1 ]; then P="$T/bin:/usr/bin:/bin"; else P="/usr/bin:/bin"; fi
    out="$(cd "$REPO" && FAKE_DIR="$T" PATH="$P" lua5.3 linux/tests/virmidi_pkexec_driver.lua "$T" 2>&1)"
    if printf '%s\n' "$out" | grep -qx "RESULT $want"; then ok "$name"; else bad "$name" "$(printf '%s\n' "$out" | tr '\n' '|')"; fi
}
run_case "the person enters the password and modprobe loads the module: running first, then ok, loaded, with no key pressed" ok 1 "ok loaded after-running"
run_case "the dialog is closed: failed, cancelled" cancel 1 "failed cancelled after-running"
run_case "no authentication agent: failed, no_agent" agent 1 "failed no_agent after-running"
run_case "modprobe fails: failed, modprobe" fail 1 "failed modprobe after-running"
run_case "nobody answers (the command hangs past its time): failed, timeout" slow 1 "failed timeout after-running"
run_case "no pkexec on this machine: nothing started, failed, no_pkexec" ok 0 "failed no_pkexec"
grep -q "modprobe snd-virmidi midi_devs=1" "$T/pkexec.args" 2> /dev/null && ok "pkexec is asked for 'modprobe snd-virmidi midi_devs=1' (the last pkexec run)" || bad "pkexec args" "$(cat $T/pkexec.args 2>&1)"
exit $FAIL
