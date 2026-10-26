#!/bin/bash
# linux/norns.sh and maiden (docs/port/phase-4-maiden.md): the launcher starts maiden next to norns on the loopback only,
# the REPL websocket of the real matron takes a page that maiden served and refuses another site, a taken port
# is said and left alone, norns without maiden built still boots, and everything stops with norns.
# headless: Xvfb, jackd dummy driver, no sclang. usage: maiden_launcher_test.sh [MAIDEN_DIR]
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
NORNS_HOME_DEFAULT="$(dirname "$REPO")"
MD="${1:-$NORNS_HOME_DEFAULT/maiden}"
if [ ! -x "$MD/maiden" ]; then
    echo "SKIP: $MD/maiden is not built (linux/maiden-build.sh)"
    exit 0
fi
FAILS=0
check() { if [ "$2" = "$3" ]; then echo "  ok    $1"; else echo "  FAIL  $1: got '$2', want '$3'"; FAILS=$((FAILS + 1)); fi; }
has() { case "$2" in *"$3"*) echo "  ok    $1" ;; *) echo "  FAIL  $1: '$3' not in '$2'"; FAILS=$((FAILS + 1)) ;; esac; }
freeport() { python3 -I -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])'; }

XVFB_PID=""
if [ -z "${DISPLAY:-}" ]; then
    Xvfb :98 -screen 0 1280x800x24 > /dev/null 2>&1 &
    XVFB_PID=$!
    export DISPLAY=:98
    sleep 1
fi
export NORNS_JACK_DRIVER=dummy SDL_AUDIODRIVER=dummy NORNS_NO_SCLANG=1
T="$(mktemp -d)"
RUN=""
stop_norns() {
    [ -n "$RUN" ] && kill "$RUN" 2> /dev/null && wait "$RUN" 2> /dev/null
    RUN=""
    for _ in $(seq 50); do pgrep -x jackd > /dev/null || pgrep -x norns > /dev/null || break; sleep 0.2; done
    pkill -9 -x norns 2> /dev/null
    pkill -9 -x jackd 2> /dev/null
    sleep 0.5
}
cleanup() { stop_norns; [ -n "$XVFB_PID" ] && kill "$XVFB_PID" 2> /dev/null; rm -rf "$T"; }
trap cleanup EXIT

# a norns home with norns -> this checkout; $1: name, $2: the maiden folder to use ("" = none)
newhome() { mkdir -p "$T/$1" && ln -s "$REPO" "$T/$1/norns"; }
start() { # name, env assignments...
    local name="$1"
    shift
    env NORNS_HOME="$T/$name" "$@" "$REPO/linux/norns.sh" ${LAUNCH_ARGS:-} < "${LAUNCH_STDIN:-/dev/null}" > "$T/$name.out" 2>&1 &
    RUN=$!
    for _ in $(seq 150); do
        grep -q "matron log\|--terminal:" "$T/$name.out" 2> /dev/null && break
        kill -0 "$RUN" 2> /dev/null || break
        sleep 0.2
    done
    for _ in $(seq 100); do grep -q "running post-startup" "$T/$name/norns.log" "$T/$name.out" 2> /dev/null && break; sleep 0.2; done
}
procs() { pgrep -f "maiden server --host 127.0.0.1 --port $1" | wc -l; }

PM=$(freeport)
echo "== maiden next to norns, port $PM"
newhome a
start a NORNS_MAIDEN="$MD" NORNS_MAIDEN_PORT="$PM"
has "the launcher says where maiden is" "$(cat "$T/a.out")" "maiden at http://127.0.0.1:$PM/maiden"
sleep 1
check "maiden, matron's REPL: loopback only" "$(python3 -I "$HERE/listening.py" "$PM" 5555)" "$(printf '%s\n' "127.0.0.1:$PM" 127.0.0.1:5555 | sort | tr '\n' ' ' | sed 's/ $//')"
check "first start: the catalog sources were copied" "$(ls "$T/a/dust/data/sources" 2> /dev/null | head -1 | grep -c json)" 1
check "web app" "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PM/maiden/")" 200
LAN="$(hostname -I 2> /dev/null | tr ' ' '\n' | grep -E '^[0-9]+\.' | grep -v '^127\.' | head -1)"
if [ -n "$LAN" ]; then
    check "maiden is not reachable on the LAN address ($LAN)" "$(curl -s -m 3 -o /dev/null -w '%{http_code}' "http://$LAN:$PM/maiden/")" 000
    check "the REPL is not reachable on the LAN address" "$(curl -s -m 3 -o /dev/null -w '%{http_code}' "http://$LAN:5555/")" 000
else
    echo "  skip  LAN address checks: this machine has no non-loopback IPv4 address"
fi
OUT="$(WS_PAYLOAD='print(40+2)
' python3 -I "$HERE/ws_probe.py" 5555 "http://127.0.0.1:$PM")"
has "the page maiden serves (127.0.0.1) runs a line in matron" "$OUT" "42"
OUT="$(WS_PAYLOAD='print(40+2)
' python3 -I "$HERE/ws_probe.py" 5555 "http://localhost:$PM")"
has "the page maiden serves (localhost) runs a line in matron" "$OUT" "42"
OUT="$(WS_PAYLOAD='print(40+2)
' python3 -I "$HERE/ws_probe.py" 5555 "http://evil.example")"
check "a page on another site: refused, nothing runs" "$(echo "$OUT" | grep -c 42)" 0
has "   ... and it was closed" "$OUT" "closed"
OUT="$(WS_PAYLOAD='print(40+2)
' python3 -I "$HERE/ws_probe.py" 5555 -)"
has "maiden-repl (no Origin) runs a line in matron" "$OUT" "42"
stop_norns
sleep 1
check "maiden stopped with norns" "$(procs "$PM")" 0

echo "== the port is taken"
python3 -I -c 'import socket,sys,time;s=socket.socket();s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1);s.bind(("127.0.0.1",int(sys.argv[1])));s.listen(1);time.sleep(60)' "$PM" &
HOLD=$!
sleep 0.5
newhome b
start b NORNS_MAIDEN="$MD" NORNS_MAIDEN_PORT="$PM"
has "the launcher says the port is in use" "$(cat "$T/b.out")" "port $PM is in use"
check "no maiden was started" "$(procs "$PM")" 0
check "norns booted" "$(grep -c 'running post-startup' "$T/b/norns.log")" 1
stop_norns
kill "$HOLD" 2> /dev/null

echo "== maiden is not built"
newhome c
start c NORNS_MAIDEN="$T/none" NORNS_MAIDEN_PORT="$PM"
has "the launcher says so" "$(cat "$T/c.out")" "maiden is not built"
check "norns booted" "$(grep -c 'running post-startup' "$T/c/norns.log")" 1
stop_norns

echo "== --terminal: matron's prompt is the terminal, there is no norns console for maiden"
newhome d
mkfifo "$T/d.fifo"
exec 4<> "$T/d.fifo"
LAUNCH_ARGS=--terminal LAUNCH_STDIN="$T/d.fifo" start d NORNS_MAIDEN="$MD" NORNS_MAIDEN_PORT="$PM"
sleep 1
has "the launcher says maiden's norns console is not available and how to get it" "$(cat "$T/d.out")" "maiden's norns console (port 5555) is not available; start without --terminal"
check "nothing listens on 5555" "$(python3 -I "$HERE/listening.py" 5555)" ""
check "maiden itself is up (editor, catalog)" "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PM/maiden/")" 200
stop_norns
exec 4>&-

[ $FAILS -eq 0 ] && echo "maiden_launcher_test: all passed" || echo "maiden_launcher_test: $FAILS failed"
if [ $FAILS -ne 0 ]; then for f in a b c d; do echo "--- $f.out"; tail -6 "$T/$f.out" 2> /dev/null; done; fi
[ $FAILS -eq 0 ]
