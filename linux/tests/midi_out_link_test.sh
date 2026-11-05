#!/bin/bash
# linux/tests/midi_out_link_test.sh <log>: the optional auto-connect of Verdandi:midi_out to MIDI inputs (midi_out_to= in audio.conf, NORNS_MIDI_OUT_TO).
# <log>.<state>: jack_lsp -c dumps. CAP is the path of jack_midi_out_test (a client with one MIDI input port "in")
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
LOG="$1"
T="$(mktemp -d)"
trap 'rm -rf "$T"; pkill -x jack_midi_out_t 2> /dev/null' EXIT
H="$(mktemp -d)"
ln -s "$REPO" "$H/norns"
jackd -r -d dummy -r 48000 -p 1024 -C 0 -P 0 < /dev/null > "$T/jackd.log" 2>&1 &
for _ in $(seq 50); do jack_lsp > /dev/null 2>&1 && break; sleep 0.2; done
# two sinks that match ("Fake Synth" now, "Late Synth" later) and one that does not
("$CAP" "Fake Synth" 40 0 > /dev/null 2>&1 &)
("$CAP" "Other Synth" 40 0 > /dev/null 2>&1 &)
sleep 0.5
export CAP
if [ "${MIDI_SCENARIO:-conf}" = conf ]; then
    export NORNS_MIDI_POKE=0
    printf 'midi_out_to=Fake Synth:;Late Synth\n' > "$H/audio.conf"
else
    export NORNS_MIDI_OUT_TO="Fake Synth:;Late Synth"
fi
NORNS_HOME="$H" "$REPO/linux/tests/norns_probe.sh" "$REPO/linux/tests/probe_midi_out_link.lua" "$LOG" > /dev/null 2>&1
for f in "$H"/probe.marks.*; do cp "$f" "$LOG.${f##*.marks.}"; done
exit 0
