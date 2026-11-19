#!/bin/bash
# linux/tests/console_ports_linux_test.sh (M25): another program that holds the console port 5555 (norns) or 5556 (sclang) must not stop Verdandi. the Linux twin of console_ports_wine_test.sh (M22).
#   1. linux/console-ports.sh: the port choice, the holder's name, the plain line, the copy of maiden's page with the ports in use
#   2. ws-wrapper: a port that is held does not crash it (the old wrapper died with a segmentation fault at the second try) and does not stop its child: the child runs, its output reaches the log, its exit status
#      is the wrapper's; "none" is a wrapper without a console
#   3. the real norns.sh (Xvfb, jackd dummy, sclang, maiden when it is built): a program holds 5555, 5556 or both: norns starts, SuperCollider's server runs, both consoles answer on the NEW ports, maiden's page
#      is told, the plain line is in norns.log, the holders are still there; with nothing held the default ports are used and nothing is copied
# usage: console_ports_linux_test.sh [MAIDEN_DIR]        PART=1|2|3 runs one part
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
CP="$REPO/linux/console-ports.sh"
WSW="$REPO/build/ws-wrapper/ws-wrapper"
MD="${1:-$(dirname "$REPO")/maiden}"
FAILS=0
ok() { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; FAILS=$((FAILS + 1)); }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: got '$2', want '$3'"; fi; }
has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1: '$3' not in '$2'" ;; esac; }
T="$(mktemp -d)"
HOLDERS=""
hold() { # port: a program (python3) listens on it
    python3 -I -c 'import socket,sys,time
s=socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind(("127.0.0.1", int(sys.argv[1]))); s.listen(5)
time.sleep(600)' "$1" > /dev/null 2>&1 &
    HOLDERS="$HOLDERS $!"
    for _ in $(seq 30); do "$CP" free "$1" || break; sleep 0.1; done
}
release_all() { if [ -n "$HOLDERS" ]; then kill $HOLDERS 2> /dev/null; wait $HOLDERS 2> /dev/null; fi; HOLDERS=""; }
XVFB_PID=""
RUN=""
stop_norns() {
    [ -n "$RUN" ] && kill "$RUN" 2> /dev/null && wait "$RUN" 2> /dev/null
    RUN=""
    for _ in $(seq 60); do pgrep -x jackd > /dev/null || pgrep -x norns > /dev/null || break; sleep 0.2; done
    pkill -9 -x norns 2> /dev/null; pkill -9 -x sclang 2> /dev/null; pkill -9 -x scsynth 2> /dev/null; pkill -9 -x jackd 2> /dev/null
    sleep 0.5
}
cleanup() { release_all; stop_norns; [ -n "$XVFB_PID" ] && kill "$XVFB_PID" 2> /dev/null; rm -rf "$T"; }
trap cleanup EXIT

want() { [ -z "${PART:-}" ] || [ "${PART:-}" = "$1" ]; }

if want 1; then
    echo "== linux/console-ports.sh"
    P1=47101; P2=47102
    check "a free port is used as it is" "$("$CP" choose $P1 0)" "$P1"
    hold $P1
    check "a port that is held is not free" "$("$CP" free $P1 && echo free || echo held)" "held"
    has "the holder is named with its process" "$("$CP" holder $P1)" "python3 (process "
    check "a held default moves to the first free port of default+100" "$(NORNS_PORT_WAIT=0 "$CP" choose $P1 0)" "$((P1 + 100))"
    check "the other console's port is never taken" "$(NORNS_PORT_WAIT=0 "$CP" choose $P1 $((P1 + 100)))" "$((P1 + 101))"
    has "the plain line names the program, the port and the new port" "$("$CP" why norns $P1 $((P1 + 100)))" "port $P1 is used by python3 (process "
    has "and says which console moves" "$("$CP" why norns $P1 $((P1 + 100)))" "the norns console in maiden uses port $((P1 + 100)) instead"
    has "no free port: the console is off and everything else runs" "$("$CP" why sclang $P1 0)" "the sclang console in maiden is off, everything else runs"
    check "nothing held: the holder says nothing" "$("$CP" holder $P2)" ""
    mkdir -p "$T/page" && echo "<html>app</html>" > "$T/page/index.html" && printf '{\n  "norns": "ws://maiden_app_location:5555",\n  "supercollider": "ws://maiden_app_location:5556"\n}\n' > "$T/page/repl-endpoints.json"
    "$CP" app-copy "$T/page" "$T/page-copy" 5655 5656
    check "the copy of maiden's page has the page" "$(cat "$T/page-copy/index.html")" "<html>app</html>"
    has "and the new ports in repl-endpoints.json" "$(cat "$T/page-copy/repl-endpoints.json")" '"norns": "ws://maiden_app_location:5655"'
    has "for both consoles" "$(cat "$T/page-copy/repl-endpoints.json")" '"supercollider": "ws://maiden_app_location:5656"'
    check "the original page is not touched" "$(grep -c 5555 "$T/page/repl-endpoints.json")" "1"
    release_all
fi

if want 2; then
    echo "== ws-wrapper with a port that is held"
    if [ ! -x "$WSW" ]; then bad "build/ws-wrapper/ws-wrapper is not built (linux/build.sh)"; else
        PW=47111
        hold $PW
        WS_WRAPPER_RETRIES=3 timeout 30 "$WSW" "ws://127.0.0.1:$PW" sh -c 'echo CHILD-RAN-$$; sleep 1; echo CHILD-DONE; exit 7' > "$T/wrap.out" 2>&1
        rc=$?
        check "the wrapper ends with the child's exit status (7), not with a crash (139) or an error (1)" "$rc" "7"
        has "the child ran (its output is in our output, the log of the program)" "$(cat "$T/wrap.out")" "CHILD-RAN-"
        has "the child went on to its end" "$(cat "$T/wrap.out")" "CHILD-DONE"
        has "the console is said to be off, with the reason" "$(cat "$T/wrap.out")" "the console at ws://127.0.0.1:$PW is off"
        if grep -q "Segmentation\|core dumped" "$T/wrap.out"; then bad "the wrapper crashed"; else ok "no crash message"; fi
        # a child that writes a lot while the port is tried must not be stopped by a full pipe (the output is read from the first moment)
        WS_WRAPPER_RETRIES=6 timeout 30 "$WSW" "ws://127.0.0.1:$PW" sh -c 'i=0; while [ $i -lt 4000 ]; do echo "line $i of a chatty child, padded padded padded padded padded"; i=$((i+1)); done; echo ALL-WRITTEN' > "$T/wrap-chatty.out" 2>&1
        grep -q "ALL-WRITTEN" "$T/wrap-chatty.out" && ok "a chatty child is not blocked while the port is tried (4000 lines, all written)" || bad "a chatty child was blocked while the port was tried"
        release_all
        timeout 20 "$WSW" none sh -c 'echo NO-CONSOLE; exit 3' > "$T/wrap-none.out" 2>&1
        check "the address none: no console, the child runs, its status is ours" "$?" "3"
        has "and says so" "$(cat "$T/wrap-none.out")" "the console is off"
        # a free port: the console works as before (a client gets what the child prints)
        timeout 40 "$WSW" "ws://127.0.0.1:47112" sh -c 'sleep 3; echo hello-from-child; sleep 8' > "$T/wrap-free.out" 2>&1 &
        WP=$!
        sleep 1
        out="$(python3 -I "$HERE/ws_repl.py" 47112 "" hello-from-child 12 2>&1)"
        has "a free port: the console answers as before" "$out" "ok:"
        kill $WP 2> /dev/null; wait $WP 2> /dev/null
        # a usage error is a message and a status, not a crash
        "$WSW" > "$T/wrap-usage.out" 2>&1; check "no arguments: the usage line and status 2" "$?" "2"
    fi
fi

if want 3; then
    echo "== the real norns.sh with the console ports held"
    if [ -z "${DISPLAY:-}" ]; then
        Xvfb :97 -screen 0 1280x800x24 > /dev/null 2>&1 &
        XVFB_PID=$!
        export DISPLAY=:97
        sleep 1
    fi
    export NORNS_JACK_DRIVER=dummy SDL_AUDIODRIVER=dummy NORNS_PORT_WAIT=1
    HAVE_MAIDEN=0
    [ -x "$MD/maiden" ] && HAVE_MAIDEN=1
    PM=$(python3 -I -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])')
    scenario() { # name, then the ports to hold
        local name="$1"
        shift
        local held="$*" want_n=5555 want_s=5556 H="$T/$name"
        mkdir -p "$H" && ln -s "$REPO" "$H/norns"
        for p in $held; do hold "$p"; done
        case " $held " in *" 5555 "*) want_n=5655 ;; esac
        case " $held " in *" 5556 "*) want_s=5656 ;; esac
        echo "-- $name: held: ${held:-nothing}; expected consoles: norns $want_n, sclang $want_s"
        NORNS_HOME="$H" NORNS_MAIDEN="$MD" NORNS_MAIDEN_PORT="$PM" "$REPO/linux/norns.sh" < /dev/null > "$H.out" 2>&1 &
        RUN=$!
        for _ in $(seq 400); do grep -q "running post-startup" "$H/logs/norns.log" 2> /dev/null && break; kill -0 "$RUN" 2> /dev/null || break; sleep 0.25; done
        grep -q "running post-startup" "$H/logs/norns.log" 2> /dev/null && ok "$name: norns started (post-startup reached)" || bad "$name: norns did not start: $(tail -5 "$H.out" | tr '\n' '|')"
        out="$(python3 -I "$HERE/ws_repl.py" "$want_n" "print('M25PING ' .. 40 + 2)\n" "M25PING 42" 40 2>&1)"
        has "$name: the norns console answers on port $want_n" "$out" "ok:"
        out="$(python3 -I "$HERE/ws_repl.py" "$want_s" '("M25SC " ++ Crone.server.serverRunning).postln;\x1b' "M25SC true" 90 2>&1)"
        has "$name: the sclang console answers on port $want_s, and its server runs" "$out" "ok:"
        if [ "$HAVE_MAIDEN" = 1 ]; then
            for _ in $(seq 40); do curl -s "http://127.0.0.1:$PM/maiden/repl-endpoints.json" > "$H.endpoints" 2> /dev/null && grep -q norns "$H.endpoints" && break; sleep 0.5; done
            has "$name: maiden's page names the norns console port $want_n" "$(cat "$H.endpoints")" "maiden_app_location:$want_n\""
            has "$name: and the sclang console port $want_s" "$(cat "$H.endpoints")" "maiden_app_location:$want_s\""
        else
            echo "  SKIP  $name: maiden is not built here (linux/maiden-build.sh): the page check is not made"
        fi
        if [ -n "$held" ]; then
            has "$name: the plain line is in the launcher's output" "$(cat "$H.out")" "console: port "
            has "$name: and in norns.log (the line on the screen)" "$(cat "$H/logs/norns.log")" "is used by python3"
            for p in $held; do "$CP" free "$p" && bad "$name: the program that held $p was disturbed" || ok "$name: the program that held $p still holds it"; done
        else
            [ ! -d "$H/.maiden-app" ] && ok "$name: nothing held: no copy of maiden's page, no note" || bad "$name: a copy of maiden's page was made without a reason"
        fi
        stop_norns
        release_all
    }
    scenario none
    scenario held-norns 5555
    scenario held-sclang 5556
    scenario held-both 5555 5556
fi

[ $FAILS -eq 0 ] && echo "console_ports_linux_test: all passed" || echo "console_ports_linux_test: $FAILS failed"
[ $FAILS -eq 0 ]
