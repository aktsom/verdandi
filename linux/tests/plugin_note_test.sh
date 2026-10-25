#!/bin/bash
# linux/tests/plugin_note_test.sh <log> [disabled]: norns.sh + the device note for a plug-in of the wrong architecture. the plug-in is a file with an
# ELF header of 32-bit ARM in dust/code (where scripts keep theirs); nothing may move it but the test.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
LOG="$1"
H="$(mktemp -d)"
ln -s "$REPO" "$H/norns"
mkdir -p "$H/dust/code/fake/ignore"
export FAKEPLUG="$H/dust/code/fake/ignore/Fake_scsynth.so"
printf "\x7fELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x03\x00\x28\x00\x00\x00" > "$FAKEPLUG"
head -c 64 /dev/zero >> "$FAKEPLUG"
[ "${2:-}" = disabled ] && export NORNS_PLUGIN_CHECK=0
NORNS_HOME="$H" "$REPO/linux/tests/norns_probe.sh" "$REPO/linux/tests/probe_plugin_note.lua" "$LOG" > /dev/null 2>&1
exit 0
