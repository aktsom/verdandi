#!/usr/bin/env bash
# linux/tests/scsynth_bridge_test.sh: scsynth with the Verdandi bridge driver (windows/patches/scsynth-null-audio.patch), against the bridge host of norns.exe (bridge_host_tool.c), on Linux.
# the patched scsynth is not built by run_all.sh (it takes a build of SuperCollider): set VERDANDI_SCSYNTH to one (and VERDANDI_SC_PLUGINS to a folder of UGen plug-ins) or the test says SKIP.
# what it proves: scsynth opens no device; waits for the bridge; takes the host's block as its input bus, plays a SynthDef (440 Hz sine plus its input) and hands the result back, so that the host's
# output holds 0.2 (the input passed through) plus a 0.5 sine at 440 Hz; with no bridge it falls back to the null clock and still answers /status.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
SCSYNTH="${VERDANDI_SCSYNTH:-}"
PLUGINS="${VERDANDI_SC_PLUGINS:-/usr/lib/SuperCollider/plugins}"
if [ -z "$SCSYNTH" ] || [ ! -x "$SCSYNTH" ] || [ ! -d "$PLUGINS" ]; then
    echo "SKIP: set VERDANDI_SCSYNTH to a scsynth built with windows/patches/scsynth-null-audio.patch (and VERDANDI_SC_PLUGINS)"
    exit 0
fi
T="$(mktemp -d)"
pids=""
# shellcheck disable=SC2329
cleanup() { for p in $pids; do kill "$p" 2> /dev/null; done; rm -rf "$T"; }
trap cleanup EXIT
fail=0
ck() { if eval "$2"; then echo "  ok    $1"; else echo "  FAIL  $1"; fail=1; fi; }
gcc -std=gnu11 -O1 -I "$REPO/matron/src/platform/windows" "$HERE/bridge_host_tool.c" -lm -lrt -o "$T/host" || exit 1
python3 "$HERE/mk_bridge_synthdef.py" "$T/vd_bridge_test.scsyndef" || exit 1
PORT=$(python3 -I -c 'import socket;s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);s.bind(("127.0.0.1",0));print(s.getsockname()[1])')
osc() { python3 - "$PORT" "$@" << 'PY'
import socket, struct, sys
def pad(b): return b + b"\0" * (4 - len(b) % 4)
port = int(sys.argv[1]); addr = sys.argv[2]; args = sys.argv[3:]
tags = ","; data = b""
for a in args:
    if a.lstrip("-").isdigit(): tags += "i"; data += struct.pack(">i", int(a))
    else: tags += "s"; data += pad(a.encode())
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.sendto(pad(addr.encode()) + pad(tags.encode()) + data, ("127.0.0.1", port))
PY
}

echo "== with the bridge"
NAME="vd-test-$$"
"$T/host" "$NAME" 14 > "$T/host.out" 2>&1 &
hostpid=$!
pids="$pids $hostpid"
sleep 0.5
VERDANDI_BRIDGE="$NAME" timeout 40 "$SCSYNTH" -u "$PORT" -a 64 -i 2 -o 2 -z 64 -U "$PLUGINS" > "$T/sc.log" 2>&1 &
pids="$pids $!"
for _ in $(seq 1 40); do grep -q "the first block was computed" "$T/sc.log" 2> /dev/null && break; sleep 0.25; done
osc /d_load "$T/vd_bridge_test.scsyndef"
sleep 0.7
osc /s_new vd_bridge_test 1000 0 0
wait "$hostpid"
cat "$T/host.out"
ck "scsynth used the bridge driver, not an audio device" "grep -q 'SC_BridgeAudioDriver: audio from norns.exe' '$T/sc.log' && ! grep -q 'Device options' '$T/sc.log'"
ck "the sample rate and block size are the host's (48000, 512)" "grep -q 'Sample rate: 48000.000, block size: 512' '$T/sc.log'"
ck "the host's input arrived on scsynth's input bus (mean 0.2)" "grep -q 'mean 0.2' '$T/host.out'"
ck "the sine of the SynthDef came back (peak 0.5, 440 Hz)" "grep -q 'peak 0.50' '$T/host.out' && grep -Eq 'freq (43[0-9]|44[0-9])\.' '$T/host.out'"
ck "no underruns or drops" "grep -q 'underruns 0 drops 0' '$T/host.out'"
ck "scsynth noticed that the host closed the bridge" "sleep 1; grep -q 'norns.exe has closed the bridge' '$T/sc.log'"
# shellcheck disable=SC2046
kill $(jobs -p) 2> /dev/null

echo "== without the bridge (norns.exe is not there)"
PORT2=$((PORT + 1))
VERDANDI_BRIDGE="vd-missing-$$" VERDANDI_BRIDGE_WAIT=1 timeout 15 "$SCSYNTH" -u "$PORT2" -a 64 -i 2 -o 2 -z 64 -U "$PLUGINS" > "$T/sc2.log" 2>&1 &
pids="$pids $!"
sleep 4
ck "it says the bridge was not found and falls back to the null driver" "grep -q 'was not found' '$T/sc2.log' && grep -q 'SC_NullAudioDriver: no audio device is used' '$T/sc2.log'"
ck "and the server is up (answers /status)" "python3 '$REPO/windows/ci/osc_status.py' $PORT2 > '$T/st.out' 2>&1"
exit $fail
