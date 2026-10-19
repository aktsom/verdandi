#!/bin/bash
# norns_probe.sh <commands.lua> [log]
#
# test harness for the macOS port: boots norns (macos/norns.sh) with a fifo on stdin,
# waits for post-startup, then feeds the lua REPL one line at a time from <commands.lua>.
# a line "#sleep N" waits N seconds. stops norns and jackd afterwards.

set -u
CMDS="$1"
# norns home = the folder above this checkout (macos/tests/ -> repo -> home)
NHOME="$(cd "$(dirname "$0")/../../.." && pwd)"
LOG="${2:-$NHOME/probe.log}"
# exFAT has no fifos
FIFO="${TMPDIR:-/tmp}/norns_probe.$$.fifo"

rm -f "$FIFO"
mkfifo "$FIFO"
"$NHOME/norns/macos/norns.sh" --terminal < "$FIFO" > "$LOG" 2>&1 &
RUN=$!
exec 3> "$FIFO"

n=0
until grep -q "running post-startup" "$LOG" 2>/dev/null; do
    n=$((n + 1))
    if [ $n -gt 150 ] || ! kill -0 $RUN 2>/dev/null; then
        echo "norns_probe: norns did not boot, see $LOG"
        break
    fi
    sleep 0.2
done
sleep 1

while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
    "#sleep "*) sleep "${line#\#sleep }" ;;
    "#"* | "") ;;
    *) printf '%s\n' "$line" >&3 ;;
    esac
done < "$CMDS"

exec 3>&-
sleep 0.5
pkill -P $RUN 2>/dev/null
kill $RUN 2>/dev/null
sleep 0.5
pkill -f "$NHOME/norns/build/norns/norns" 2>/dev/null
pkill -f "$NHOME/norns/build/ws-wrapper/ws-wrapper" 2>/dev/null
pkill -f 'SuperCollider.app/Contents/MacOS/sc' 2>/dev/null
pkill -x jackd 2>/dev/null
sleep 0.5
if pgrep -f "$NHOME/norns/build/norns/norns|SuperCollider.app/Contents/MacOS/sc" >/dev/null; then
    echo "norns_probe: WARNING leftover processes:"; pgrep -fl "$NHOME/norns/build/norns/norns|SuperCollider.app/Contents/MacOS/sc"
fi
rm -f "$FIFO"
echo "norns_probe: done, log in $LOG"
