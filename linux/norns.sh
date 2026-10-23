#!/bin/bash
# norns on Linux (desktop): start jackd if none runs, norns (matron + crone + softcut) and sclang
# with HOME set to the norns home, like macos/norns.sh.
#
# layout (same as /home/we on the device):
#   <norns home>/norns          this repository
#   <norns home>/dust           scripts, audio, data
#   <norns home>/matronrc.lua   written on first start (desktop screen)
#
# usage: linux/norns.sh [--terminal]
#   default: matron and sclang REPLs are websockets (127.0.0.1:5555/5556), the log is in
#            <norns home>/norns.log
#   --terminal: matron's lua REPL and log are this terminal
#
# environment (all optional):
#   NORNS_HOME          the norns home (default: the folder above this repository)
#   NORNS_JACK_DRIVER   jackd driver, default "alsa"; "dummy" for headless runs
#   NORNS_JACK_RATE / NORNS_JACK_PERIOD   default 48000 / 1024
#   NORNS_NO_SCLANG=1   do not start sclang
#   NORNS_AUDIO_SERVER  "auto" (default): use a JACK server that answers; else, if PipeWire runs, run
#                       this script again under pw-jack; else start jackd. "jackd": always start our own
#                       jackd. "pipewire": always use PipeWire's JACK through pw-jack.
#                       NORNS_JACK_DRIVER given (and no server answering) also means our own jackd.
#   NORNS_IN_PORTS / NORNS_OUT_PORTS   sound card to use, as the start of its JACK client name (the
#                       card's name in PipeWire). default: the session's default source / sink under
#                       PipeWire (wpctl), else the first card. audio.conf in the norns home may hold
#                       in_ports=... and out_ports=... (the environment wins)
#   NORNS_DECIDE_ONLY=1 print the decision ("DECIDE action=... server=... in=... out=...") and exit

set -u

TERMINAL=0
[ "${1:-}" = "--terminal" ] && TERMINAL=1

REPO="$(cd "$(dirname "$0")/.." && pwd)"
NORNS_HOME="${NORNS_HOME:-$(dirname "$REPO")}"
JACK_DRIVER="${NORNS_JACK_DRIVER:-alsa}"
JACK_RATE="${NORNS_JACK_RATE:-48000}"
JACK_PERIOD="${NORNS_JACK_PERIOD:-1024}"

jack_up() { jack_lsp >/dev/null 2>&1; }
pw_up() { pw-cli info 0 >/dev/null 2>&1; }
PW_JACK="${NORNS_PW_JACK:-$(command -v pw-jack || true)}"
# a key from audio.conf in the norns home (the last one wins)
conf_get() { sed -n "s/^$1=//p" "$NORNS_HOME/audio.conf" 2>/dev/null | tail -1; }
# the name of PipeWire's default sink / source: also the name of its JACK client
pw_default() { wpctl inspect "$1" 2>/dev/null | sed -n 's/.*node\.description = "\(.*\)".*/\1/p' | head -1; }

# which audio server: SERVER (jackd, pipewire, jack = something else answering), ACTION
decide_server() {
    local want="${NORNS_AUDIO_SERVER:-auto}"
    SERVER=jack
    if jack_up; then
        ACTION=use-running
        if [ "${NORNS_REEXEC:-0}" = 1 ] || { pw_up && jack_lsp 2>/dev/null | grep -q '^Midi-Bridge:'; }; then
            SERVER=pipewire
        fi
        return
    fi
    if [ "$want" = jackd ] || { [ "$want" = auto ] && { [ -n "${NORNS_JACK_DRIVER:-}" ] || ! pw_up; }; }; then
        ACTION=start-jackd
        SERVER=jackd
        return
    fi
    SERVER=pipewire
    if [ "${NORNS_REEXEC:-0}" = 1 ]; then
        ACTION=pipewire-no-jack
    elif pw_up && [ -x "$PW_JACK" ]; then
        ACTION=reexec-pw-jack
    else
        ACTION=need-pw-jack
    fi
}

# the card to use, as a prefix of its JACK client name ("" = the first one)
decide_devices() {
    IN_PORTS="${NORNS_IN_PORTS:-$(conf_get in_ports)}"
    OUT_PORTS="${NORNS_OUT_PORTS:-$(conf_get out_ports)}"
    if [ "$SERVER" = pipewire ]; then
        local d
        if [ -z "$IN_PORTS" ]; then
            d="$(pw_default @DEFAULT_AUDIO_SOURCE@)"
            case "$d" in "Monitor of "*) d="" ;; esac
            IN_PORTS="$d"
        fi
        [ -z "$OUT_PORTS" ] && OUT_PORTS="$(pw_default @DEFAULT_AUDIO_SINK@)"
    fi
}

decide_server
decide_devices
if [ "${NORNS_DECIDE_ONLY:-0}" = 1 ]; then
    echo "DECIDE action=$ACTION server=$SERVER in=$IN_PORTS out=$OUT_PORTS"
    exit 0
fi

export HOME="$NORNS_HOME"
export JACK_NO_START_SERVER=1
# no norns hardware: the keyboard drives K1-3 / E1-3 when nothing else wants the keys
# (lua/core/keyboard.lua)
export NORNS_HARDWARE_KEYS=1
export NORNS_PLATFORM=linux
# SDL would catch SIGTERM and turn it into a quit event nothing reads yet (no window event pump
# on linux until phase 2): let the signal end norns
export SDL_NO_SIGNAL_HANDLERS=1
cd "$NORNS_HOME" || exit 1

mkdir -p dust/code dust/audio dust/data
if [ -f "$REPO/update/version.txt" ] && ! cmp -s "$REPO/update/version.txt" version.txt; then
    cp "$REPO/update/version.txt" version.txt
fi
if [ ! -f matronrc.lua ]; then
    cat > matronrc.lua <<'RC'
-- Linux desktop: the norns window (screen:sdl). keys and encoders: see readme-macos.md
_boot.add_io('screen:sdl', {})
RC
fi

# sclang: the include paths norns-config.sc sets up on the device
SC_CONF="$NORNS_HOME/.config/SuperCollider"
mkdir -p "$SC_CONF"
if [ ! -f "$SC_CONF/sclang_conf.yaml" ]; then
    cat > "$SC_CONF/sclang_conf.yaml" <<SC
includePaths:
    - "$REPO/sc/core"
    - "$REPO/sc/engines"
    - "$NORNS_HOME/dust"
excludePaths:
    []
postInlineWarnings: false
SC
fi

if pgrep -x norns >/dev/null; then
    echo "norns.sh: norns is already running"
    exit 1
fi

PIDS=""
JACK_PID=""
# a process and everything below it, children first
tree() {
    local c
    for c in $(pgrep -P "$1" 2>/dev/null); do tree "$c"; done
    kill "$1" 2>/dev/null
}
cleanup() {
    trap - EXIT INT TERM
    local p
    # reverse start order: jackd goes last, after everything that plays through it
    for p in $(echo $PIDS | tr ' ' '\n' | tac); do tree "$p"; done
    wait 2>/dev/null
}
trap cleanup EXIT
trap 'exit 130' INT TERM

case "$ACTION" in
reexec-pw-jack)
    echo "norns.sh: no JACK server, but PipeWire runs: starting again under pw-jack"
    export NORNS_REEXEC=1
    exec "$PW_JACK" "$0" "$@"
    ;;
need-pw-jack)
    echo "norns.sh: PipeWire is the sound server here but pw-jack is not available (or PipeWire is not running)."
    echo "          install it (Debian/Ubuntu: sudo apt install pipewire-jack), or use our own JACK:"
    echo "          NORNS_AUDIO_SERVER=jackd NORNS_JACK_DRIVER=dummy linux/norns.sh   (silent)"
    exit 1
    ;;
pipewire-no-jack)
    echo "norns.sh: no JACK server answers even under pw-jack. Is pipewire-jack installed and PipeWire running?"
    exit 1
    ;;
esac
echo "norns.sh: audio server: $SERVER${IN_PORTS:+, input '$IN_PORTS'}${OUT_PORTS:+, output '$OUT_PORTS'}"
export NORNS_AUDIO_SERVER_MODE="$SERVER"

if [ "$ACTION" = start-jackd ]; then
    args=(-d "$JACK_DRIVER" -r "$JACK_RATE" -p "$JACK_PERIOD")
    # the dummy driver needs no realtime; jackd -r keeps it quiet in containers
    [ "$JACK_DRIVER" = "dummy" ] && args=(-r -d dummy -r "$JACK_RATE" -p "$JACK_PERIOD")
    echo "norns.sh: starting jackd (${JACK_DRIVER}, ${JACK_RATE} Hz, period ${JACK_PERIOD})"
    jackd "${args[@]}" < /dev/null > "$NORNS_HOME/jackd.log" 2>&1 &
    JACK_PID=$!
    PIDS="$PIDS $JACK_PID"
    n=0
    until jack_up; do
        n=$((n + 1))
        if [ $n -gt 50 ] || ! kill -0 "$JACK_PID" 2>/dev/null; then
            echo "norns.sh: jackd did not start, see $NORNS_HOME/jackd.log"
            exit 1
        fi
        sleep 0.2
    done
fi

WS="$REPO/build/ws-wrapper/ws-wrapper"
NORNS_BIN="$REPO/build/norns/norns"
[ -x "$NORNS_BIN" ] || { echo "norns.sh: $NORNS_BIN not built, run linux/build.sh"; exit 1; }
RESTART_MARK="$NORNS_HOME/.norns-restart"
rm -f "$RESTART_MARK"

start_norns() {
    export NORNS_IN_PORTS="$IN_PORTS" NORNS_OUT_PORTS="$OUT_PORTS"
    if [ $TERMINAL -eq 1 ]; then
        # explicit <&0: a non-interactive shell gives background jobs /dev/null as stdin
        "$NORNS_BIN" <&0 &
    else
        "$WS" "ws://127.0.0.1:5555" "$NORNS_BIN" < /dev/null > "$NORNS_HOME/norns.log" 2>&1 &
    fi
    NORNS_PID=$!
    PIDS="$PIDS $NORNS_PID"
    [ "${NORNS_NO_SCLANG:-0}" = "1" ] && return
    # sclang wires scsynth into crone's jack ports, so wait for crone
    local n=0
    until jack_lsp 2>/dev/null | grep -q '^crone:input_5$'; do
        n=$((n + 1))
        if [ $n -gt 100 ] || ! kill -0 "$NORNS_PID" 2>/dev/null; then
            echo "norns.sh: crone did not come up, sclang not started"
            return
        fi
        sleep 0.2
    done
    # sclang's Qt WebEngine refuses to start as root (containers) without this
    [ "$(id -u)" -eq 0 ] && export QTWEBENGINE_DISABLE_SANDBOX=1 QTWEBENGINE_CHROMIUM_FLAGS=--no-sandbox
    QT_QPA_PLATFORM=offscreen "$WS" "ws://127.0.0.1:5556" sclang -i maiden \
        < /dev/null > "$NORNS_HOME/sclang.log" 2>&1 &
    SCLANG_PID=$!
    PIDS="$PIDS $SCLANG_PID"
}

start_norns
[ $TERMINAL -eq 0 ] && echo "norns.sh: matron log in $NORNS_HOME/norns.log"

while :; do
    wait "$NORNS_PID"
    [ -f "$RESTART_MARK" ] || break
    rm -f "$RESTART_MARK"
    echo "norns.sh: restarting norns and sclang"
    [ -n "${SCLANG_PID:-}" ] && tree "$SCLANG_PID"
    n=0
    while jack_lsp 2>/dev/null | grep -q '^crone:' && [ $n -lt 25 ]; do
        sleep 0.2
        n=$((n + 1))
    done
    decide_devices
    start_norns
done
