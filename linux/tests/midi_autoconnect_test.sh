#!/bin/bash
# linux/tests/midi_autoconnect_test.sh <log>: the optional auto-connect of MIDI outputs to Verdandi:midi_in.
# <log>.<state>: jack_lsp -c dumps
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
LOG="$1"
T="$(mktemp -d)"
trap 'rm -rf "$T"; pkill -x fake_midi 2> /dev/null' EXIT
cc -std=gnu11 "$REPO/linux/tests/fake_midi.c" -o "$T/fake_midi" $(pkg-config --cflags --libs jack) || exit 1
H="$(mktemp -d)"
ln -s "$REPO" "$H/norns"
jackd -r -d dummy -r 48000 -p 1024 -C 0 -P 0 < /dev/null > "$T/jackd.log" 2>&1 &
for _ in $(seq 50); do jack_lsp > /dev/null 2>&1 && break; sleep 0.2; done
export FAKEMIDI="$T/fake_midi"
case "${MIDI_SCENARIO:-conf}" in
    default)  # M39: no midi_in_from anywhere: Reaper's virtual port (as PipeWire names it) is linked by itself; the probe restarts it
        "$T/fake_midi" "Midi-Bridge" "Client-128:(capture_0) Virtual RawMIDI" &
        "$T/fake_midi" "Other" &
        ;;
    default2) # M39: two programs with a virtual port, a hardware interface and the VirMIDI card: one source linked, nothing else
        "$T/fake_midi" "Midi-Bridge" "Client-128:(capture_0) Virtual RawMIDI" "Client-129:(capture_0) Virtual RawMIDI" "mio:(capture_0) mio MIDI 1" "VirMIDI 1-0:(capture_0) VirMIDI 1-0" &
        ;;
    *)
        "$T/fake_midi" "Fake DAW" &
        "$T/fake_midi" "Other" &
        ;;
esac
sleep 0.5
# a prefix on the command line of audio.conf: tested through audio.conf in the first scenario, the environment in
# the other: audio.conf here, the environment variable beats it (scenario "env")
if [ "${MIDI_SCENARIO:-conf}" = default ] || [ "${MIDI_SCENARIO:-conf}" = default2 ]; then
    : # no audio.conf line and no variable: the default
elif [ "${MIDI_SCENARIO:-conf}" = conf ]; then
    # audio.conf; and no wake-ups by port registrations: only the 2 s re-check can repair the cut link
    export NORNS_MIDI_POKE=0
    printf 'midi_in_from=Fake DAW:;Late DAW\n' > "$H/audio.conf"
else
    export NORNS_MIDI_IN_FROM="Fake DAW:;Late DAW"
fi
PROBE=probe_midi_link.lua
case "${MIDI_SCENARIO:-conf}" in default) PROBE=probe_midi_default.lua ;; default2) PROBE=probe_midi_default2.lua ;; esac
NORNS_HOME="$H" "$REPO/linux/tests/norns_probe.sh" "$REPO/linux/tests/$PROBE" "$LOG" > /dev/null 2>&1
for f in "$H"/probe.marks.*; do cp "$f" "$LOG.${f##*.marks.}"; done
exit 0
