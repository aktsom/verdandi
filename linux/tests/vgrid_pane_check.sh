#!/bin/bash
# helper of the headless test of the virtual grid window (probe_vgrid_view.lua, run_all.sh): what only X can tell and do, with the window found by its title "grid".
#   vgrid_pane_check.sh shape NAME                   NAME=<w>x<h> (the window) and NAME_rot=<the saved rotation>
#   vgrid_pane_check.sh key COLS ROWS ROT C R [mods]    press and let go of the device key (C, R) where the plate turned ROT has it; mods: shift
#   vgrid_pane_check.sh down|up|move COLS ROWS ROT C R  the left button down / up / the pointer moves, at that key
#   vgrid_pane_check.sh button COLS ROWS ROT N          click the button N of the bar (1-3 sizes, 4 ROTATE)
#   vgrid_pane_check.sh shift down|up                   the shift key (the pointer stays over the window: there is no window manager, the keys go to the window under the pointer)
#   vgrid_pane_check.sh ctrl down|up                    the Ctrl key (M43: stage and fire)
#   vgrid_pane_check.sh esc                             the Esc key
#   vgrid_pane_check.sh focus main|grid                 move the keyboard focus (what a click in another window does)
#   vgrid_pane_check.sh count NAME                      NAME=<number of windows titled grid>
HERE="$(cd "$(dirname "$0")" && pwd)"
cmd="${1:-}"
shift
gid() { xdotool search --name '^grid$' 2> /dev/null | head -n 1; }
geo() { eval "$(xdotool getwindowgeometry --shell "$1" 2> /dev/null)"; }
# a person moves the mouse onto the window, then clicks: the test moves the pointer into the window first (the corner), then to the key
jiggle() {
    xdotool mousemove --window "$1" 3 3
    sleep 0.15
    # M43: the click on the dead corner is only done when VP_DEADCLICK=1 (it was needed before the size and ROTATE buttons acted on the release: the window that was made again under the pressed button
    # left SDL with a button that seemed pressed and the next click was lost)
    if [ "${VP_DEADCLICK:-0}" = 1 ]; then
        xdotool mousedown 1
        sleep 0.1
        xdotool mouseup 1
        sleep 0.15
    fi
    xdotool mousemove --window "$1" "$2" "$3"
    sleep 0.15
}
xy() { python3 -I "$HERE/vgrid_pane_xy.py" "$@"; }
case "$cmd" in
shape)
    id="$(gid)"
    if [ -n "$id" ]; then geo "$id"; echo "$1=${WIDTH}x${HEIGHT}" >> "$MARKS"; else echo "$1=none" >> "$MARKS"; fi
    echo "$1_rot=$(tr -d '\n' < "$NORNS_HOME/.vgrid-rotation" 2> /dev/null)" >> "$MARKS"
    ;;
count) echo "$1=$(xdotool search --name '^grid$' 2> /dev/null | wc -l)" >> "$MARKS" ;;
key | down | up | move)
    id="$(gid)"
    [ -n "$id" ] || exit 0
    geo "$id"
    read -r x y <<< "$(xy key "$1" "$2" "$3" "$4" "$5" "$WIDTH" "$HEIGHT")"
    case "$cmd" in
    key)
        if [ "${6:-}" = shift ]; then xdotool keydown shift; sleep 0.15; fi
        jiggle "$id" "$x" "$y"
        xdotool mousedown 1
        sleep 0.2
        xdotool mouseup 1
        sleep 0.2
        [ "${6:-}" = shift ] && { sleep 0.1; xdotool keyup shift; sleep 0.3; }
        ;;
    down) jiggle "$id" "$x" "$y"; xdotool mousedown 1 ;;
    up) xdotool mousemove --window "$id" "$x" "$y" mouseup 1 ;;
    move) xdotool mousemove --window "$id" "$x" "$y" ;;
    esac
    ;;
button)
    id="$(gid)"
    [ -n "$id" ] || exit 0
    geo "$id"
    read -r x y <<< "$(xy button "$1" "$2" "$3" "$4" "$WIDTH" "$HEIGHT")"
    jiggle "$id" "$x" "$y"
    xdotool mousedown 1
    sleep 0.2
    xdotool mouseup 1
    sleep 0.6
    ;;
ctrl) if [ "$1" = down ]; then xdotool keydown ctrl; else xdotool keyup ctrl; fi ;;
shift) if [ "$1" = down ]; then xdotool keydown shift; else xdotool keyup shift; fi ;;
esc) xdotool key Escape ;;
focus)
    if [ "$1" = main ]; then xdotool windowfocus "$(xdotool search --name '^Verdandi' 2> /dev/null | head -n 1)"; else xdotool windowfocus "$(gid)"; fi
    ;;
esac
exit 0
