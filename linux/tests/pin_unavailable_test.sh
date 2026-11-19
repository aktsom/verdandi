#!/bin/bash
# linux/tests/pin_unavailable_test.sh (M25): PIN (always on top) on a desktop that cannot do it. SDL's X11 driver can ask the window manager to keep a window on top; a Wayland client cannot (SDL's wayland driver has
# no such request). the code asks SDL_GetCurrentVideoDriver(): anything but "x11" is "cannot". this test runs the real norns with SDL's "offscreen" video driver (no Wayland session is available to the tests: it is the same
# branch, not Wayland itself): F7 must NOT turn PIN on (state 0, the button dark, no window flagged), and the log must say why in one plain line.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
FAILS=0
ok() { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; FAILS=$((FAILS + 1)); }
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
NH="$T/home"; mkdir -p "$NH"; ln -s "$REPO" "$NH/norns"
printf '%s\n' "#sleep 3" "_norns.grid_window('keys')" "#sleep 1" "_norns.pin_report(1)" "#sleep 1" "_norns.grid_window('keys')" "#sleep 1" "_norns.pin_report(2)" "#sleep 1" > "$T/probe.lua"
SDL_VIDEODRIVER=offscreen VERDANDI_TEST_HOOKS=1 NORNS_MAIDEN="$T/none" NORNS_HOME="$NH" "$HERE/norns_probe.sh" "$T/probe.lua" "$T/log" > /dev/null 2>&1
if grep -aq "pin report 1: state=0 lit=0 main=0/" "$NH/pin_report.log" 2> /dev/null && grep -aq "pin report 2: state=0 lit=0" "$NH/pin_report.log"; then ok "F7 twice: PIN stays off, the button stays dark, no window is flagged"; else bad "PIN did something on a driver that cannot do it: $(cat "$NH/pin_report.log" 2> /dev/null | tr '\n' '|')"; fi
if grep -aq "always on top (PIN) is not available here: the video driver is 'offscreen'" "$T/log"; then ok "the log says why in one plain sentence"; else bad "no sentence in the log: $(grep -a 'always on top' "$T/log" | head -2)"; fi
n="$(grep -ac "always on top (PIN) is not available here" "$T/log")"
[ "$n" = 2 ] && ok "once per press, nothing else" || bad "the sentence came $n times for 2 presses"
[ $FAILS -eq 0 ] && echo "pin_unavailable_test: all passed" || echo "pin_unavailable_test: $FAILS failed"
[ $FAILS -eq 0 ]
