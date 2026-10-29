#!/bin/bash
# the real mod nb_mxsynths (github.com/sonocircuit/nb_mxsynths, cloned: NB_MXSYNTHS_DIR=<a clone> avoids the network; no network and no clone: skipped, said out loud) in a headless norns
# (linux/tests/norns_probe.sh: Xvfb, a dummy jackd, the real launcher on SuperCollider 3.14.1 when the build tree or the package has it), docs/port/KNOWN-ISSUES.md item 21. the mod is
# started like its Lua does (/nb_mxsynths/init to sclang) and a note is sent to every one of its 11 voices; a voice whose SynthDef was not created answers "SynthDef not found" in sclang.log.
#   control (NORNS_SC_COMPAT=0, what the package did): mx_malone "build failed", and mx_malone and the 7 defs after it are missing
#   fixed   (the launcher's default): mx_malone builds, no "build failed", all 11 voices answer, and the user's files are byte for byte what they were
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d)"
. "$REPO/linux/tests/sc314_env.sh"
trap 'sc314_unlink_tree; rm -rf "${T:?}"' EXIT
FAIL=0
ok() { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; FAIL=1; }
SRC="${NB_MXSYNTHS_DIR:-}"
if [ -z "$SRC" ]; then
    SRC="$T/clone"
    timeout 90 git clone -q --depth 1 https://github.com/sonocircuit/nb_mxsynths "$SRC" 2> /dev/null || { echo "SKIP: nb_mxsynths could not be fetched (no network?)"; exit 0; }
fi
[ -f "$SRC/lib/nb_mxsynths.sc" ] || { echo "SKIP: $SRC is not an nb_mxsynths clone"; exit 0; }
command -v sclang > /dev/null && command -v xdotool > /dev/null || { echo "SKIP: sclang or xdotool missing"; exit 0; }
# SuperCollider 3.14.1 of the build tree where there is one (the package's version); else the sclang on the PATH, said in the output
if sc314_link_tree "$REPO" && sc314_path_dir "$REPO" "$T/sc314bin"; then echo "using the build tree's SuperCollider 3.14.1"; else echo "no build tree: using the sclang on the PATH ($(sclang -v 2>&1 | head -n 1))"; fi
VOICES="mx_synthy mx_icarus mx_casio mx_malone mx_toshiya mx_piano mx_epiano mx_mdapiano mx_kalimba mx_aaaaaa mx_triangles"
{
    echo "#sleep 5"
    echo 'osc.send({"localhost", 57120}, "/nb_mxsynths/init")'
    echo "#sleep 5"
    v=0
    for name in $VOICES; do
        echo "osc.send({\"localhost\", 57120}, \"/nb_mxsynths/note_on\", {\"$name\", $((v % 6)), 220, 0.5})"
        v=$((v + 1))
    done
    echo "#sleep 3"
    echo 'print("PROBE nb_mxsynths done")'
} > "$T/probe.lua"

run_home() { # name, env assignments...
    local name="$1"; shift
    local H="$T/$name"
    mkdir -p "$H/dust/code"
    ln -s "$REPO" "$H/norns"
    cp -a "$SRC" "$H/dust/code/nb_mxsynths"
    (cd "$H/dust/code/nb_mxsynths" && find . -type f -exec md5sum {} + | sort -k2) > "$T/$name.before"
    env NORNS_HOME="$H" "$@" "$REPO/linux/tests/norns_probe.sh" "$T/probe.lua" "$T/$name.log" > /dev/null 2>&1
    cp "$H/logs/sclang.log" "$T/$name.sclang" 2> /dev/null
    (cd "$H/dust/code/nb_mxsynths" && find . -type f -exec md5sum {} + | sort -k2) > "$T/$name.after"
}
missing() { for name in $VOICES; do grep -q "SynthDef not found.*\b$name\b\|$name.*not found" "$T/$1.sclang" 2> /dev/null && echo -n "$name "; done; }

echo "== control: without the SynthDef compatibility folder (what the package did)"
run_home control NORNS_SC_COMPAT=0
grep -q "SynthDef mx_malone build failed" "$T/control.sclang" && ok "the log line of the report: SynthDef mx_malone build failed" || { bad "no 'mx_malone build failed' in the control run"; tail -5 "$T/control.sclang"; }
M="$(missing control)"
[ -n "$M" ] && ok "voices missing in the control run: $M" || bad "the control run lost no voice (is the harness sending notes?)"

echo "== fixed: the launcher's default"
run_home fixed
grep -q "build failed" "$T/fixed.sclang" && { bad "a SynthDef still fails to build"; grep "build failed\|^ERROR" "$T/fixed.sclang" | head -3; } || ok "no 'build failed' in sclang.log"
grep -q "nb mxsynths initialized" "$T/fixed.sclang" && ok "the mod reports: nb mxsynths initialized" || bad "mod did not initialise"
grep -q "mx_malone" "$T/fixed.sclang" && grep -q "K2A" "$T/fixed.sclang" && ok "the log says which def was adjusted (mx_malone, K2A.ar)" || bad "no compat log line"
M="$(missing fixed)"
[ -z "$M" ] && ok "all 11 voices exist on SuperCollider $(grep -o 'SuperCollider 3\.[0-9.]*' "$T/fixed.sclang" | head -n 1 | sed 's/SuperCollider //'): no 'SynthDef not found'" || bad "voices missing: $M"
cmp -s "$T/fixed.before" "$T/fixed.after" && ok "the mod's files in dust/code are unchanged (nothing of the user's is edited)" || bad "mod files changed"
grep -q "^ERROR" "$T/fixed.sclang" && { bad "ERROR lines in the fixed sclang.log"; grep "^ERROR" "$T/fixed.sclang" | sort | uniq -c | head -5; } || ok "no ERROR line"

[ $FAIL = 0 ] && echo "nb_mxsynths_test: all passed"
exit $FAIL
