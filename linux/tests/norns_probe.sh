#!/bin/bash
# norns_probe.sh <commands.lua> [log]
#
# headless test harness: boots norns (linux/norns.sh) on Xvfb with jackd's dummy driver and a fifo
# on stdin, waits for post-startup, feeds the lua REPL one line at a time from <commands.lua>
# ("#sleep N" waits N seconds, other lines starting with # are comments), stops everything.
# more commands for the window (Xvfb): "#shot <png>" saves the screen, "#xdo <xdotool args>" sends
# input (needs xdotool, imagemagick: linux/setup-deps.sh).
# norns home: $NORNS_HOME, or a fresh temp dir with norns -> this checkout.

set -u
CMDS="$1"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
if [ -z "${NORNS_HOME:-}" ]; then
    NORNS_HOME="$(mktemp -d)"
    ln -s "$REPO" "$NORNS_HOME/norns"
fi
export NORNS_HOME
LOG="${2:-$NORNS_HOME/probe.log}"
FIFO="$NORNS_HOME/probe.fifo"

XVFB_PID=""
if [ -z "${DISPLAY:-}" ]; then
    Xvfb :99 -screen 0 1280x800x24 >/dev/null 2>&1 &
    XVFB_PID=$!
    export DISPLAY=:99
    sleep 1
fi
export NORNS_JACK_DRIVER=dummy
export SDL_AUDIODRIVER=dummy

rm -f "$FIFO"
mkfifo "$FIFO"
"$REPO/linux/norns.sh" --terminal < "$FIFO" > "$LOG" 2>&1 &
RUN=$!
exec 3> "$FIFO"

n=0
until grep -q "running post-startup" "$LOG" 2>/dev/null; do
    n=$((n + 1))
    if [ $n -gt 300 ] || ! kill -0 $RUN 2>/dev/null; then
        echo "norns_probe: norns did not boot, see $LOG"
        break
    fi
    sleep 0.2
done
sleep 1

while IFS= read -r line || [ -n "$line" ]; do
    line="${line//@home/$NORNS_HOME}" # @home = the norns home, for "#shot @home/x.png"
    case "$line" in
    "#sleep "*) sleep "${line#\#sleep }" ;;
    "#shot "*) xwd -root -display "$DISPLAY" | convert xwd:- "png:${line#\#shot }" ;;
    "#xdo "*) xdotool ${line#\#xdo } ;;
    "#"* | "") ;;
    *) printf '%s\n' "$line" >&3 ;;
    esac
done < "$CMDS"

exec 3>&-
sleep 0.5
kill $RUN 2>/dev/null
wait $RUN 2>/dev/null
pkill -f "$REPO/build/norns/norns" 2>/dev/null
sleep 1
pkill -9 -f "$REPO/build/norns/norns" 2>/dev/null
pkill -x sclang 2>/dev/null
pkill -x scsynth 2>/dev/null
pkill -x jackd 2>/dev/null
[ -n "$XVFB_PID" ] && kill "$XVFB_PID" 2>/dev/null
rm -f "$FIFO"
echo "norns_probe: done, log in $LOG"
