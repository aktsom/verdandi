#!/bin/bash
# linux/tests/window_state_test.sh (M25): the size and place of the main window are kept in <home>/main-window.conf and put back at the next start, as on Windows (docs/port/phase-m25.md).
# the real norns on Xvfb (no window manager: the window is where SDL puts it). 1. the window is moved and resized, norns ends: the file has the numbers. 2. the next start: the window is where it was, the same
# size. 3. a saved place that no screen shows (x 9000, or a monitor that was to the left of this one): the window opens on the screen, with the saved size. 4. a size that is bigger than the screen: the screen's.
# 5. a damaged file: ignored. the pure rules (monitors, minimum, maximum) are in win_state_test.c. HOWS="1 2" runs some steps
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
FAILS=0
ok() { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; FAILS=$((FAILS + 1)); }
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
SCREEN_W=1280; SCREEN_H=800 # norns_probe.sh's Xvfb
NH="$T/home"; mkdir -p "$NH"; ln -s "$REPO" "$NH/norns"
run() { # probe commands (lua file lines) -> $T/probe.lua, runs norns on $NH, geometry marks in $NH/probe.marks
    rm -f "$NH/probe.marks"
    NORNS_MAIDEN="$T/none" NORNS_HOME="$NH" "$HERE/norns_probe.sh" "$T/probe.lua" "$T/log" > /dev/null 2>&1
}
geom() { grep -a "^$1=" "$NH/probe.marks" 2> /dev/null | tail -n 1 | cut -d= -f2; }
GEOM_CMD="#sh '$HERE/detach_check.sh' geom main '^Verdandi.Linux\$'"
want() { case " ${HOWS:-1 2 3 4 5} " in *" $1 "*) return 0 ;; esac; return 1; }

if want 1; then
    echo "== the window is moved and resized, norns ends"
    printf '%s\n' "#sleep 3" "#sh xdotool search --name '^Verdandi.Linux\$' | head -1 > \"\$MARKS.id\"" \
        "#sh xdotool windowmove \$(cat \"\$MARKS.id\") 130 70 windowsize \$(cat \"\$MARKS.id\") 760 500" "#sleep 2.5" "$GEOM_CMD" > "$T/probe.lua"
    run
    g1="$(geom main)"
    [ -s "$NH/main-window.conf" ] && ok "main-window.conf was written ($(tr '\n' ' ' < "$NH/main-window.conf"))" || bad "no main-window.conf after the window was moved and resized"
    echo "  the window before the end: $g1"
    case "$g1" in 760x500+130+70) ok "the window was moved and resized as asked" ;; *) bad "the window is $g1, not 760x500+130+70 (the test could not move it)" ;; esac
    grep -q "^x=130$" "$NH/main-window.conf" && grep -q "^y=70$" "$NH/main-window.conf" && grep -q "^w=760$" "$NH/main-window.conf" && grep -q "^h=500$" "$NH/main-window.conf" && ok "the file has x, y, w, h" || bad "the file does not have 130 70 760 500"
fi
if want 2; then
    echo "== the next start puts it back"
    printf '%s\n' "#sleep 3" "$GEOM_CMD" > "$T/probe.lua"
    run
    g2="$(geom main)"
    echo "  the window at the next start: $g2"
    [ "$g2" = "760x500+130+70" ] && ok "the same size and place" || bad "the window is $g2, not 760x500+130+70"
    grep -aq "size and place of the last run restored" "$T/log" && ok "norns says it restored them" || bad "no 'restored' line in the log"
fi
if want 3; then
    for place in "9000 9000" "-5000 100" "1270 790"; do
        set -- $place
        echo "== a saved place that no screen shows: x=$1 y=$2"
        printf 'x=%s\ny=%s\nw=900\nh=560\n' "$1" "$2" > "$NH/main-window.conf"
        printf '%s\n' "#sleep 3" "$GEOM_CMD" > "$T/probe.lua"
        run
        g="$(geom main)"; echo "  the window: $g"
        w="${g%%x*}"; rest="${g#*x}"; h="${rest%%+*}"; r2="${rest#*+}"; x="${r2%%+*}"; y="${r2#*+}"
        if [ -n "$g" ] && [ "$g" != none ] && [ "$x" -ge -200 ] && [ "$x" -le $((SCREEN_W - 80)) ] && [ "$y" -ge -50 ] && [ "$y" -le $((SCREEN_H - 30)) ]; then ok "x=$1 y=$2: the window is on the screen ($x,$y)"; else bad "x=$1 y=$2: the window is at $x,$y, not on the screen"; fi
        [ "$w" = 900 ] && [ "$h" = 560 ] && ok "x=$1 y=$2: the saved size 900x560 is kept" || bad "x=$1 y=$2: the size is ${w}x$h, not 900x560"
        grep -aq "the place did not fit the screens now" "$T/log" && ok "x=$1 y=$2: said in the log" || bad "x=$1 y=$2: no line about the place that did not fit"
    done
fi
if want 4; then
    echo "== a size that is bigger than the screen"
    printf 'x=0\ny=0\nw=9000\nh=9000\n' > "$NH/main-window.conf"
    printf '%s\n' "#sleep 3" "$GEOM_CMD" > "$T/probe.lua"
    run
    g="$(geom main)"; echo "  the window: $g"
    w="${g%%x*}"; rest="${g#*x}"; h="${rest%%+*}"
    [ -n "$w" ] && [ "$w" -le $SCREEN_W ] && [ "$h" -le $SCREEN_H ] && ok "the window fits the screen (${w}x$h)" || bad "the window is ${w}x$h on a ${SCREEN_W}x$SCREEN_H screen"
fi
if want 5; then
    echo "== a damaged file"
    printf 'x=abc\ny=\nw=0\nh=-3\n\000\377junk' > "$NH/main-window.conf"
    printf '%s\n' "#sleep 3" "$GEOM_CMD" > "$T/probe.lua"
    run
    g="$(geom main)"; echo "  the window: $g"
    [ -n "$g" ] && [ "$g" != none ] && ok "norns starts with a window (the damaged file is ignored)" || bad "no window after a damaged main-window.conf"
fi
[ $FAILS -eq 0 ] && echo "window_state_test: all passed" || echo "window_state_test: $FAILS failed"
[ $FAILS -eq 0 ]
