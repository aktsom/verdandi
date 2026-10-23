#!/bin/bash
# linux/tests/input_test.sh <log>: MIC, SYS, APP, sink monitor and OFF against fake JACK clients.
# the jack_lsp -c dumps of every state are in <log>.<state>
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
LOG="$1"
T="$(mktemp -d)"
trap 'rm -rf "$T"; pkill -x fake_card 2> /dev/null' EXIT
cc -std=gnu11 "$REPO/linux/tests/fake_card.c" -o "$T/fake_card" $(pkg-config --cflags --libs jack) || exit 1
H="$(mktemp -d)"
ln -s "$REPO" "$H/norns"
jackd -r -d dummy -r 48000 -p 1024 -C 0 -P 0 < /dev/null > "$T/jackd.log" 2>&1 &
for _ in $(seq 50); do jack_lsp > /dev/null 2>&1 && break; sleep 0.2; done
"$T/fake_card" "Built-in Audio Analog Stereo" &
sleep 0.4
"$T/fake_card" "Vivaldi" app &
"$T/fake_card" "Vivaldi-73" app &
"$T/fake_card" "mpv" app &
sleep 0.5
export FAKE="$T/fake_card" NORNS_SYS_MONITOR=1
NORNS_HOME="$H" "$REPO/linux/tests/norns_probe.sh" "$REPO/linux/tests/probe_input.lua" "$LOG" > /dev/null 2>&1
for f in "$H"/probe.marks.*; do cp "$f" "$LOG.${f##*.marks.}"; done
exit 0
