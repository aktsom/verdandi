#!/usr/bin/env bash
# windows/ci/build-norns.sh (M1): norns.exe and Verdandi.exe, and the DLLs they need, in $OUT (default ./m1-norns). run in the MSYS2 UCRT64 shell after windows/ci/msys2-deps.sh
# (DEPS_STEPS="packages lua libmonome"): the packages, Lua 5.3 and libmonome are in $PREFIX.
#   PREFIX   the prefix of msys2-deps.sh (default ./m0-work/prefix)     OUT   where the result goes     BLD   the CMake build folder
# every step is recorded for the report (lib.sh). a compile error does not stop the other files from compiling (ninja -k 0), so one run shows all of them.
# shellcheck disable=SC2329
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=windows/ci/lib.sh
. "$HERE/lib.sh"
REPO="$(cd "$HERE/../.." && pwd)"
PREFIX="${PREFIX:-$PWD/m0-work/prefix}"
OUT="${OUT:-$PWD/m1-norns}"
BLD="${BLD:-$REPO/build/win}"
export PATH="$PREFIX/bin:$PATH"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

configure() {
    local wprefix="$PREFIX"
    if command -v cygpath > /dev/null 2>&1; then wprefix="$(cygpath -m "$PREFIX")"; fi
    cmake -S "$REPO/windows/cmake" -B "$BLD" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$wprefix" \
        -DVERDANDI_VERSION_HASH="$(git -C "$REPO" rev-parse HEAD 2> /dev/null | cut -c1-7)"
}

build() {
    cmake --build "$BLD" -- -k 0
}

launcher() {
    mkdir -p "$BLD"
    gcc -municode -mwindows -O2 -Wall -Wextra "$REPO/windows/launcher/verdandi.c" -o "$BLD/Verdandi.exe" -static -lws2_32
}

# the DLLs of norns.exe that are not Windows's own (ldd lists them recursively); the result is a flat folder
collect() {
    mkdir -p "$OUT"
    cp "$BLD/norns.exe" "$BLD/Verdandi.exe" "$OUT/" || return 1
    local n=0 dll
    while read -r dll; do
        [ -f "$dll" ] && cp -u "$dll" "$OUT/" && n=$((n + 1))
    done < <(ldd "$BLD/norns.exe" | awk '/=> \// { print $3 }' | grep -i -E '^/(ucrt64|mingw64|usr)/' | sort -u)
    echo "copied $n DLLs:"
    find "$OUT" -maxdepth 1 -name '*.dll' | sort
    find "$OUT" -maxdepth 1 -type f -size +1k | wc -l
}

m0_init
m0_run norns-configure configure || exit 0
m0_run norns-build build
m0_run launcher-build launcher
if [ -f "$BLD/norns.exe" ] && [ -f "$BLD/Verdandi.exe" ]; then
    m0_run norns-collect collect
else
    m0_skip norns-collect "norns.exe or Verdandi.exe was not built"
fi
exit 0
