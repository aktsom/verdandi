#!/bin/bash
# helper of the second-start scenario (probe_second_start*.lua, run_all.sh second_start_scenario): runs inside the probe, writes to $MARKS.
#   second_start_check.sh cover-start | cover-focus | cover-stop     another window in front of everything, with the keyboard focus (x_cover_window.py)
#   second_start_check.sh second NAME                  starts the launcher a second time, as from the application menu (no terminal): NAME_rc, NAME_norns, NAME_dialogs
#   second_start_check.sh focus NAME                   NAME=<the window with the keyboard focus>
#   second_start_check.sh id NAME REGEX                NAME=<id of the first window whose title matches>
#   second_start_check.sh files NAME                   NAME=<the .norns-raise control files in the norns home>
HERE="$(cd "$(dirname "$0")" && pwd)"
cmd="${1:-}"
shift
case "$cmd" in
cover-start)
    python3 -I "$HERE/x_cover_window.py" > "$NORNS_HOME/cover.id" 2> /dev/null &
    echo $! > "$NORNS_HOME/cover.pid"
    ;;
cover-focus) xdotool windowfocus "$(head -n 1 "$NORNS_HOME/cover.id")" 2> /dev/null ;;
cover-stop) kill "$(cat "$NORNS_HOME/cover.pid" 2> /dev/null)" 2> /dev/null ;;
second)
    env PATH="$NORNS_HOME/stub:$PATH" NORNS_HOME="$NORNS_HOME" NORNS_RAISE_WAIT=5 "$NORNS_HOME/norns/linux/norns.sh" > "$NORNS_HOME/second-$1.out" 2>&1 < /dev/null
    rc=$?
    { echo "$1_rc=$rc"; echo "$1_norns=$(pgrep -xc norns)"; echo "$1_dialogs=$(wc -l < "$NORNS_HOME/zenity.log" 2> /dev/null || echo 0)"; } >> "$MARKS"
    ;;
focus) echo "$1=$(xdotool getwindowfocus 2> /dev/null)" >> "$MARKS" ;;
id) echo "$1=$(xdotool search --name "$2" 2> /dev/null | head -n 1)" >> "$MARKS" ;;
files) echo "$1=$(ls -a "$NORNS_HOME" | grep '^\.norns-raise' | tr '\n' ' ')" >> "$MARKS" ;;
esac
exit 0
