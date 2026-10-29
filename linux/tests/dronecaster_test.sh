#!/bin/bash
# the real dronecaster (github.com/tyleretters/dronecaster, cloned: DRONECASTER_DIR=<a clone> avoids the network; no network and no clone: skipped, said out loud) in a headless norns
# (linux/tests/norns_probe.sh: Xvfb, a dummy jackd, the real launcher), docs/port/KNOWN-ISSUES.md item 20. its engine lists /home/we/dust/code/dronecaster/engine/drones with
# PathName(...).entries and loads every file. two starts of the same home:
#   control  (NORNS_SC_VIRTUAL_HOME=0, what the installed package did): "Dictionary[ ]", "does not know this drone", silence on crone's outputs
#   fixed    (the launcher's default): the drones are compiled, a start request finds one, and there is signal on crone:output_1/2
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d)"
trap '[ -n "${KEEP_DIR:-}" ] && cp -r "$T" "$KEEP_DIR"; rm -rf "${T:?}"' EXIT
FAIL=0
ok() { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; FAIL=1; }
SRC="${DRONECASTER_DIR:-}"
if [ -z "$SRC" ]; then
    SRC="$T/clone"
    timeout 90 git clone -q --depth 1 https://github.com/tyleretters/dronecaster "$SRC" 2> /dev/null || { echo "SKIP: dronecaster could not be fetched (no network?)"; exit 0; }
fi
[ -d "$SRC/engine/drones" ] || { echo "SKIP: $SRC is not a dronecaster clone"; exit 0; }
command -v sclang > /dev/null && command -v xdotool > /dev/null || { echo "SKIP: sclang or xdotool missing"; exit 0; }
cc -std=gnu11 "$REPO/linux/tests/jack_peak.c" -o "$T/jack_peak" -ljack -lm || { echo "SKIP: libjack headers missing"; exit 0; }
N="$(ls "$SRC/engine/drones" | wc -l)"
DRONE="$(ls "$SRC/engine/drones" | head -n 1)"
DRONE="${DRONE%.scd}"
echo "dronecaster: $N drone files, starting '$DRONE'"

cat > "$T/probe.lua" << PROBE
#sleep 5
norns.script.load("code/dronecaster/dronecaster.lua")
#sleep 12
engine.start("$DRONE")
#sleep 4
#sh "$T/jack_peak" 2 crone:output_1 crone:output_2 >> "\$MARKS"
print("PROBE dronecaster done")
PROBE

run_home() { # name, env assignments... -> $T/<name>.sclang, <name>.marks
    local name="$1"; shift
    local H="$T/$name"
    mkdir -p "$H/dust/code"
    ln -s "$REPO" "$H/norns"
    cp -a "$SRC" "$H/dust/code/dronecaster"
    env NORNS_HOME="$H" "$@" "$REPO/linux/tests/norns_probe.sh" "$T/probe.lua" "$T/$name.log" > /dev/null 2>&1
    cp "$H/logs/sclang.log" "$T/$name.sclang" 2> /dev/null
    cp "$H/probe.marks" "$T/$name.marks" 2> /dev/null
}

echo "== control: without the SuperCollider extension (the installed package's behaviour)"
run_home control NORNS_SC_VIRTUAL_HOME=0
grep -q "compiling drones in /home/we/dust/code/dronecaster/engine/drones" "$T/control.sclang" && ok "the engine looks in /home/we/dust/code/dronecaster/engine/drones (the log line of the report)" || { bad "no compiling line"; tail -5 "$T/control.sclang"; }
grep -q "does not know this drone: $DRONE" "$T/control.sclang" && ok "the start request says: dronecaster does not know this drone" || bad "no 'does not know' line (control)"
grep -q "PEAK 0.00000" "$T/control.marks" && ok "silence on crone:output_1/2" || bad "control marks: $(cat "$T/control.marks" 2> /dev/null)"

echo "== fixed: the launcher's default"
run_home fixed
grep -q "compiling drones in /home/we/dust/code/dronecaster/engine/drones" "$T/fixed.sclang" && ok "the same engine, the same path" || bad "no compiling line (fixed)"
KEYS="$(python3 -I - "$T/fixed.sclang" << 'PY'
import sys
t = open(sys.argv[1], errors="replace").read()
i = t.find("Dictionary[")
print(t[i:].split("start requested")[0].count("-> a SynthDef") if i >= 0 else 0)
PY
)"
# sclang prints only the first 19 entries of a long dictionary and ends the line with "...etc...": so 19 shown plus that marker means there are more
if [ "$KEYS" -ge 19 ] && { [ "$N" -le 19 ] || grep -q "etc\.\.\." "$T/fixed.sclang"; }; then ok "the dictionary holds drones (the log shows the first $KEYS of $N; the engine compiled every file)"; else bad "drones in the dictionary: $KEYS shown of $N"; fi
grep -q "start requested for name: $DRONE" "$T/fixed.sclang" && ! grep -q "does not know this drone" "$T/fixed.sclang" && ok "the start request finds '$DRONE'" || bad "start request (fixed)"
PEAK="$(sed -n 's/^PEAK \([0-9.]*\) .*/\1/p' "$T/fixed.marks" | tail -n 1)"
[ -n "$PEAK" ] && awk -v p="$PEAK" 'BEGIN { exit !(p > 0.01) }' && ok "signal on crone's outputs: peak $PEAK" || bad "no signal (peak '$PEAK'; $(cat "$T/fixed.marks" 2> /dev/null))"
grep -q "^ERROR" "$T/fixed.sclang" && { bad "ERROR lines in the fixed sclang.log"; grep "^ERROR" "$T/fixed.sclang" | sort | uniq -c | head -5; } || ok "no ERROR line in sclang.log"

[ $FAIL = 0 ] && echo "dronecaster_test: all passed"
exit $FAIL
