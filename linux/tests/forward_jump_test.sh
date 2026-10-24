#!/bin/bash
# linux/tests/forward_jump_test.sh [log]: what a 560 s forward jump of JACK's frame time does to the clock and to coroutines waiting
# on clock.sync and clock.sleep (measurement, not part of run_all.sh: docs/port/KNOWN-ISSUES.md item 6). prints the PROBE lines.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
LOG="${1:-/tmp/forward_jump.log}"
T="$(mktemp -d)"
H="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
ln -s "$REPO" "$H/norns"
mkdir -p "$H/dust/code/jump"
cp "$REPO/linux/tests/scripts/jump_probe.lua" "$H/dust/code/jump/"
cc -shared -fPIC -o "$T/jump_shim.so" "$REPO/linux/tests/jump_shim.c" -ldl $(pkg-config --cflags jack) || exit 1
jackd -r -d dummy -r 48000 -p 1024 -C 0 -P 0 < /dev/null > /dev/null 2>&1 &
for _ in $(seq 50); do jack_lsp > /dev/null 2>&1 && break; sleep 0.2; done
JUMP_FILE="$T/jump" LD_PRELOAD="$T/jump_shim.so" NORNS_HOME="$H" "$REPO/linux/tests/norns_probe.sh" "$REPO/linux/tests/probe_jump.lua" "$LOG" > /dev/null 2>&1
grep -a "PROBE" "$LOG"
