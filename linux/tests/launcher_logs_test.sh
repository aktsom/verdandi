#!/bin/bash
# the files the launcher makes in the norns home (docs/port/clean-layout.md): logs/ with the last runs kept, logs/crash/, cache/ for the libraries' caches with a
# size cap; nothing of that loose in the home or in a hidden .cache folder. two headless starts of the same home.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "${T:?}"' EXIT
FAIL=0
ok() { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; FAIL=1; }
H="$T/home"
mkdir -p "$H"
ln -s "$REPO" "$H/norns"

mkdir -p "$T/account-home"
# the account's own HOME is an empty scratch folder: whatever the launcher writes outside the norns home lands in it and is found below
run() { HOME="$T/account-home" NORNS_HOME="$H" "$REPO/linux/tests/norns_probe.sh" "$REPO/linux/tests/probe_dirs.lua" "$T/probe$1.log" > /dev/null 2>&1; }
# (the probe starts norns with --terminal: matron's own output is the probe's log, so norns.log stays empty here; sclang.log and jackd.log are the real files)
run 1
P1="$T/probe1.log"
[ -f "$H/logs/norns.log" ] && ok "first start: logs/norns.log exists (matron's output goes there without --terminal)" || bad "first start: no logs/norns.log"
grep -q "engines: \[" "$H/logs/sclang.log" 2>/dev/null && ok "logs/sclang.log has the run" || bad "no logs/sclang.log with the run"
[ -f "$H/logs/jackd.log" ] && ok "logs/jackd.log" || bad "no logs/jackd.log"
[ -d "$H/logs/crash" ] && ok "logs/crash/ exists (and is empty: a crash report is made only by a crash)" || bad "no logs/crash"
[ -z "$(ls "$H/logs/crash")" ] && ok "no crash report, no empty crash-report.txt" || bad "crash folder not empty: $(ls "$H/logs/crash")"
[ ! -e "$H/crash-report.txt" ] && ok "no crash-report.txt in the home" || bad "crash-report.txt in the home"
for f in norns.log sclang.log jackd.log maiden.log launcher.log; do
    [ -e "$H/$f" ] && bad "$f is loose in the home" || true
done
ok "no log is loose in the home"
grep -q "PROBE dirs cache.$H/cache.64M" "$P1" && ok "XDG_CACHE_HOME is <home>/cache and the shader cache is capped at 64M" || bad "cache environment: $(grep 'PROBE dirs cache' "$P1")"
[ -d "$H/cache" ] && ok "cache/ exists" || bad "no cache/"
[ ! -e "$H/.cache" ] && ok "no hidden .cache folder in the home" || bad "a hidden .cache was made: $(ls "$H/.cache")"
grep -q "PROBE dirs tidy.$REPO/linux/tidy.sh" "$P1" && ok "NORNS_TIDY names the tool (the CLEAN UP page runs it)" || bad "NORNS_TIDY"

run 2
[ -f "$H/logs/norns.1.log" ] && ok "second start: the previous run's norns log is norns.1.log" || bad "no norns.1.log"
grep -q "engines: \[" "$H/logs/sclang.1.log" 2>/dev/null && ok "the first run's sclang log survived the second start as sclang.1.log" || bad "sclang.1.log does not hold the first run"
grep -q "engines: \[" "$H/logs/sclang.log" 2>/dev/null && ok "and sclang.log is the second run" || bad "sclang.log of the second run"
[ -f "$H/logs/jackd.1.log" ] && ok "jackd keeps its previous run too" || bad "jackd.1.log missing"
[ $(ls "$H/logs" | grep -c '^norns\.') -le 5 ] && ok "at most 5 runs of a log" || bad "too many norns logs"

[ -z "$(ls -A "$T/account-home")" ] && ok "the launcher wrote nothing into the account's own home (only into the norns home)" || bad "outside the norns home: $(cd "$T/account-home" && find . | head)"

[ $FAIL -eq 0 ] && echo "launcher_logs_test: all passed"
exit $FAIL
