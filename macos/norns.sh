#!/bin/bash
# norns on macOS: start jack (coreaudio), sclang and norns with HOME set to the norns home.
#
# layout (same as /home/we on the device):
#   <norns home>/norns          this repository
#   <norns home>/dust           scripts, audio, data
#   <norns home>/matronrc.lua   written on first start (desktop screen)
#
#   <norns home>/Library/Application Support/SuperCollider   sclang config + extensions
#
# usage: macos/norns.sh
#   matron's lua REPL is this terminal; sclang's REPL is ws://localhost:5556 (maiden).

set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
NORNS_HOME="$(dirname "$REPO")"
DEPS="${NORNS_DEPS:-}"
if [ -z "$DEPS" ]; then
    d="$REPO"
    while [ "$d" != "/" ] && [ ! -d "$d/deps/prefix" ]; do d="$(dirname "$d")"; done
    DEPS="$d/deps/prefix"
fi
BREW="${HOMEBREW_PREFIX:-/opt/homebrew}"
JACK_RATE="${NORNS_JACK_RATE:-48000}"
JACK_PERIOD="${NORNS_JACK_PERIOD:-256}"

export HOME="$NORNS_HOME"
SC_BIN="$DEPS/SuperCollider/SuperCollider.app/Contents/MacOS"
# build/macos: jack_connect / jack_disconnect / jack_lsp (Crone.sc and scripts call them).
# gnubin: the norns core and scripts shell out to GNU tools (find -printf, stat -c, sed -i,
# sha256sum, timeout, shuf ...), as on the device; only norns' own processes see them.
GNUBIN=""
for f in coreutils findutils gnu-sed grep; do
    [ -d "$BREW/opt/$f/libexec/gnubin" ] && GNUBIN="$GNUBIN$BREW/opt/$f/libexec/gnubin:"
done
export PATH="$REPO/build/macos:$GNUBIN$DEPS/bin:$BREW/bin:$PATH"
# we start jackd ourselves; clients must not autostart a second server
export JACK_NO_START_SERVER=1
cd "$NORNS_HOME"

mkdir -p dust/code dust/audio dust/data
if [ ! -f matronrc.lua ]; then
    cat > matronrc.lua <<'EOF'
-- macOS desktop: the norns window (screen:sdl). keys/encoders: click / scroll in the
-- left, middle, right third of the window. the computer keyboard is the norns keyboard.
_boot.add_io('screen:sdl', {})
EOF
fi

SC_CONF="$NORNS_HOME/Library/Application Support/SuperCollider"
mkdir -p "$SC_CONF/Extensions"
if [ ! -f "$SC_CONF/sclang_conf.yaml" ]; then
    # the include paths norns-config.sc sets up on the device
    cat > "$SC_CONF/sclang_conf.yaml" <<EOF
includePaths:
    - "$NORNS_HOME/norns/sc/core"
    - "$NORNS_HOME/norns/sc/engines"
    - "$NORNS_HOME/dust"
excludePaths:
    []
postInlineWarnings: false
EOF
fi

# processes we started (bash 3.2: no negative indices, no empty arrays under set -u)
PIDS=""
cleanup() {
    for p in $PIDS; do kill "$p" 2>/dev/null; done
    # sclang (under ws-wrapper) and its scsynth are not our direct children
    pkill -f "$SC_BIN/sclang" 2>/dev/null
    pkill -f "$SC_BIN/scsynth" 2>/dev/null
    wait 2>/dev/null
}
trap cleanup EXIT INT TERM

JACK_WAIT="$REPO/build/macos/jack_wait"
if ! "$JACK_WAIT" 0 2>/dev/null; then
    echo "norns.sh: starting jackd (coreaudio, ${JACK_RATE} Hz, period ${JACK_PERIOD})"
    # helpers get /dev/null as stdin: they share the file description with matron's REPL,
    # and one that flips it to non-blocking makes matron's reads fail
    jackd -d coreaudio -r "$JACK_RATE" -p "$JACK_PERIOD" < /dev/null > "$NORNS_HOME/jackd.log" 2>&1 &
    PIDS="$PIDS $!"
    "$JACK_WAIT" 10 || { echo "norns.sh: jackd did not start, see $NORNS_HOME/jackd.log"; exit 1; }
fi

# explicit <&0: a non-interactive shell gives background jobs /dev/null as stdin,
# which would leave matron's lua REPL without input
"$REPO/build/norns/norns" <&0 &
NORNS_PID=$!
PIDS="$PIDS $NORNS_PID"
# sclang wires scsynth into crone's jack ports, so wait for crone
n=0
until jack_lsp 2>/dev/null | grep -q '^crone:input_5$'; do
    n=$((n + 1))
    if [ $n -gt 50 ] || ! kill -0 "$NORNS_PID" 2>/dev/null; then
        echo "norns.sh: crone did not come up, sclang not started"
        break
    fi
    sleep 0.2
done
if jack_lsp 2>/dev/null | grep -q '^crone:input_5$'; then
    "$REPO/build/ws-wrapper/ws-wrapper" "ws://*:5556" "$SC_BIN/sclang" -i maiden < /dev/null > "$NORNS_HOME/sclang.log" 2>&1 &
    PIDS="$PIDS $!"
fi

wait "$NORNS_PID"
