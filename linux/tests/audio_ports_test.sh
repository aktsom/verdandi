#!/bin/bash
# linux/tests/audio_ports_test.sh <scenario> <log>: crone's sound card choice on a JACK server that
# has fake cards (fake_card.c) and no "system" ports.
#   two-cards: "Fake Card A" and "Fake Card B", each with a physical MIDI port; NORNS_OUT_PORTS picks B
#   none:      no physical ports at all: norns must still boot, unconnected, with a warning
# the connections are in <log>.conn (jack_lsp -c), norns' answers in <log>.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SCEN="$1"
LOG="$2"
T="$(mktemp -d)"
trap 'rm -rf "$T"; pkill -x fake_card 2> /dev/null' EXIT
cc -std=gnu11 "$REPO/linux/tests/fake_card.c" -o "$T/fake_card" $(pkg-config --cflags --libs jack) || exit 1

H="$(mktemp -d)"
ln -s "$REPO" "$H/norns"
jackd -r -d dummy -r 48000 -p 1024 -C 0 -P 0 < /dev/null > "$T/jackd.log" 2>&1 &
for _ in $(seq 50); do jack_lsp > /dev/null 2>&1 && break; sleep 0.2; done
case "$SCEN" in
two-cards)
    "$T/fake_card" "Fake Card A" &
    sleep 0.5
    "$T/fake_card" "Fake Card B" &
    sleep 0.5
    export NORNS_OUT_PORTS="Fake Card B"
    ;;
none) ;;
esac
NORNS_HOME="$H" "$REPO/linux/tests/norns_probe.sh" "$REPO/linux/tests/probe_audio.lua" "$LOG" > /dev/null 2>&1
cp "$H/probe.marks.conn" "$LOG.conn" 2> /dev/null
exit 0
