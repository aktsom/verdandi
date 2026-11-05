#!/bin/bash
# linux/tests/cc2_clock_test.sh <log>: Cheat Codes 2 (a clone of dndrks/cheat_codes_2 with its nb submodule, from $CC2_DIR or cloned here when the network allows) in the real norns:
# a pattern recording ends without "invalid paramset index: clock_midi_out". exit 2: no clone (the test is skipped)
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
LOG="$1"
SRC="${CC2_DIR:-}"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
if [ -z "$SRC" ] || [ ! -f "$SRC/cheat_codes_2.lua" ]; then
    SRC="$T/clone"
    timeout 90 git clone -q --depth 1 --recurse-submodules --shallow-submodules https://github.com/dndrks/cheat_codes_2.git "$SRC" > /dev/null 2>&1 || exit 2
fi
[ -d "$SRC/lib/nb/lib" ] || exit 2
H="$(mktemp -d)"
ln -s "$REPO" "$H/norns"
mkdir -p "$H/dust/code"
cp -r "$SRC" "$H/dust/code/cheat_codes_2"
NORNS_HOME="$H" "$REPO/linux/tests/norns_probe.sh" "$REPO/linux/tests/probe_cc2_clock.lua" "$LOG" > /dev/null 2>&1
rm -rf "$H"
exit 0
