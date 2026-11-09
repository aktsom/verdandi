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

echo "== launcher"
$CC -municode -mwindows -O2 -Wall windows/launcher/verdandi.c -o "$T/app/Verdandi.exe" -static 2> /dev/null || { mkdir -p "$T/app"; $CC -municode -mwindows -O2 -Wall windows/launcher/verdandi.c -o "$T/app/Verdandi.exe" -static || exit 1; }
mkdir -p "$T/app/lua/core" "$T/app/supercollider" "$T/app/update"
touch "$T/app/lua/core/config.lua"; echo "test" > "$T/app/update/version.txt"
cat > "$T/stub.c" <<'STUB'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <windows.h>
int main(int argc, char **argv) {
    printf("stub %s\nHOME=%s\nNORNS_PLATFORM=%s\nVERDANDI_NULL_AUDIO=%s\nSDL_VIDEODRIVER=%s\n", argv[0], getenv("HOME"), getenv("NORNS_PLATFORM"), getenv("VERDANDI_NULL_AUDIO"), getenv("SDL_VIDEODRIVER"));
    for (int i = 1; i < argc; i++) printf("arg %s\n", argv[i]);
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
# a missing piece is said in plain words (headless: in the log), and nothing is started
rm -f "$T/app/norns.exe"
(cd "$T/app" && VERDANDI_NO_LINK=1 timeout 60 "$WINE" ./Verdandi.exe --headless --home="Z:$T/vhome2" > "$T/launcher2.out" 2>&1); rc=$?
ck "a missing norns.exe is reported plainly and the launcher stops with a code" "[ $rc -ne 0 ] && grep -q 'a part of the program is missing' '$T/vhome2/logs/launcher.log' && grep -q 'norns.exe' '$T/vhome2/logs/launcher.log'"
exit $fail
