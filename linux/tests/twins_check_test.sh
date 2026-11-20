#!/bin/bash
# linux/tests/twins_check_test.sh [live]: linux/twins_check.py, the check that catches the next change of the script twins (docs/port/phase-m29.md, item 4).
#   no argument: the PINNED list (linux/tests/twins-pin: names read from twins at the commit in COMMIT) must be fully shipped; a library nobody ships (an invented requirement and an invented
#                UGen, added to a copy of the pin) must fail with a plain message that names them and says where the installer would fetch it; a bundled library without an x86_64 file must fail;
#                a fake twins whose installer line has another layout must stop with a plain message
#   "live":      the CURRENT twins (a shallow clone of its default branch) must be fully shipped. this one goes red when twins starts to need something new: that is its job
# needs sclang and the PortedPlugins pack (build/linux/portedplugins from linux/build.sh); prints SKIP and exits 77 without them (and without the network for "live")
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
C="$REPO/linux/twins_check.py"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
FAIL=0
ok() { echo "$1: ok"; }
bad() { echo "$1: FAIL $2"; FAIL=1; }
command -v python3 > /dev/null || { echo "SKIP twins_check_test: no python3"; exit 77; }
PACK="${NORNS_PORTED_TEST_PACK:-$REPO/build/linux/portedplugins/PortedPlugins}"
[ -f "$PACK/.verdandi-stamp" ] || { echo "SKIP twins_check_test: no stamped PortedPlugins pack at $PACK (linux/build.sh, or NORNS_PORTED_TEST_PACK)"; exit 77; }
command -v sclang > /dev/null || { echo "SKIP twins_check_test: no sclang"; exit 77; }

if [ "${1:-}" = live ]; then
    OUT="$(python3 -I "$C" --live --pack "$PACK" 2>&1)"; rc=$?
    [ $rc = 77 ] && { echo "$OUT"; exit 77; }
    echo "$OUT" | sed 's/^/    /'
    [ $rc = 0 ] && ok "the CURRENT twins needs nothing that Verdandi does not ship" || bad "live" "twins needs something that is not shipped (see the lines above)"
    exit $FAIL
fi

PIN="$REPO/linux/tests/twins-pin"
OUT="$(python3 -I "$C" --pin "$PIN" --pack "$PACK" 2>&1)"; rc=$?
[ $rc = 0 ] && printf '%s\n' "$OUT" | grep -q "twins_check: ok" && ok "the pinned list of twins (commit $(cut -c1-7 "$PIN/COMMIT")): every library it needs is shipped" || bad "pin" "$OUT"
printf '%s\n' "$OUT" | grep -q "3 requirements (AnalogChew AnalogLoss AnalogDegrade), bundled (TwinGrain)" && ok "...it read the three requirements and the bundled TwinGrain" || bad "pin lists" "$OUT"

# a library nobody ships: an invented requirement and an invented UGen in a copy of the pin
cp -R "$PIN" "$T/pin2"
echo "AnalogNewThing" >> "$T/pin2/requirements.txt"
echo "NobodyShipsThisGrain" >> "$T/pin2/ugens.txt"
echo "https://example.invalid/PortedPlugins.zip" > "$T/pin2/ZIP.txt"
OUT="$(python3 -I "$C" --pin "$T/pin2" --pack "$PACK" 2>&1)"; rc=$?
[ $rc = 1 ] && ok "a library nobody ships: the check fails (exit 1)" || bad "invented exit" "rc=$rc $OUT"
printf '%s\n' "$OUT" | grep -q "twins_check: FAIL: twins needs the SuperCollider library AnalogNewThing (the installer fetches it from https://example.invalid/PortedPlugins.zip) and nothing Verdandi ships provides it" && printf '%s\n' "$OUT" | grep -q "FAIL: twins needs the SuperCollider library NobodyShipsThisGrain and nothing Verdandi ships" && ok "...the message is plain: which library, where the installer would fetch it, that nothing ships it" || bad "invented text" "$OUT"
printf '%s\n' "$OUT" | grep -q "what to do:" && ok "...and says what to do" || bad "what to do" "$OUT"

# a bundled library with no x86_64 file (a fake clone of twins with the layout of the real installer line)
mkdir -p "$T/tw/lib/ugens" "$T/tw/lib/installer"
cat > "$T/tw/twins.lua" <<'LUA'
local installer = include("lib/installer/installer"):new{requirements = {"AnalogChew", "AnalogLoss", "AnalogDegrade"}, bundled = {TwinGrain = "lib/ugens", NewGrain = "lib/ugens"}, zip = "https://example.invalid/x.zip"}
LUA
echo 'SynthDef(\a, { Out.ar(0, SinOsc.ar(1)) });' > "$T/tw/lib/engine_twins.sc"
echo "x" > "$T/tw/lib/ugens/TwinGrain.sc.in"; mkdir -p "$T/tw/lib/ugens/x86_64"; echo x > "$T/tw/lib/ugens/x86_64/TwinGrain.so.in"
echo "x" > "$T/tw/lib/ugens/NewGrain.sc.in"
OUT="$(python3 -I "$C" --source "$T/tw" --pack "$PACK" 2>&1)"; rc=$?
[ $rc = 1 ] && printf '%s\n' "$OUT" | grep -q "twins bundles NewGrain but has no x86_64 file" && ! printf '%s\n' "$OUT" | grep -q "twins bundles TwinGrain" && ok "a bundled library without an x86_64 file fails with a plain message (and the one that has the file passes)" || bad "bundled" "rc=$rc $OUT"
# an installer line in another layout: stops with a plain message, no traceback
printf 'local installer = something_else()\n' > "$T/tw/twins.lua"
OUT="$(python3 -I "$C" --source "$T/tw" --pack "$PACK" 2>&1)"; rc=$?
printf '%s\n' "$OUT" | grep -q "cannot find the installer line" && ! printf '%s\n' "$OUT" | grep -q Traceback && ok "twins changed the layout of its installer line: a plain message that says the check has to be updated" || bad "layout" "rc=$rc $OUT"
# the real installer line of a clone of twins, if one is at hand (NORNS_TWINS): parsed the same way
if [ -n "${NORNS_TWINS:-}" ] && [ -f "$NORNS_TWINS/twins.lua" ]; then
    OUT="$(python3 -I "$C" --source "$NORNS_TWINS" --pack "$PACK" 2>&1)"; rc=$?
    [ $rc = 0 ] && ok "the clone in NORNS_TWINS: every library it needs is shipped" || bad "clone" "$OUT"
fi
exit $FAIL
