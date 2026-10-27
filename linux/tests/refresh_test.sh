#!/bin/bash
# linux/tests/refresh_test.sh: norns calls a script's global refresh() about 60 times a second on the desktop screen, as the device's
# screen thread does (matron/src/hardware/screen/ssd1322.cc posts EVENT_SCREEN_REFRESH at 60 Hz; the desktop backend, sdl.cc, did not).
# found with the script eterna (draws only in refresh()). docs/port/KNOWN-ISSUES.md item 13
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
FAILS=0
ok() { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; FAILS=$((FAILS + 1)); }
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/dust/code"
cp -r "$HERE/refresh_scripts/refresh_a" "$HERE/refresh_scripts/refresh_b" "$T/dust/code/"
ln -s "$REPO" "$T/norns"
NORNS_MAIDEN="$T/none" NORNS_HOME="$T" "$HERE/norns_probe.sh" "$HERE/probe_refresh.lua" "$T/log" > /dev/null 2>&1
line="$(grep -a '^PROBE a_running' "$T/log")"
n="$(echo "$line" | awk '{print $NF}')"
# 3 s: 180 calls at 60 Hz; the window allows a loaded machine
if [ -n "$n" ] && [ "$n" -ge 120 ] && [ "$n" -le 240 ] 2> /dev/null; then ok "refresh() called $n times in 3 s (about 60 per second)"; else bad "refresh() calls in 3 s: '$n' ($line)"; fi
line="$(grep -a '^PROBE b_loaded' "$T/log")"
case "$line" in *true) ok "a script without refresh() leaves refresh as norns.none" ;; *) bad "script without refresh: $line" ;; esac
n="$(grep -a '^PROBE after_replace' "$T/log" | awk '{print $NF}')"
[ "$n" = 0 ] && ok "the old script's refresh() is not called after another script replaced it" || bad "after replace: '$n' calls"
line="$(grep -a '^PROBE after_clear' "$T/log")"
case "$line" in *"	0	true" | *" 0 true") ok "no calls after the script is cleared, refresh is norns.none again" ;; *) bad "after clear: $line" ;; esac
if grep -aq "attempt to call\|stack traceback" "$T/log"; then bad "errors in the log"; grep -a "attempt to call\|stack traceback" "$T/log" | head -3; else ok "no Lua errors in the log"; fi
[ $FAILS -eq 0 ] && echo "refresh_test: all passed" || { echo "refresh_test: $FAILS failed"; grep -a PROBE "$T/log"; }
[ $FAILS -eq 0 ]
