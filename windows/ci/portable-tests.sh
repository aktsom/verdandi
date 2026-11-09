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
EXE=""
case "$(uname -s)" in MINGW* | MSYS* | CYGWIN*) EXE=".exe" ;; esac
# the Lua of the toolchain: LUA, else the one msys2-deps.sh built, else a lua5.3/lua on the PATH. none: the Lua tests are SKIPped with a reason (never run with an empty command)
LUA="${LUA:-}"
for c in "$PWD/m0-work/prefix/bin/lua$EXE" "$(command -v lua5.3 || true)" "$(command -v lua || true)"; do
    if [ -z "$LUA" ] && [ -n "$c" ] && [ -x "$c" ]; then LUA="$c"; fi
done

# doctest: a submodule (third-party/doctest, needs a recursive checkout), else the MSYS2 package, else fetched from the upstream repository
ensure_doctest() {
    [ -f third-party/doctest/doctest/doctest.h ] && return 0
    git submodule update --init third-party/doctest > /dev/null 2>&1 && [ -f third-party/doctest/doctest/doctest.h ] && return 0
    if command -v pacman > /dev/null 2>&1; then pacman -S --noconfirm --needed mingw-w64-ucrt-x86_64-doctest > /dev/null 2>&1 || true; fi
    [ -f "$(dirname "$(command -v g++)")/../include/doctest/doctest.h" ] && { DOCTEST_INC="$(dirname "$(command -v g++)")/../include"; return 0; }
    return 1
}
DOCTEST_INC="third-party/doctest"

cpp_test() { # name source
    g++ -std=c++14 -I "$DOCTEST_INC" -I matron/src "$2" -o "$T/$1$EXE" && "$T/$1$EXE"
}
lua_test() { # script
    "$LUA" "$1"
}

m0_init
SUMMARY="$M0_OUT/portable-summary.txt"
: > "$SUMMARY"
if [ -n "$LUA" ]; then
    m0_run pt-lua-version "$LUA" -v
    m0_run pt-lua-colour lua_test linux/tests/colour_test.lua
    m0_run pt-lua-clock-midi-out lua_test linux/tests/clock_midi_out_test.lua
else
    for n in pt-lua-version pt-lua-colour pt-lua-clock-midi-out; do m0_skip "$n" "no Lua 5.3 available (lua53-build failed?)"; done
fi
if ensure_doctest; then
    for t in midi_ignore device_dedupe serialosc_conflict plugin_arch; do
        m0_run "pt-cpp-$t" cpp_test "$t" "linux/tests/${t}_test.cpp"
    done
else
    for t in midi_ignore device_dedupe serialosc_conflict plugin_arch; do m0_skip "pt-cpp-$t" "doctest.h not found (submodule, MSYS2 package)"; done
fi
# which compile and run, and which need porting (the first error of each)
{
    echo "portable tests: result and, for a failure, the first error line"
    for f in "$M0_OUT"/status/pt-*.status; do
        [ -e "$f" ] || continue
        n="$(basename "$f" .status)"
        read -r w _ < "$f"
        if [ "$w" = PASS ] || [ "$w" = SKIP ]; then
            printf '%-28s %s\n' "$n" "$w"
        else
            printf '%-28s FAIL: %s\n' "$n" "$(grep -m1 -E 'error|Error|FAILED|failed' "$M0_OUT/logs/$n.log" 2> /dev/null | cut -c1-160)"
        fi
    done
} > "$SUMMARY"
cat "$SUMMARY"
exit 0
