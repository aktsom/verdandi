#!/bin/bash
# norns/sidecar_shell.cpp and a command's stderr (docs/port/KNOWN-ISSUES.md item 22): the same source built with the desktop define (output = stdout only, stderr to the log) and without it
# (device and macOS: unchanged), plus the upstream test of the file built the way it always was
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "${T:?}"' EXIT
cd "$REPO" || exit 1
FAIL=0
inc="-I third-party/doctest -I norns"
main='#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>'
printf '%s\n' "$main" > "$T/main.cpp"
build() { g++ -std=c++14 $inc "$@" -o "$T/$OUT" 2>&1 || { echo "FAIL  build $OUT"; FAIL=1; return 1; }; }
for v in desktop device; do
    OUT="$v"; def=""; [ "$v" = desktop ] && def="-DNORNS_LINUX_DESKTOP=1"
    build $def "$T/main.cpp" linux/tests/sidecar_stderr_test.cpp norns/sidecar_shell.cpp -pthread || continue
    if "$T/$v" > "$T/$v.out" 2>&1; then echo "  ok    $v: $(grep -o 'test cases: *[0-9]* | *[0-9]* passed' "$T/$v.out")"; else echo "  FAIL  $v"; cat "$T/$v.out"; FAIL=1; fi
done
OUT=upstream
build "$T/main.cpp" tests/norns/sidecar_shell/test_sidecar_shell.cpp norns/sidecar_shell.cpp -pthread \
    && { "$T/upstream" > "$T/upstream.out" 2>&1 && echo "  ok    the upstream sidecar_shell tests (built without the define): $(grep -o 'test cases: *[0-9]* | *[0-9]* passed' "$T/upstream.out")" || { echo "  FAIL  upstream tests"; tail -20 "$T/upstream.out"; FAIL=1; }; }
[ $FAIL = 0 ] && echo "sidecar_stderr_test: all passed"
exit $FAIL
