#!/bin/bash
# stress_boot.sh [runs] [log dir]: the boot:headless check of run_all.sh, repeated, some runs under CPU load.
# thirds: idle, one busy loop per cpu, two per cpu. a failing run keeps its whole log in <log dir>/fail-<n>.log.
# prints one line per run and a summary; exit 1 if any run failed.

set -u
RUNS="${1:-36}"
OUT="${2:-$(mktemp -d)}"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
CPUS="$(nproc)"
mkdir -p "$OUT"
LOADPIDS=""

stop_load() {
    for p in $LOADPIDS; do kill "$p" 2> /dev/null; done
    LOADPIDS=""
}
trap stop_load EXIT

start_load() { # loops
    for _ in $(seq "$1"); do
        (while :; do :; done) &
        LOADPIDS="$LOADPIDS $!"
    done
}

fails=0
for n in $(seq "$RUNS"); do
    stop_load
    third=${STRESS_THIRD:-$(((n - 1) * 3 / RUNS))}
    case $third in
    0) load=0 ;;
    1) load=$CPUS ;;
    *) load=$((CPUS * 2)) ;;
    esac
    [ "$load" -gt 0 ] && start_load "$load"

    H="$(mktemp -d)"
    ln -s "$REPO" "$H/norns"
    mkdir -p "$H/dust/code/probe"
    cat > "$H/dust/code/probe/probe.lua" <<'LUA'
engine.name = "PolyPerc"
function init() print("PROBE script init ok") end
function key(n, z) print("PROBE key", n, z) end
function enc(n, d) print("PROBE enc", n, d) end
LUA
    LOG="$OUT/run-$n.log"
    t0=$(date +%s)
    NORNS_HOME="$H" "$REPO/linux/tests/norns_probe.sh" "$REPO/linux/tests/probe_boot.lua" "$LOG" > /dev/null 2>&1
    secs=$(($(date +%s) - t0))
    missing=""
    for want in "running post-startup" "PROBE engines.5" "PROBE script init ok" "PROBE loaded.probe.PolyPerc" \
        "PROBE key.2.1" "PROBE enc.1"; do
        grep -q "$want" "$LOG" || missing="$missing [$want]"
    done
    if [ -z "$missing" ]; then
        echo "run $n load=$load ${secs}s ok"
        rm -f "$LOG"
    else
        fails=$((fails + 1))
        mv "$LOG" "$OUT/fail-$n.log"
        # what the home had: jack and sclang logs
        cp "$H/logs/jackd.log" "$OUT/fail-$n.jackd.log" 2> /dev/null
        cp "$H/logs/sclang.log" "$OUT/fail-$n.sclang.log" 2> /dev/null
        echo "run $n load=$load ${secs}s FAIL missing:$missing"
    fi
    rm -rf "$H"
done
stop_load
echo "stress_boot: $RUNS runs, $fails failed; logs in $OUT"
[ "$fails" -eq 0 ]
