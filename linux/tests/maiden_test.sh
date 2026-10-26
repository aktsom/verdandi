#!/bin/bash
# maiden on Linux (docs/port/phase-4-maiden.md): the server answers on the loopback only, the editor's
# file API and script install work, and a web page in a browser cannot reach the REPL websockets or
# maiden (the Origin / Host checks). no audio, no norns: ws-wrapper around `cat` stands in for the REPL.
# usage: maiden_test.sh [MAIDEN_DIR]   (default <norns home>/maiden; skipped, not passed, if it is not built)
# environment: WS_WRAPPER (default build/ws-wrapper/ws-wrapper)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
NORNS_HOME="${NORNS_HOME:-$(dirname "$REPO")}"
MD="${1:-$NORNS_HOME/maiden}"
WSW="${WS_WRAPPER:-$REPO/build/ws-wrapper/ws-wrapper}"
if [ ! -x "$MD/maiden" ]; then
    echo "SKIP: $MD/maiden is not built (linux/maiden-build.sh)"
    exit 0
fi
[ -x "$WSW" ] || { echo "maiden_test: $WSW not built"; exit 1; }

T="$(mktemp -d)"
PIDS=""
cleanup() { for p in $PIDS; do kill "$p" 2> /dev/null; done; wait 2> /dev/null; rm -rf "$T"; }
trap cleanup EXIT
FAILS=0
check() { # name, got, want (a failure is printed with both)
    if [ "$2" = "$3" ]; then echo "  ok    $1"; else echo "  FAIL  $1: got '$2', want '$3'"; FAILS=$((FAILS + 1)); fi
}
freeport() { python3 -I -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])'; }

PM=$(freeport); PW=$(freeport)
EVIL=http://evil.example
OWN=http://127.0.0.1:$PM
mkdir -p "$T/dust/code" "$T/dust/data/sources" "$T/dust/data/catalogs" "$T/doc"
# a script to install: a zip with one folder, as the catalog's zip sources are
mkdir -p "$T/zsrc/victim-main"
echo 'print("hello")' > "$T/zsrc/victim-main/victim.lua"
(cd "$T/zsrc" && python3 -I -c 'import zipfile,os;z=zipfile.ZipFile("../victim.zip","w");[z.write(os.path.join(d,f)) for d,_,fs in os.walk("victim-main") for f in fs]')

# the REPL stand-in: the origin list the launcher would give ws-wrapper (loopback names on maiden's port)
WS_WRAPPER_ALLOWED_ORIGINS="http://127.0.0.1:$PM,http://localhost:$PM" "$WSW" "ws://127.0.0.1:$PW" cat < /dev/null > "$T/ws.log" 2>&1 &
PIDS="$PIDS $!"
WSPID=$!
(cd "$MD" && HOME="$T" exec ./maiden server --host 127.0.0.1 --port "$PM" --app ./app/build --data "$T/dust" --doc "$T/doc" \
    --config "$MD/maiden.yaml" < /dev/null > "$T/maiden.log" 2>&1) &
PIDS="$PIDS $!"
MPID=$!
for _ in $(seq 50); do curl -sf -o /dev/null "http://127.0.0.1:$PM/api/v1" && break; sleep 0.2; done
for _ in $(seq 25); do ss -ltn 2> /dev/null | grep -q "127.0.0.1:$PW " && break; sleep 0.2; done

echo "== listening addresses (loopback only)"
LISTEN=$(python3 -I "$HERE/listening.py" "$PM" "$PW")
WANT=$(printf '%s\n' "127.0.0.1:$PM" "127.0.0.1:$PW" | sort | tr '\n' ' ' | sed 's/ $//')
check "maiden and ws-wrapper listen on 127.0.0.1 only" "$LISTEN" "$WANT"

printf x=1 > "$T/x.txt"; printf y=2 > "$T/y.txt"
echo "== the editor"
code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }
check "web app is served" "$(code "$OWN/maiden/")" 200
check "api answers" "$(curl -s "$OWN/api/v1" | grep -c '"maiden"')" 1
check "write a file into dust" "$(code -X PUT -F "value=@$T/x.txt" "$OWN/api/v1/dust/code/note.lua")" 200
check "read it back" "$(curl -s "$OWN/api/v1/dust/code/note.lua" | tr -d '\n')" "x=1"
check "it is in the dust folder" "$(cat "$T/dust/code/note.lua" 2> /dev/null)" "x=1"

echo "== install a script from a zip (no Origin: curl, like maiden-repl or a script)"
check "install" "$(code -X POST "$OWN/api/v1/project/install?url=file://$T/victim.zip")" 201
check "files are under dust/code" "$(ls "$T/dust/code/victim" 2> /dev/null | tr '\n' ' ')" "victim.lua "
rm -rf "$T/dust/code/victim"

echo "== REPL websocket: who may connect"
wsp() { python3 -I "$HERE/ws_probe.py" "$PW" "$@" | tr '\n' ' '; }
check "no Origin (maiden-repl)" "$(wsp -)" "handshake=101 echo=ping-from-test "
check "maiden's own page (127.0.0.1)" "$(wsp "$OWN")" "handshake=101 echo=ping-from-test "
check "maiden's own page (localhost)" "$(wsp "http://localhost:$PM")" "handshake=101 echo=ping-from-test "
check "another website is refused" "$(wsp "$EVIL" | sed 's/handshake=[0-9]* //')" "closed "
check "another port on 127.0.0.1 is refused" "$(wsp "http://127.0.0.1:1" | sed 's/handshake=[0-9]* //')" "closed "
check "origin 'null' (a file:// page, a sandboxed iframe) is refused" "$(wsp null | sed 's/handshake=[0-9]* //')" "closed "

echo "== maiden: cross-site requests and DNS rebinding"
check "page on another site: POST install is refused" \
    "$(code -X POST -H "Origin: $EVIL" -H 'Content-Type: text/plain' "$OWN/api/v1/project/install?url=file://$T/victim.zip")" 403
check "nothing was installed by it" "$(ls "$T/dust/code" | tr '\n' ' ')" "note.lua "
check "page on another site: GET of dust is refused" "$(code -H "Origin: $EVIL" "$OWN/api/v1/dust")" 403
check "rebinding: Host evil.example is refused" "$(code -H "Host: evil.example:$PM" "$OWN/api/v1/dust")" 403
check "rebinding: a wrong port in Host is refused" "$(code -H "Host: 127.0.0.1:1" "$OWN/api/v1/dust")" 403
check "Host localhost works" "$(code -H "Host: localhost:$PM" "$OWN/api/v1/dust")" 200
check "own Origin works (the web app's requests)" "$(code -H "Origin: $OWN" "$OWN/api/v1/dust")" 200
check "own Origin works for a write" "$(code -X PUT -H "Origin: $OWN" -F "value=@$T/y.txt" "$OWN/api/v1/dust/code/note2.lua")" 200

echo "== the systemd unit API is off on Linux"
check "unit status is not served" "$(code "$OWN/api/v1/unit/norns-main.service")" 404
check "unit restart is not served" "$(code "$OWN/api/v1/unit/norns-main.service?do=restart")" 404

[ $FAILS -eq 0 ] && echo "maiden_test: all passed" || echo "maiden_test: $FAILS failed"
if [ $FAILS -ne 0 ]; then echo "--- maiden.log"; tail -5 "$T/maiden.log"; echo "--- ws.log"; tail -3 "$T/ws.log"; fi
[ $FAILS -eq 0 ]
