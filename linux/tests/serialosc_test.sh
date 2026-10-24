#!/bin/bash
# linux/tests/serialosc_test.sh <log> [disabled]: the serialosc conflict check against fake processes with serialosc's command lines.
# "disabled": NORNS_SERIALOSC_CHECK=0 (nothing may be reported)
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
LOG="$1"
T="$(mktemp -d)"
H="$(mktemp -d)"
trap 'for f in "$H"/probe.marks.pid_*; do kill "$(cat "$f")" 2> /dev/null; done; rm -rf "$T"' EXIT
ln -s "$REPO" "$H/norns"
cc -std=gnu11 "$REPO/linux/tests/fake_serialosc_device.c" -o "$T/fake" || exit 1
# the "grid": a file standing for /dev/ttyACM3 and a by-id symlink to it, as udev makes them
mkdir -p "$T/dev/serial/by-id"
: > "$T/dev/ttyACM3"
ln -s ../../ttyACM3 "$T/dev/serial/by-id/usb-monome_grid_m0000001-if00"
export FAKE="$T/fake" DEVTTY="$T/dev/ttyACM3" DEVLINK="$T/dev/serial/by-id/usb-monome_grid_m0000001-if00"
[ "${2:-}" = disabled ] && export NORNS_SERIALOSC_CHECK=0
jackd -r -d dummy -r 48000 -p 1024 -C 0 -P 0 < /dev/null > "$T/jackd.log" 2>&1 &
for _ in $(seq 50); do jack_lsp > /dev/null 2>&1 && break; sleep 0.2; done
NORNS_HOME="$H" "$REPO/linux/tests/norns_probe.sh" "$REPO/linux/tests/probe_serialosc.lua" "$LOG" > /dev/null 2>&1
exit 0
