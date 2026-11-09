#!/usr/bin/env bash
# windows/ci/portable-tests.sh (M0a/M0b): the tests of the Linux version that use no hardware, no shell tools and no Linux-only headers, built and run with the compiler of the runner (MinGW gcc in MSYS2 UCRT64).
# they prove the compiler, the headers and the Lua of the toolchain can run the shared, portable code of norns, which is the "does the toolchain work" part of M0. everything that needs a shell (mkdir -p, ls, sh) is left out on purpose:
# on Windows that is the job of the busybox decision in docs/port/windows-plan.md, not of M0.
# also works on Linux (g++ and lua5.3 on the PATH), which is how it is checked before it is pushed.
#   LUA   the Lua 5.3 interpreter (default: lua5.3, then lua)
# the functions below are called through m0_run (shellcheck cannot see that)
# shellcheck disable=SC2329
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=windows/ci/lib.sh
. "$HERE/lib.sh"
REPO="$(cd "$HERE/../.." && pwd)"
cd "$REPO" || exit 1
T="${PT_TMP:-$(mktemp -d)}"
LUA="${LUA:-$(command -v lua5.3 || command -v lua)}"
EXE=""
case "$(uname -s)" in MINGW* | MSYS* | CYGWIN*) EXE=".exe" ;; esac

cpp_test() { # name source
    g++ -std=c++14 -I third-party/doctest -I matron/src "$2" -o "$T/$1$EXE" && "$T/$1$EXE"
}
lua_test() { # script
    "$LUA" "$1"
}

m0_init
m0_run pt-lua-version "$LUA" -v
m0_run pt-lua-colour lua_test linux/tests/colour_test.lua
m0_run pt-lua-clock-midi-out lua_test linux/tests/clock_midi_out_test.lua
for t in midi_ignore device_dedupe serialosc_conflict plugin_arch; do
    m0_run "pt-cpp-$t" cpp_test "$t" "linux/tests/${t}_test.cpp"
done
exit 0
