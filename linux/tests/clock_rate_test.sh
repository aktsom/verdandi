#!/bin/bash
# linux/tests/clock_rate_test.sh <jackd|pipewire> <log>: beats per second of the internal clock (120 BPM = 2.0) while the
# input is SYS (every application's sound linked into crone), in a JACK graph with several clients.
#   jackd:    our own jackd (dummy driver), fake application clients
#   pipewire: a private PipeWire + WirePlumber with a null sink, fake clients through pw-jack. needs pipewire, wireplumber,
#             pw-jack, dbus-run-session. (the clock reads JACK's frame time, a counter of the graph's driver: when PipeWire
#             moves norns' nodes to another driver its base jumps; see docs/port/KNOWN-ISSUES.md item 6)
# prints "RATE <beats per second> <seconds> <beats>" as the last line of <log>.rate
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
FLAVOR="$1"
LOG="$2"
T="$(mktemp -d)"
H="$(mktemp -d)"
ln -s "$REPO" "$H/norns"
PIDS=""
cleanup() {
    for p in $PIDS; do kill "$p" 2> /dev/null; done
    pkill -f "$T/fake_card" 2> /dev/null
    rm -rf "$T"
}
trap cleanup EXIT
cc -std=gnu11 "$REPO/linux/tests/fake_card.c" -o "$T/fake_card" $(pkg-config --cflags --libs jack) || exit 1
# the input mode at startup (INPUT_MODE): system (SYS, default), off (MIC off), mic
case "${INPUT_MODE:-system}" in
system) printf 'system\n\n\n' > "$H/.norns-input" ;;
off) touch "$H/.mic-off" ;;
esac

if [ "$FLAVOR" = pipewire ]; then
    export XDG_RUNTIME_DIR="$T/xdg"
    mkdir -p "$XDG_RUNTIME_DIR"
    chmod 700 "$XDG_RUNTIME_DIR"
    pipewire > "$T/pipewire.log" 2>&1 &
    PIDS="$PIDS $!"
    for _ in $(seq 50); do pw-cli info 0 > /dev/null 2>&1 && break; sleep 0.2; done
    pw-cli create-node adapter '{ factory.name=support.null-audio-sink node.name=nullsink media.class=Audio/Sink object.linger=true audio.position=[FL FR] node.driver=true priority.driver=1000 }' > /dev/null
    dbus-run-session -- wireplumber > "$T/wireplumber.log" 2>&1 &
    PIDS="$PIDS $!"
    sleep 4
    RUN=(pw-jack)
else
    jackd -r -d dummy -r 48000 -p 1024 -C 0 -P 0 < /dev/null > "$T/jackd.log" 2>&1 &
    PIDS="$PIDS $!"
    for _ in $(seq 50); do jack_lsp > /dev/null 2>&1 && break; sleep 0.2; done
    RUN=()
fi
"${RUN[@]}" "$T/fake_card" "Built-in Audio Analog Stereo" &
"${RUN[@]}" "$T/fake_card" "USB DAC" nomidi &
for a in Vivaldi Vivaldi-73 mpv Reaper Spotify; do "${RUN[@]}" "$T/fake_card" "$a" app & done
sleep 1.5

NORNS_HOME="$H" NORNS_CLOCK_DEBUG=1 "${RUN[@]}" "$REPO/linux/tests/norns_probe.sh" "$REPO/linux/tests/probe_clock.lua" "$LOG" > /dev/null 2>&1
awk -v marks="$H/probe.marks.t" '
    BEGIN { while ((getline line < marks) > 0) t[++n] = line }
    /PROBE beats/ { b[++m] = $3 }
    END { k = (n < m) ? n : m; if (k < 2) { print "RATE 0 0 0"; exit }
          dt = t[k] - t[1]; db = b[k] - b[1]; printf "RATE %.3f %.2f %.2f\n", db / dt, dt, db }' "$LOG" > "$LOG.rate"
exit 0
