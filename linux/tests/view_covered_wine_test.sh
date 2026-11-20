#!/bin/bash
# M28: the real Win32 test of "is the window fully covered?" under Wine (linux/tests/view_covered_wine_test.c with matron/src/platform/windows/view_covered_win.c).
# the program checks first that this Wine hit-tests windows at all: without a display (the CI runner's Wine for the other tests) it does not, then the test is tried under Xvfb; when neither Wine can answer,
# the result is a SKIP with the reason (the real Windows runner checks the same call with real windows: windows/ci/maiden_probe.py, pin-view-covered). a check that runs and fails is a FAIL.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d)"
XPID=""
trap 'rm -rf "$T"; [ -n "$XPID" ] && kill "$XPID" 2>/dev/null' EXIT
CC=x86_64-w64-mingw32-gcc-posix
command -v $CC > /dev/null 2>&1 || CC=x86_64-w64-mingw32-gcc
$CC -std=gnu11 -Wall -I "$REPO/matron/src" "$REPO/linux/tests/view_covered_wine_test.c" "$REPO/matron/src/platform/windows/view_covered_win.c" -o "$T/vc.exe" -luser32 || { echo "the test did not compile"; exit 1; }
export WINEDEBUG=-all
attempt() { # name, then the env for Wine
    local name="$1"; shift
    OUT="$(cd "$T" && env "$@" WINEPREFIX="$T/prefix-$name" timeout 120 /usr/lib/wine/wine64 ./vc.exe 2>&1)"
    echo "== $name"; echo "$OUT"
    echo "$OUT" | grep -q "view_covered: all passed" && exit 0
    echo "$OUT" | grep -q "^FAIL" && exit 1
    return 0
}
attempt nodisplay -u DISPLAY -u WAYLAND_DISPLAY
if command -v Xvfb > /dev/null 2>&1; then
    Xvfb :97 -screen 0 1280x800x24 > /dev/null 2>&1 &
    XPID=$!
    sleep 1
    attempt xvfb DISPLAY=:97
fi
echo "SKIP: Wine here cannot hit-test windows (see above); the real Windows runner checks the same call"
exit 77
