#!/bin/bash
# linux/tests/grid_exit_test.sh: the grid's LEDs when norns ends (KNOWN-ISSUES 30). a script lights LEDs on the virtual grid (a pseudo terminal that libmonome writes to like a real grid's serial port; write_log.c records the
# bytes), then norns ends by: Ctrl+Q, the window's close button, SIGTERM (a launcher restart, a logout), SIGHUP (the terminal closing) and a crash (SIGSEGV). in every case the last thing on the port must be all-zero level maps
# for both halves of the grid (the LEDs are off); and a normal quit writes them within a second
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
FAILS=0
ok() { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; FAILS=$((FAILS + 1)); }
T0="$(mktemp -d)"
trap 'rm -rf "$T0"' EXIT
cc -shared -fPIC -O2 -o "$T0/write_log.so" "$HERE/write_log.c" -ldl || { echo "cannot build the write shim"; exit 1; }
zero32="0000000000000000000000000000000000000000000000000000000000000000"
for how in ${HOWS:-quit close term hup segv}; do
    T="$(mktemp -d)"
    mkdir -p "$T/dust/code"
    cp -r "$HERE/grid_scripts/grid_a" "$T/dust/code/"
    ln -s "$REPO" "$T/norns"
    export WRITE_LOG="$T/writes.log"
    HOW="$how" DC="$HERE/detach_check.sh" LD_PRELOAD="$T0/write_log.so" NORNS_MAIDEN="$T/none" NORNS_HOME="$T" "$HERE/norns_probe.sh" "$HERE/probe_grid_exit.lua" "$T/log" > /dev/null 2>&1
    # what was written after MARK exit: level maps (35 bytes: 1a + x + y + 32 level bytes)
    after="$(awk '$0 == "MARK exit" {on=1; next} /^MARK /{on=0} on' "$WRITE_LOG" 2> /dev/null | awk '$2 == 35 && substr($4, 1, 2) == "1a" {print $4}')"
    lit="$(awk '$0 == "MARK exit" {exit} {print}' "$WRITE_LOG" 2> /dev/null | awk '$2 == 35 && substr($4, 1, 6) == "1a0000" && substr($4, 7, 2) == "f0"' | wc -l)"
    [ "$lit" -ge 1 ] && ok "$how: the script's LEDs were on before the exit" || bad "$how: no lit map before the exit (the test did not light the grid)"
    last0="$(echo "$after" | awk 'substr($1, 1, 6) == "1a0000" {l = substr($1, 7)} END {print l}')"
    last8="$(echo "$after" | awk 'substr($1, 1, 6) == "1a0800" {l = substr($1, 7)} END {print l}')"
    if [ "$last0" = "$zero32" ] && [ "$last8" = "$zero32" ]; then ok "$how: the last map of both halves written on the way out is all zero (the LEDs are off)"; else bad "$how: after the exit the last maps are: left ${last0:0:16}, right ${last8:0:16} (wanted all zero)"; fi
    if awk '$1 == "W" && $3 != $2 {bad = 1} END {exit !bad}' "$WRITE_LOG" 2> /dev/null; then bad "$how: a write was cut short"; fi
    pgrep -x norns > /dev/null && bad "$how: norns is still running afterwards"
    rm -rf "$T"
done
[ $FAILS -eq 0 ] && echo "grid_exit_test: all passed" || echo "grid_exit_test: $FAILS failed"
[ $FAILS -eq 0 ]
