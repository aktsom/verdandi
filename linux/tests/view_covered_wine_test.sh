#!/bin/bash
# M28: the real Win32 test of "is the window fully covered?" under Wine without a display (linux/tests/view_covered_wine_test.c with matron/src/platform/windows/view_covered_win.c)
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
CC=x86_64-w64-mingw32-gcc-posix
command -v $CC > /dev/null 2>&1 || CC=x86_64-w64-mingw32-gcc
$CC -std=gnu11 -Wall -I "$REPO/matron/src" "$REPO/linux/tests/view_covered_wine_test.c" "$REPO/matron/src/platform/windows/view_covered_win.c" -o "$T/vc.exe" -luser32 || { echo "the test did not compile"; exit 1; }
# no X display: Wine keeps the windows and their stacking order in its own server, and WindowFromPoint answers from there (the runner has no display)
unset DISPLAY WAYLAND_DISPLAY
export WINEPREFIX="$T/prefix" WINEDEBUG=-all
OUT="$(timeout 120 /usr/lib/wine/wine64 "$T/vc.exe" 2>&1)"
echo "$OUT"
echo "$OUT" | grep -q "view_covered: all passed"
