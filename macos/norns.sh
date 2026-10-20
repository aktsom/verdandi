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
#   <norns home>/maiden         maiden (web editor, REPLs, catalog), if installed
#
# usage: macos/norns.sh [--terminal]
#   default: like the device, matron and sclang REPLs are websockets (127.0.0.1:5555/5556)
#            used by maiden at http://127.0.0.1:5000/maiden; matron logs to norns.log
#   --terminal: matron's lua REPL and log are this terminal
#   everything listens on 127.0.0.1 only: these REPLs run arbitrary code.

set -u

TERMINAL=0
[ "${1:-}" = "--terminal" ] && TERMINAL=1

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
if [ -d "$DEPS/gnubin" ]; then
    GNUBIN="$DEPS/gnubin:" # app bundle
else
    for f in coreutils findutils gnu-sed grep; do
        [ -d "$BREW/opt/$f/libexec/gnubin" ] && GNUBIN="$GNUBIN$BREW/opt/$f/libexec/gnubin:"
    done
fi
# bundled jack drivers (app bundle); homebrew's jackd knows its own
[ -d "$DEPS/lib/jack" ] && export JACK_DRIVER_DIR="$DEPS/lib/jack"
if [ -d "$DEPS/gnubin" ]; then
    # app bundle: only what it brings (and the system)
    export PATH="$REPO/build/macos:$GNUBIN$DEPS/bin:$PATH"
else
    export PATH="$REPO/build/macos:$GNUBIN$DEPS/bin:$BREW/bin:$PATH"
fi
# we start jackd ourselves; clients must not autostart a second server
export JACK_NO_START_SERVER=1
# no norns hardware: the keyboard drives K1-3 / E1-3 when nothing else wants the keys
# (lua/core/keyboard.lua)
export NORNS_HARDWARE_KEYS=1
# the lua core hides device-only menus (wifi, update)
export NORNS_PLATFORM=macos
# dock icon of the norns window
export NORNS_ICON="$REPO/macos/norns-icon.png"
cd "$NORNS_HOME"

mkdir -p dust/code dust/audio dust/data
if [ ! -f matronrc.lua ]; then
    cat > matronrc.lua <<'EOF'
-- macOS desktop: the norns window (screen:sdl). keys/encoders: 1 2 3 and QW AS ZX on the
-- keyboard (see readme-macos.md), or click / scroll in the left, middle, right third.
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

# one norns at a time: a second one finds the OSC / REPL ports taken
if pgrep -x norns >/dev/null; then
    echo "norns.sh: norns is already running (close its window first)"
    exit 1
fi

# processes we started (bash 3.2: no negative indices, no empty arrays under set -u)
PIDS=""

# a process and everything below it (ws-wrapper -> sclang -> scsynth), children first.
# by parent pid, so a SuperCollider of your own is never touched
tree() {
    local c
    for c in $(pgrep -P "$1" 2>/dev/null); do tree "$c"; done
    echo "$1"
}

kill_tree() {
    local all p n=0
    all="$(tree "$1")"
    for p in $all; do kill "$p" 2>/dev/null; done
    while :; do
        local alive=""
        for p in $all; do kill -0 "$p" 2>/dev/null && alive="$alive $p"; done
        [ -z "$alive" ] && return
        n=$((n + 1))
        if [ $n -gt 25 ]; then
            for p in $alive; do kill -9 "$p" 2>/dev/null; done
            return
        fi
        sleep 0.2
    done
}

cleanup() {
    # reverse start order: jackd goes last, after everything that plays through it
    local p rev=""
    for p in $PIDS; do rev="$p $rev"; done
    for p in $rev; do kill_tree "$p"; done
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

WS="$REPO/build/ws-wrapper/ws-wrapper"
# SYSTEM > RESTART (matron/src/system_cmd.cc) leaves this and quits norns
RESTART_MARK="$NORNS_HOME/.norns-restart"
rm -f "$RESTART_MARK"

start_norns() {
    if [ $TERMINAL -eq 1 ]; then
        # explicit <&0: a non-interactive shell gives background jobs /dev/null as stdin,
        # which would leave matron's lua REPL without input
        "$REPO/build/norns/norns" <&0 &
    else
        "$WS" "ws://127.0.0.1:5555" "$REPO/build/norns/norns" < /dev/null > "$NORNS_HOME/norns.log" 2>&1 &
    fi
    NORNS_PID=$!
    PIDS="$PIDS $NORNS_PID"
    # sclang wires scsynth into crone's jack ports, so wait for crone
    local n=0
    until jack_lsp 2>/dev/null | grep -q '^crone:input_5$'; do
        n=$((n + 1))
        if [ $n -gt 50 ] || ! kill -0 "$NORNS_PID" 2>/dev/null; then
            echo "norns.sh: crone did not come up, sclang not started"
            return
        fi
        sleep 0.2
    done
    "$WS" "ws://127.0.0.1:5556" "$SC_BIN/sclang" -i maiden < /dev/null > "$NORNS_HOME/sclang.log" 2>&1 &
    SCLANG_PID=$!
    PIDS="$PIDS $SCLANG_PID"
}

# the new sclang must get the old one's OSC port (57120): stop the whole old tree first
stop_sclang() {
    [ -n "${SCLANG_PID:-}" ] && kill_tree "$SCLANG_PID"
}

start_norns

# the norns side of the AUv3: idle until the plugin renders in a DAW
if [ -x "$REPO/build/macos/auv3_bridge" ]; then
    "$REPO/build/macos/auv3_bridge" < /dev/null > "$NORNS_HOME/auv3_bridge.log" 2>&1 &
    PIDS="$PIDS $!"
fi

MAIDEN="${NORNS_MAIDEN:-$NORNS_HOME/maiden}"
if [ -x "$MAIDEN/maiden" ]; then
    # first start: the catalog sources maiden installs scripts from (tool/project-setup.sh)
    if [ ! -d dust/data/sources ]; then
        mkdir -p dust/data/sources dust/data/catalogs
        cp "$MAIDEN"/dist/sources/*.json dust/data/sources/ 2>/dev/null
    fi
    (cd "$MAIDEN" && exec ./maiden server --host 127.0.0.1 --port 5000 --app ./app/build \
        --data "$NORNS_HOME/dust" --doc "$NORNS_HOME/norns/doc" < /dev/null > "$NORNS_HOME/maiden.log" 2>&1) &
    PIDS="$PIDS $!"
    echo "norns.sh: maiden at http://127.0.0.1:5000/maiden"
fi
[ $TERMINAL -eq 0 ] && echo "norns.sh: matron log in $NORNS_HOME/norns.log (close the norns window or ctrl-c to stop)"

while :; do
    wait "$NORNS_PID"
    [ -f "$RESTART_MARK" ] || break
    rm -f "$RESTART_MARK"
    echo "norns.sh: restarting norns and sclang"
    stop_sclang
    start_norns
done
