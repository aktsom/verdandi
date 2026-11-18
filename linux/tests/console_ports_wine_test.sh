#!/usr/bin/env bash
# M22 item 2 (docs/port/phase-m22.md): another program holds maiden's console port 5555 (norns) and/or 5556 (sclang). Verdandi must keep running, say plainly which program holds the port, and give maiden's page other ports.
#   part A: the launcher (windows/launcher/verdandi.c) under Wine with stand-in norns.exe/sclang.exe and a stand-in ws-wrapper that behaves like the OLD wrapper (bind fails -> exit 1): 5555 busy, 5556 busy, both busy
#   part B: the real ws-wrapper.exe (needs the Windows nng DLL: NNG_DLL=..., else this part is SKIPPED, and says so) with a busy port: the child keeps running and its exit code is the wrapper's
# env: NNG_DLL / NNG_INC (the Windows libnng DLL and the headers of the SAME version), LAUNCHER_SRC / WRAPPER_SRC replace the sources (to run the OLD code: "does the test fail without the fix"). exit 0 = passed, 77 = nothing to run here (no cross compiler or no Wine)
set -u
cd "$(dirname "$0")/../.." || exit 1
CC=x86_64-w64-mingw32-gcc-posix
command -v "$CC" > /dev/null || CC=x86_64-w64-mingw32-gcc
command -v "$CC" > /dev/null || { echo "SKIP no mingw-w64 cross compiler"; exit 77; }
WINE=/usr/lib/wine/wine64
[ -x "$WINE" ] || WINE="$(command -v wine64 || command -v wine || true)"
[ -n "$WINE" ] || { echo "SKIP no Wine"; exit 77; }
T="$(mktemp -d)"
trap 'kill $(jobs -p) 2> /dev/null; [ -n "${KEEP:-}" ] || rm -rf "$T"' EXIT
WS="$(command -v wineserver || ls /usr/lib/wine/wineserver* 2> /dev/null | head -n 1)"
export WINEPREFIX="$T/prefix" WINEDEBUG=-all
fail=0
ck() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
LSRC="${LAUNCHER_SRC:-windows/launcher/verdandi.c}"
mkdir -p "$T/app/lua/core" "$T/app/supercollider" "$T/app/update"
printf "9.9.9 abcdef1\nbuilt: test\n" > "$T/app/BUILD.txt"; touch "$T/app/lua/core/config.lua"; echo test > "$T/app/update/version.txt"
$CC -municode -mwindows -O2 -w "$LSRC" -I windows/launcher -o "$T/app/Verdandi.exe" -static -lws2_32 -liphlpapi || exit 1

# stand-in programs: norns.exe and sclang.exe live until they are asked to end or the launcher ends them
cat > "$T/stub.c" <<'STUB'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <windows.h>
int main(int argc, char **argv) {
    (void)argc;
    { const char *bn = getenv("VERDANDI_BRIDGE"); if (bn) { char nm[200]; snprintf(nm, sizeof nm, "Local\\%s", bn); CreateFileMappingA(INVALID_HANDLE_VALUE, NULL, PAGE_READWRITE, 0, 4096, nm); } }
    printf("stub %s alive\n", argv[0]); fflush(stdout);
    for (int i = 0; i < 600; i++) { Sleep(100); if (i % 10 == 0) { printf("tick %d\n", i / 10); fflush(stdout); } }
    return 0;
}
STUB
$CC "$T/stub.c" -o "$T/app/norns.exe" -static && cp "$T/app/norns.exe" "$T/app/supercollider/sclang.exe" || exit 1
# a stand-in listener (what holds the port in the test): listens on 127.0.0.1:PORT for SECONDS seconds
cat > "$T/listen.c" <<'STUB'
#include <winsock2.h>
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char **argv) {
    WSADATA w; WSAStartup(MAKEWORD(2, 2), &w);
    SOCKET s = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in a; memset(&a, 0, sizeof a); a.sin_family = AF_INET; a.sin_addr.s_addr = htonl(INADDR_LOOPBACK); a.sin_port = htons((unsigned short)atoi(argv[1]));
    if (bind(s, (struct sockaddr *)&a, sizeof a) != 0 || listen(s, 4) != 0) { printf("listener: cannot bind %s\n", argv[1]); return 1; }
    printf("listener: %s\n", argv[1]); fflush(stdout);
    Sleep((DWORD)atoi(argv[2]) * 1000);
    return 0;
}
STUB
$CC "$T/listen.c" -o "$T/stand-in-listener.exe" -static -lws2_32 || exit 1
# a stand-in wrapper that behaves like the OLD ws-wrapper: it tries to open the port and, when it cannot, ends with code 1 (nothing is run). it writes the URL it was given
cat > "$T/wrap.c" <<'STUB'
#include <winsock2.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(int argc, char **argv) {
    (void)argc;
    const char *c = strrchr(argv[1], ':'); int port = c ? atoi(c + 1) : 0;
    char f[600]; snprintf(f, sizeof f, "%s/wrapper-%d.txt", getenv("HOME"), port); FILE *o = fopen(f, "w"); if (o) { fputs(argv[1], o); fclose(o); }
    WSADATA w; WSAStartup(MAKEWORD(2, 2), &w);
    SOCKET s = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in a; memset(&a, 0, sizeof a); a.sin_family = AF_INET; a.sin_addr.s_addr = htonl(INADDR_LOOPBACK); a.sin_port = htons((unsigned short)port);
    if (bind(s, (struct sockaddr *)&a, sizeof a) != 0 || listen(s, 4) != 0) { fprintf(stderr, "ws-wrapper: nng_listener_start: Address in use\n"); Sleep(1500); return 1; }
    char cmd[2000]; snprintf(cmd, sizeof cmd, "\"%s\"", argv[2]);
    STARTUPINFOA si; PROCESS_INFORMATION pi; memset(&si, 0, sizeof si); si.cb = sizeof si;
    si.dwFlags = STARTF_USESTDHANDLES; si.hStdOutput = GetStdHandle(STD_OUTPUT_HANDLE); si.hStdError = GetStdHandle(STD_ERROR_HANDLE); si.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
    if (!CreateProcessA(NULL, cmd, NULL, NULL, TRUE, 0, NULL, NULL, &si, &pi)) return 4;
    WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD code = 0; GetExitCodeProcess(pi.hProcess, &code);
    return (int)code;
}
STUB
$CC "$T/wrap.c" -o "$T/app/ws-wrapper.exe" -static -lws2_32 || exit 1

# the ports the test uses must be free here, else the numbers 5555/5556 cannot be tested on this machine
for p in 5555 5556; do
    if (exec 3<> "/dev/tcp/127.0.0.1/$p") 2> /dev/null; then echo "SKIP port $p is in use on this machine, so the default ports cannot be tested here"; exit 77; fi
done

run() { # name seconds ports-to-occupy...
    local name="$1" secs="$2"; shift 2
    local home="$T/home-$name"; rm -rf "$home"; mkdir -p "$home"
    for p in "$@"; do (cd "$T" && timeout $((secs + 25)) "$WINE" ./stand-in-listener.exe "$p" $((secs + 20)) > "$T/listener-$name-$p.out" 2>&1 &) ; done
    [ $# -gt 0 ] && sleep 4
    (cd "$T/app" && VERDANDI_NO_LINK=1 timeout $((secs + 60)) "$WINE" ./Verdandi.exe --headless --exit-after="$secs" --home="Z:$home" > "$T/launcher-$name.out" 2>&1); echo $? > "$T/rc-$name"
    "$WS" -k 2> /dev/null
    sleep 1
}
check_alive() { # name: norns and sclang ran until the launcher ended them (the launcher's own end), no "ended" before
    local L="$T/home-$1/logs/launcher.log"
    ck "$1: norns.exe and sclang.exe started" "grep -q 'norns.exe started' '$L' && grep -q 'sclang.exe started' '$L'"
    ck "$1: Verdandi ran to the planned end (no early stop, no error)" "grep -q -- '--exit-after=.*: stopping norns.exe' '$L' && ! grep -q 'stopped early\|exited early\|Verdandi ended' '$L' && [ \"\$(cat '$T/rc-$1')\" = 0 ]"
    ck "$1: norns.log has the stand-in's ticks (the program ran, its output was kept)" "grep -q 'tick 3' '$T/home-$1/logs/norns.log'"
}

echo "== A0: no port is taken: the default ports are used, no note"
run free 8
check_alive free
ck "free: wrappers got 5555 and 5556" "grep -q ':5555' '$T/home-free/wrapper-5555.txt' && grep -q ':5556' '$T/home-free/wrapper-5556.txt'"
ck "free: no console note" "! grep -q 'console:' '$T/home-free/logs/launcher.log' && [ ! -f '$T/home-free/.verdandi-note' ]"

echo "== A1: 5555 is held by another program"
run p5555 8 5555
check_alive p5555
ck "p5555: the log says which program holds port 5555 and which port the norns console uses instead" "grep -q 'console: port 5555 is used by \(stand-in-listener.exe (process [0-9]*)\|another program\): the norns console in maiden uses port [0-9]* instead' '$T/home-p5555/logs/launcher.log'"
ck "p5555: the norns wrapper got another port, sclang kept 5556" "! grep -q ':5555' '$T/home-p5555/wrapper-5555.txt' 2> /dev/null && grep -q ':5556' '$T/home-p5555/wrapper-5556.txt' && ls '$T/home-p5555'/wrapper-*.txt | grep -qv 'wrapper-555[56]'"
ck "p5555: the window note says it in a plain line" "grep -q 'port 5555 is used by' '$T/home-p5555/.verdandi-note'"

echo "== A2: 5556 is held by another program"
run p5556 8 5556
check_alive p5556
ck "p5556: the log says which program holds port 5556" "grep -q 'console: port 5556 is used by \(stand-in-listener.exe (process [0-9]*)\|another program\): the sclang console in maiden uses port [0-9]* instead' '$T/home-p5556/logs/launcher.log'"
ck "p5556: sclang's wrapper got another port, norns kept 5555" "grep -q ':5555' '$T/home-p5556/wrapper-5555.txt' && ! grep -q ':5556' '$T/home-p5556/wrapper-5556.txt' 2> /dev/null"

echo "== A3: both are held"
run both 8 5555 5556
check_alive both
ck "both: two lines in the log, two different free ports" "[ \$(grep -c 'console: port 555[56] is used by' '$T/home-both/logs/launcher.log') -eq 2 ] && [ \$(ls '$T/home-both'/wrapper-*.txt | wc -l) -eq 2 ] && ! ls '$T/home-both'/wrapper-*.txt | grep -q 'wrapper-555[56]'"
ck "both: the note names both ports" "grep -q 'port 5555' '$T/home-both/.verdandi-note' && grep -q 'port 5556' '$T/home-both/.verdandi-note'"

echo "== B: the real ws-wrapper.exe with a busy port"
NNG="${NNG_DLL:-}"
[ -n "$NNG" ] && [ -f "$NNG" ] || NNG="$(ls build/package/cache/*/libnng*.dll build/package/*/libnng*.dll 2> /dev/null | head -n 1)"
if [ -z "$NNG" ] || [ ! -f "$NNG" ]; then
    echo "SKIP part B (the real wrapper): no Windows nng DLL (set NNG_DLL=path/libnng-1.dll). Part B runs in the Windows CI on the real build."
else
    mkdir -p "$T/inc" "$T/w"; cp -r "${NNG_INC:-/usr/include}/nng" "$T/inc/" 2> /dev/null || { echo "SKIP part B: no nng headers (libnng-dev)"; NNG=""; }
fi
if [ -n "$NNG" ] && [ -f "$NNG" ]; then
    D="$(dirname "$NNG")"
    $CC -municode -O2 -w -I"$T/inc" "${WRAPPER_SRC:-windows/ws-wrapper/ws_wrapper_win.c}" "$NNG" -lws2_32 -lpthread -o "$T/w/ws-wrapper.exe" || exit 1
    cp "$NNG" "$T/w/"; for d in libwinpthread-1.dll libwolfssl-46.dll libgcc_s_seh-1.dll; do [ -f "$D/$d" ] && cp "$D/$d" "$T/w/"; done
    cp "$T/app/norns.exe" "$T/w/child.exe"
    # does this wrapper + nng DLL open a websocket under Wine at all (a free port)? when it does not (nng_listener_create: Not supported, seen with nng 1.12 DLLs under Wine, also with the OLD wrapper) there is nothing to compare: SKIP
    (cd "$T/w" && timeout 12 "$WINE" ./ws-wrapper.exe ws://127.0.0.1:5558 "$(printf 'Z:%s' "$T/w/child.exe")" > "$T/wrap-free.out" 2>&1)
    if grep -q 'is open' "$T/wrap-free.out"; then
    (cd "$T" && timeout 60 "$WINE" ./stand-in-listener.exe 5557 50 > "$T/l5557.out" 2>&1 &); sleep 4
    (cd "$T/w" && timeout 40 "$WINE" ./ws-wrapper.exe ws://127.0.0.1:5557 "$(printf 'Z:%s' "$T/w/child.exe")" > "$T/wrap-real.out" 2>&1 & echo $! > "$T/wrap.pid")
    sleep 20
    ck "the real wrapper: 15 s after its port was refused the child is still running (it printed ticks)" "grep -q 'tick 10' '$T/wrap-real.out'"
    ck "the real wrapper: it said it runs on without its console" "grep -q 'runs on without its console' '$T/wrap-real.out'"
    [ -n "${SHOW:-}" ] && head -20 "$T/wrap-real.out"
    "$WS" -k 2> /dev/null; sleep 1
    else
        echo "SKIP part B: the real wrapper cannot open a websocket under Wine here even on a free port ($(head -n 1 "$T/wrap-free.out")). Part B runs on real Windows in the CI (smoke-m1.sh m22-busy-ports)."
    fi
fi
echo
[ "$fail" = 0 ] && echo "console ports: all passed" || echo "console ports: FAILED"
exit $fail
