#!/bin/bash
# linux/tests/grid_led_test.sh: the LED data that norns writes to a grid's serial port. the virtual grid is a pseudo terminal that libmonome opens like a
# real grid; an LD_PRELOAD shim (write_log.c) records the bytes. checks (mext protocol, LED level map = header 0x1a, offset x y, 32 bytes of levels):
#   a script lights LEDs (a packet with 0xf0 as the first level byte, the key at 1,1 at 15), a script change clears them (all-zero maps for both
#   halves of a 16x8 grid), and direct commands from the Lua prompt reach the port (g:led + g:refresh lights the top left key; g:all(0) + g:refresh clears)
# found on a laptop with a real grid 128: LEDs stayed after a script change and the prompt had no effect. docs/port/KNOWN-ISSUES.md item 14
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
FAILS=0
ok() { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; FAILS=$((FAILS + 1)); }
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
cc -shared -fPIC -O2 -o "$T/write_log.so" "$HERE/write_log.c" -ldl || { echo "cannot build the write shim"; exit 1; }
mkdir -p "$T/dust/code"
cp -r "$HERE/grid_scripts/grid_a" "$HERE/grid_scripts/grid_b" "$T/dust/code/"
ln -s "$REPO" "$T/norns"
export WRITE_LOG="$T/writes.log"
LD_PRELOAD="$T/write_log.so" NORNS_MAIDEN="$T/none" NORNS_HOME="$T" "$HERE/norns_probe.sh" "$HERE/probe_grid_led.lua" "$T/log" > /dev/null 2>&1
grep -a "PROBE vport" "$T/log" | head -1
# the lines between MARK $1 and the next MARK, level-map packets only (35 bytes: 1a + x + y + 32)
section() { awk -v m="MARK $1" '$0 == m {on=1; next} /^MARK /{on=0} on' "$WRITE_LOG" 2> /dev/null; }
maps() { section "$1" | awk '$2 == 35 && substr($4, 1, 2) == "1a"' ; }
zero32="0000000000000000000000000000000000000000000000000000000000000000"
n="$(maps script_a | grep -c .)"
[ "$n" -ge 2 ] && ok "the script's LEDs are written ($n level maps)" || bad "script A: $n level maps written"
maps script_a | awk '{print $4}' | grep -q "^1a000" && maps script_a | awk '{print $4}' | grep -q "^1a0000f0" && ok "top left key at level 15 (first level byte 0xf0)" || bad "no map with 0xf0 as the first level byte: $(maps script_a | awk '{print substr($4,1,12)}' | tr '\n' ' ')"
c="$(maps script_change | awk '{print $4}')"
echo "$c" | grep -q "^1a0000$zero32" && echo "$c" | grep -q "^1a0800$zero32" && ok "a script change clears both halves (all-zero maps at x=0 and x=8)" || bad "script change: $(echo "$c" | awk '{print substr($1,1,12)}' | tr '\n' ' ')"
c="$(maps repl_led | awk '{print $4}')"
echo "$c" | grep -q "^1a0000f0" && ok "g:led(1,1,15); g:refresh() from the prompt reaches the port" || bad "prompt led: $(echo "$c" | awk '{print substr($1,1,12)}' | tr '\n' ' ')"
c="$(maps repl_all | awk '{print $4}')"
echo "$c" | grep -q "^1a0000$zero32" && ok "g:all(0); g:refresh() from the prompt reaches the port" || bad "prompt all: $(echo "$c" | awk '{print substr($1,1,12)}' | tr '\n' ' ')"
# every write was complete
if awk '$1 == "W" && $3 != $2 {bad = 1} END {exit !bad}' "$WRITE_LOG" 2> /dev/null; then bad "a write was cut short"; else ok "no write was cut short"; fi
[ $FAILS -eq 0 ] && echo "grid_led_test: all passed" || { echo "grid_led_test: $FAILS failed"; head -30 "$WRITE_LOG" | cut -c1-90; }
[ $FAILS -eq 0 ]
