#!/usr/bin/env bash
# the Windows code that can run on Linux under Wine: cross-compile with mingw-w64 (apt: g++-mingw-w64-x86-64, wine64) and run
#   - the JACK-compatible null backend (its unit test linux/tests/jack_null_test.c: block cadence on a Windows waitable timer, ring buffer, ports, connections)
#   - fnmatch / glob / the shell runner of the sidecar (linux/tests/windows_posix_test.cpp; the shell runner uses cmd.exe of Wine)
#   - the launcher (windows/launcher/verdandi.c) with stand-in programs: environment, folders, logs, sclang's relative arguments, --exit-after
# exit 0 = all passed. 77 = nothing to run here (no cross compiler or no Wine): the caller says SKIP.
set -u
cd "$(dirname "$0")/../.." || exit 1
CC=x86_64-w64-mingw32-gcc-posix; CXX=x86_64-w64-mingw32-g++-posix
command -v "$CC" > /dev/null || { CC=x86_64-w64-mingw32-gcc; CXX=x86_64-w64-mingw32-g++; }
command -v "$CC" > /dev/null || { echo "no mingw-w64 cross compiler"; exit 77; }
WINE=/usr/lib/wine/wine64
[ -x "$WINE" ] || WINE="$(command -v wine64 || command -v wine || true)"
[ -n "$WINE" ] || { echo "no Wine"; exit 77; }
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export WINEPREFIX="$T/prefix" WINEDEBUG=-all
INC=(-include matron/src/platform/windows/compat_win.h -I matron/src/platform/windows/include -I matron/src/platform/windows/jack_null/include -I .)
fail=0

echo "== jack_null"
$CC -std=gnu11 -O1 "${INC[@]}" linux/tests/jack_null_test.c matron/src/platform/windows/jack_null/jack_null.c -static -lwinmm -o "$T/jack_null_test.exe" || exit 1
timeout 120 "$WINE" "$T/jack_null_test.exe" || fail=1

echo "== posix stand-ins and shell runner"
$CC -std=gnu11 -O1 "${INC[@]}" -c matron/src/platform/windows/posix_compat.c -o "$T/pc.o" || exit 1
$CXX -std=gnu++14 -O1 "${INC[@]}" -c matron/src/platform/windows/sidecar_shell_win.cpp -o "$T/ssw.o" || exit 1
$CXX -std=gnu++14 -O1 "${INC[@]}" -c linux/tests/windows_posix_test.cpp -o "$T/wpt.o" || exit 1
$CXX "$T/wpt.o" "$T/pc.o" "$T/ssw.o" -static -lws2_32 -o "$T/windows_posix_test.exe" || exit 1
(cd "$T" && timeout 120 "$WINE" ./windows_posix_test.exe) || fail=1

echo "== audio bridge between two programs, and the audio chain with a fake sound card"
$CC -std=gnu11 -O1 -I matron/src/platform/windows linux/tests/bridge_host_tool.c -o "$T/bridge_host.exe" -static -lwinpthread || exit 1
$CC -std=gnu11 -O1 -I matron/src/platform/windows linux/tests/bridge_guest_tool.c -o "$T/bridge_guest.exe" -static -lwinpthread || exit 1
BN="vd-wine-$$"
(cd "$T" || exit 1
 timeout 60 "$WINE" ./bridge_guest.exe "$BN" > bridge_guest.out 2>&1 &
 timeout 60 "$WINE" ./bridge_host.exe "$BN" 8 > bridge_host.out 2>&1; wait)
cat "$T/bridge_host.out" "$T/bridge_guest.out"
if grep -q 'mean 0.200 peak 0.50' "$T/bridge_host.out" && grep -Eq 'freq (43[0-9]|44[0-9])\.' "$T/bridge_host.out" && grep -Eq 'underruns [0-2] drops 0' "$T/bridge_host.out" && grep -q 'the host closed the bridge' "$T/bridge_guest.out"; then
    echo "bridge (two Windows processes, named memory and event): ok"
else
    echo "FAIL bridge between two processes"; fail=1
fi
$CC -std=gnu11 -O1 "${INC[@]}" -I matron/src/platform/windows linux/tests/audio_chain_test.c matron/src/platform/windows/audio/audio_device.c matron/src/platform/windows/audio/audio_bridge_host.c matron/src/platform/windows/audio/exit_win.c matron/src/platform/windows/jack_null/jack_null.c -static -lwinmm -o "$T/audio_chain_test.exe" || exit 1
# the way norns.exe ends (SYSTEM > RESTART: exit code 42) with the card callback, crone, the bridge and scsynth running: ten times, always the code and never a crash
bad=0
for i in 1 2 3 4 5 6 7 8 9 10; do
    (cd "$T" && timeout 60 "$WINE" ./audio_chain_test.exe exit > /dev/null 2>&1); rc=$?
    [ "$rc" -eq 42 ] || { echo "FAIL fast exit $i: exit code $rc"; bad=1; }
done
[ "$bad" -eq 0 ] && echo "fast exit (TerminateProcess) ten times: exit code 42, no crash: ok" || fail=1
for sc in device small noguest busy notfound badrate latecrone preconnected; do
    (cd "$T" && timeout 90 "$WINE" ./audio_chain_test.exe "$sc" 2> /dev/null | grep -E '^FAIL|passed') || fail=1
done

echo "== crash report (a crash in nested calls; a crash with the stdio locks held by another thread)"
$CXX -std=gnu++14 -O1 -g0 -fno-omit-frame-pointer "${INC[@]}" linux/tests/crash_report_win_test.cc matron/src/platform/windows/crash_report_win.cc -static -ldbghelp -lpsapi -lwinpthread -o "$T/crash_test.exe" 2> "$T/crash_build.log" || { cat "$T/crash_build.log"; exit 1; }
for mode in null locked; do
    rm -rf "$T/crash_$mode"; mkdir -p "$T/crash_$mode"
    (cd "$T" && timeout 90 "$WINE" ./crash_test.exe "crash_$mode" "$mode" > "crash_$mode.out" 2>&1)
    rep=$(find "$T/crash_$mode" -name "*.txt" 2> /dev/null | head -1)
    if [ -n "$rep" ] && grep -q 'access violation' "$rep" && grep -q 'tried to write 0x0000000000000000' "$rep" && grep -q 'vd_test_inner_crash' "$rep" && grep -q 'vd_test_crash_target' "$rep" && grep -q '^modules:' "$rep" && grep -q 'crash_test.exe+0x' "$rep"; then
        echo "crash report ($mode): complete, with function names: ok"
        if [ "$mode" = null ]; then
            sed 's/crash_test\.exe+/norns.exe+/' "$rep" > "$T/crash_as_norns.txt"
            if python3 windows/ci/resolve_crash.py "$T/crash_test.exe" --report "$T/crash_as_norns.txt" | grep -q 'vd_test_inner_crash'; then echo "resolve_crash.py: the offsets of the report give the function names offline: ok"; else echo "FAIL resolve_crash.py"; fail=1; fi
        fi
    else
        echo "FAIL crash report ($mode)"; fail=1; [ -n "$rep" ] && cat "$rep"; cat "$T/crash_$mode.out" | head -20
    fi
done

echo "== launcher"
$CC -municode -mwindows -O2 -Wall windows/launcher/verdandi.c -o "$T/app/Verdandi.exe" -static -lws2_32 2> /dev/null || { mkdir -p "$T/app"; $CC -municode -mwindows -O2 -Wall windows/launcher/verdandi.c -o "$T/app/Verdandi.exe" -static -lws2_32 || exit 1; }
mkdir -p "$T/app/lua/core" "$T/app/supercollider" "$T/app/update"
mkdir -p "$T/app/dust-seed/code/awake/lib"; echo "-- seed" > "$T/app/dust-seed/code/awake/awake.lua"; echo "-- lib" > "$T/app/dust-seed/code/awake/lib/x.lua"
printf "9.9.9 abcdef1\nbuilt: test\n" > "$T/app/BUILD.txt"
touch "$T/app/lua/core/config.lua"; echo "test" > "$T/app/update/version.txt"
cat > "$T/stub.c" <<'STUB'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <windows.h>
int main(int argc, char **argv) {
    printf("stub %s\nHOME=%s\nNORNS_PLATFORM=%s\nVERDANDI_NULL_AUDIO=%s\nSDL_VIDEODRIVER=%s\nBRIDGE=%s\nAUDIO=%s\n", argv[0], getenv("HOME"), getenv("NORNS_PLATFORM"), getenv("VERDANDI_NULL_AUDIO"), getenv("SDL_VIDEODRIVER"), getenv("VERDANDI_BRIDGE"), getenv("VERDANDI_AUDIO"));
    { const char *bn = getenv("VERDANDI_BRIDGE"); if (bn) { char nm[200]; snprintf(nm, sizeof nm, "Local\\%s", bn); CreateFileMappingA(INVALID_HANDLE_VALUE, NULL, PAGE_READWRITE, 0, 4096, nm); } } /* what norns.exe does: the launcher waits for it before it starts sclang */
    for (int i = 1; i < argc; i++) printf("arg %s\n", argv[i]);
    for (int i = 0; i < 500; i++) printf("same line every time\n");
    char cwd[500]; GetCurrentDirectoryA(500, cwd); printf("cwd %s\n", cwd); fflush(stdout);
    Sleep(strstr(argv[0], "norns") ? 8000 : 500);
    return 0;
}
STUB
$CC "$T/stub.c" -o "$T/app/norns.exe" -static && cp "$T/app/norns.exe" "$T/app/supercollider/sclang.exe" || exit 1
(cd "$T/app" && VERDANDI_NO_LINK=1 timeout 60 "$WINE" ./Verdandi.exe --headless --exit-after=3 --home="Z:$T/vhome" > "$T/launcher.out" 2>&1)
L="$T/vhome/logs"
ck() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
ck "launcher log says norns.exe and sclang.exe started" "grep -q 'norns.exe started' '$L/launcher.log' && grep -q 'sclang.exe started' '$L/launcher.log'"
ck "norns got HOME with forward slashes, NORNS_PLATFORM=windows, the null audio driver and the dummy video driver" "grep -q 'HOME=Z:/' '$L/norns.log' && grep -q 'NORNS_PLATFORM=windows' '$L/norns.log' && grep -q 'VERDANDI_NULL_AUDIO=1' '$L/norns.log' && grep -q 'SDL_VIDEODRIVER=dummy' '$L/norns.log'"
ck "sclang started with relative ASCII arguments from the SuperCollider config folder" "grep -q '^arg sclang_conf.yaml' '$L/sclang.log' && grep -q 'cwd .*SuperCollider' '$L/sclang.log' && ! grep -q '^arg Z:' '$L/sclang.log'"
ck "sclang_conf.yaml names the norns classes and dust" "grep -q '/sc/core' '$T/vhome/.config/SuperCollider/sclang_conf.yaml' && grep -q '/dust' '$T/vhome/.config/SuperCollider/sclang_conf.yaml'"
ck "dust/code, dust/audio, dust/data, logs/crash and version.txt exist" "[ -d '$T/vhome/dust/code' ] && [ -d '$T/vhome/dust/audio' ] && [ -d '$T/vhome/dust/data' ] && [ -d '$L/crash' ] && [ -f '$T/vhome/version.txt' ]"
ck "--exit-after stopped norns.exe" "grep -q 'exit-after=3' '$L/launcher.log' || grep -q 'norns.exe ended' '$L/launcher.log'"
ck "a line that repeats 500 times is in the log once, with a note" "[ \$(grep -c 'same line every time' '$L/norns.log') -eq 1 ] && grep -q 'repeated 499 more times' '$L/norns.log'"
ck "first start: the seeded scripts were copied to dust/code" "[ -f '$T/vhome/dust/code/awake/awake.lua' ] && [ -f '$T/vhome/dust/code/awake/lib/x.lua' ]"
echo "-- edited by the user" > "$T/vhome/dust/code/awake/awake.lua"
(cd "$T/app" && VERDANDI_NO_LINK=1 timeout 60 "$WINE" ./Verdandi.exe --headless --exit-after=2 --home="Z:$T/vhome" > "$T/launcher1b.out" 2>&1)
ck "a second start leaves the scripts alone" "grep -q 'edited by the user' '$T/vhome/dust/code/awake/awake.lua'"
ck "the launcher log names the build (BUILD.txt) in its first lines" "head -n 3 '$L/launcher.log' | grep -q 'Verdandi build 9.9.9 abcdef1'"
ck "norns.exe and sclang got the name of the audio bridge" "grep -q '^BRIDGE=VerdandiBridge-[0-9]*-1' '$L/norns.log' && grep -q '^BRIDGE=VerdandiBridge-[0-9]*-1' '$L/sclang.log'"
# M2: exit code 42 from norns.exe (SYSTEM > RESTART, a new audio device) starts everything again, with a new bridge name; --null-audio tells norns not to open a sound card
cat > "$T/stub42.c" <<'STUB'
#include <stdio.h>
#include <stdlib.h>
#include <windows.h>
int main(int argc, char **argv) {
    (void)argc;
    printf("stub %s BRIDGE=%s AUDIO=%s\n", argv[0], getenv("VERDANDI_BRIDGE"), getenv("VERDANDI_AUDIO") ? getenv("VERDANDI_AUDIO") : "-"); fflush(stdout);
    { const char *bn = getenv("VERDANDI_BRIDGE"); if (bn) { char nm[200]; snprintf(nm, sizeof nm, "Local\\%s", bn); CreateFileMappingA(INVALID_HANDLE_VALUE, NULL, PAGE_READWRITE, 0, 4096, nm); } } /* what norns.exe does: the launcher waits for it before it starts sclang */
    char marker[600]; snprintf(marker, sizeof marker, "%s/restarted.txt", getenv("HOME"));
    FILE *f = fopen(marker, "r");
    if (!f) { f = fopen(marker, "w"); if (f) { fputs("x", f); fclose(f); } return 42; }
    fclose(f);
    Sleep(1500);
    return 0;
}
STUB
cp "$T/app/norns.exe" "$T/app/norns.real.exe" 2> /dev/null
$CC "$T/stub42.c" -o "$T/app/norns.exe" -static || exit 1
rm -rf "$T/vhome3"; mkdir -p "$T/vhome3"
(cd "$T/app" && VERDANDI_NO_LINK=1 timeout 60 "$WINE" ./Verdandi.exe --headless --null-audio --home="Z:$T/vhome3" > "$T/launcher3.out" 2>&1)
ck "norns.exe exit code 42 starts another round" "grep -q 'asked for a restart' '$T/vhome3/logs/launcher.log' && [ \$(grep -c 'norns.exe started' '$T/vhome3/logs/launcher.log') -eq 2 ]"
ck "the second round has another bridge name, and --null-audio reaches norns.exe" "grep -q 'BRIDGE=VerdandiBridge-[0-9]*-2' '$T/vhome3/logs/norns.log' && grep -q 'AUDIO=null' '$T/vhome3/logs/norns.log'"
ck "the launcher ends with code 0 after the second round" "grep -q 'norns.exe ended with exit code 0x00000000' '$T/vhome3/logs/launcher.log'"
# M2: the start order. norns.exe makes the audio bridge (a named memory) 1.5 s after it starts; sclang must not start before. a stale norns.exe of this folder from an earlier start must be stopped first.
cat > "$T/stubB.c" <<'STUB'
#include <stdio.h>
#include <stdlib.h>
#include <windows.h>
int main(int argc, char **argv) {
    (void)argc;
    printf("stub %s pid %lu\n", argv[0], (unsigned long)GetCurrentProcessId()); fflush(stdout);
    const char *b = getenv("VERDANDI_BRIDGE");
    if (b && argc == 1) {
        Sleep(1500);
        char name[200]; snprintf(name, sizeof name, "Local\\%s", b);
        CreateFileMappingA(INVALID_HANDLE_VALUE, NULL, PAGE_READWRITE, 0, 4096, name); /* (the handle stays open for the life of the process) */
        printf("bridge made\n"); fflush(stdout);
    }
    Sleep(argc > 1 ? 30000 : 3000);
    return 0;
}
STUB
$CC "$T/stubB.c" -o "$T/app/norns.exe" -static || exit 1
cp "$T/app/norns.exe" "$T/app/supercollider/sclang.exe"
rm -rf "$T/vhome4"; mkdir -p "$T/vhome4"
# a stale copy: the same program, started outside the launcher, sleeping 30 s
(cd "$T/app" && timeout 40 "$WINE" ./norns.exe stale > "$T/stale.out" 2>&1 &)
sleep 2
(cd "$T/app" && VERDANDI_NO_LINK=1 timeout 60 "$WINE" ./Verdandi.exe --headless --exit-after=8 --home="Z:$T/vhome4" > "$T/launcher4.out" 2>&1)
ck "a stale norns.exe of an earlier start is stopped before the new one starts" "grep -q 'stopping norns.exe (process [0-9]*) of an earlier start' '$T/vhome4/logs/launcher.log'"
ck "sclang starts only after norns.exe has made the audio bridge" "[ \$(grep -n 'audio bridge of norns.exe is ready' '$T/vhome4/logs/launcher.log' | cut -d: -f1) -lt \$(grep -n 'sclang.exe started' '$T/vhome4/logs/launcher.log' | cut -d: -f1) ] && grep -Eq 'ready after 1[4-9][0-9][0-9] ms' '$T/vhome4/logs/launcher.log'"
rm -f "$T/app/norns.exe"
# a missing piece is said in plain words (headless: in the log), and nothing is started
rm -f "$T/app/norns.exe"
(cd "$T/app" && VERDANDI_NO_LINK=1 timeout 60 "$WINE" ./Verdandi.exe --headless --home="Z:$T/vhome2" > "$T/launcher2.out" 2>&1); rc=$?
ck "a missing norns.exe is reported plainly and the launcher stops with a code" "[ $rc -ne 0 ] && grep -q 'a part of the program is missing' '$T/vhome2/logs/launcher.log' && grep -q 'norns.exe' '$T/vhome2/logs/launcher.log'"
exit $fail
