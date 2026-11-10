#!/usr/bin/env bash
# linux/tests/cycle_check_test.sh: the check of the start/restart cycle test of the Windows CI (chk_cycles in windows/ci/smoke-m1.sh) on logs: the good run passes; the real failing run of the first version of the test
# (fixtures/cycle-failing: 2 starts, 1 restart, round 2 resumed no script and hung: "NO SCRIPT") fails AND the report carries the log of the failing round (launcher log, the last norns.log start without the OSC lists, sclang log).
set -u
cd "$(dirname "$0")/../.." || exit 1
T="$(mktemp -d)"
# shellcheck disable=SC2329
cleanup() { rm -rf "$T"; }
trap cleanup EXIT
fail=0
ck() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
# the functions of the check, cut out of the script (the script itself runs the whole smoke test when it is run)
{
    echo 'has() { if grep -q -E "$2" "$1" 2> /dev/null; then echo "found: $3"; else echo "NOT FOUND: $3"; return 1; fi; }'
    sed -n '/^CYCLES=/,/^chk_sclang() {/p' windows/ci/smoke-m1.sh | sed '$d'
} > "$T/funcs.sh"
run_check() { # home -> prints the output, returns the result of chk_cycles
    (
        EXE=""; WORK="$T"; M0_OUT="$T/out"; CYCLES=10
        # shellcheck disable=SC1091
        . "$T/funcs.sh"
        CYCLE_HOME="$1"
        chk_cycles
    )
}

echo "== a good run: 10 starts, 9 restarts"
H="$T/good"; mkdir -p "$H/logs"
: > "$H/logs/launcher.log"
for i in $(seq 1 10); do
    echo "2026-11-10 17:00:0$((i % 10)) launcher: norns.exe started" >> "$H/logs/launcher.log"
    if [ "$i" -lt 10 ]; then
        echo "launcher: norns.exe ended with exit code 0x0000002a" >> "$H/logs/launcher.log"
        echo "launcher: norns.exe asked for a restart (exit code 42): starting everything again (round $((i + 1)))" >> "$H/logs/launcher.log"
    else
        echo "launcher: norns.exe ended with exit code 0x00000000" >> "$H/logs/launcher.log"
    fi
    printf 'Verdandi Windows build 0.2.0 abc1234\nVERDANDI_CYCLE %d of 10 (start-up ok)\n' "$i" >> "$H/logs/norns.log"
done
echo "VERDANDI_CYCLE_DONE 10" >> "$H/logs/norns.log"
echo 0 > "$H/launcher.rc"; : > "$H/leftovers.txt"
run_check "$H" > "$T/good.out" 2>&1; rc=$?
ck "the good run passes" "[ $rc -eq 0 ] && grep -q 'found: 10 starts, 9 restarts' '$T/good.out'"

echo "== the real failing run of the first version"
H="$T/bad"; mkdir -p "$H/logs"
cp linux/tests/fixtures/cycle-failing/*.log "$H/logs/"
echo 124 > "$H/launcher.rc"; : > "$H/leftovers.txt"
run_check "$H" > "$T/bad.out" 2>&1; rc=$?
ck "the failing run fails" "[ $rc -ne 0 ]"
ck "it says what was counted (2 starts, 1 restart) and what was wanted" "grep -q 'started 2 times, restarted 1 times (wanted 10 and 9)' '$T/bad.out'"
ck "it says that the last round did not reach its end and that the launcher ended with 124" "grep -q 'VERDANDI_CYCLE_DONE 10' '$T/bad.out' && grep -q 'ended with 124' '$T/bad.out'"
ck "the report carries the launcher log" "grep -q 'launcher: norns.exe asked for a restart (exit code 42)' '$T/bad.out'"
ck "the report carries the log of the LAST start (round 2): its 'NO SCRIPT', not the first round's script" "grep -q 'SCRIPT ERROR: NO SCRIPT' '$T/bad.out' && ! grep -q 'VERDANDI_CYCLE_RESTART 1' '$T/bad.out'"
ck "the OSC command lists are left out" "! grep -q '^/set/level' '$T/bad.out'"
ck "and the sclang log is there" "grep -q 'sclang.log of the last start' '$T/bad.out'"
exit $fail
