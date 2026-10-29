#!/bin/bash
# helper of the detach scenario (probe_detach*.lua, run_all.sh): what only X can tell, written to $MARKS or to files.
#   detach_check.sh count NAME REGEX      NAME=<number of windows whose title matches REGEX>
#   detach_check.sh geom NAME REGEX       NAME=<w>x<h>+<x>+<y> of the first such window
#   detach_check.sh cap REGEX FILE        a picture of that window, raised first (there is no window manager: what is on top is what the picture shows); REGEX root: the whole display
#   detach_check.sh close REGEX           what the window manager's close button does (x_close_window.py)
#   detach_check.sh newshot FILE          copy the newest Verdandi*.png of dust/ (the Screenshot item / Ctrl+Shift+S) to FILE
#   detach_check.sh newgif FILE           the same for the newest Verdandi*.gif (Record GIF)
#   detach_check.sh conf NAME             NAME=<screen-window.conf with the lines joined by ,>
#   detach_check.sh alive NAME            NAME=yes|no: is norns still running
HERE="$(cd "$(dirname "$0")" && pwd)"
cmd="${1:-}"
shift
first() { xdotool search --name "$1" 2> /dev/null | head -n 1; }
case "$cmd" in
count) echo "$1=$(xdotool search --name "$2" 2> /dev/null | wc -l)" >> "$MARKS" ;;
geom)
    id="$(first "$2")"
    if [ -n "$id" ]; then
        eval "$(xdotool getwindowgeometry --shell "$id" 2> /dev/null)"
        echo "$1=${WIDTH}x${HEIGHT}+${X}+${Y}" >> "$MARKS"
    else
        echo "$1=none" >> "$MARKS"
    fi
    ;;
cap)
    if [ "$1" = root ]; then import -window root "$2"; else id="$(first "$1")"; [ -n "$id" ] && { xdotool windowraise "$id"; sleep 0.4; import -window "$id" "$2"; }; fi
    ;;
close) id="$(first "$1")"; [ -n "$id" ] && python3 -I "$HERE/x_close_window.py" "$id" ;;
newgif) f="$(ls -t "$NORNS_HOME"/dust/Verdandi*.gif 2> /dev/null | head -n 1)"; [ -n "$f" ] && cp "$f" "$1" ;;
newshot) f="$(ls -t "$NORNS_HOME"/dust/Verdandi*.png 2> /dev/null | head -n 1)"; [ -n "$f" ] && cp "$f" "$1" ;;
conf) echo "$1=$(tr '\n' ',' < "$NORNS_HOME/screen-window.conf" 2> /dev/null)" >> "$MARKS" ;;
alive) if pgrep -x norns > /dev/null; then echo "$1=yes" >> "$MARKS"; else echo "$1=no" >> "$MARKS"; fi ;;
esac
exit 0
