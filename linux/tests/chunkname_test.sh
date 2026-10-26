#!/bin/bash
# linux/tests/chunkname_test.sh <log-dir>: norns loads a script whose libraries locate themselves with debug.getinfo(1).source and _path.code, as nb does
# (include, dofile and require), on a real boot where the norns home is not /home/we. with NB_DIR (a checkout of github.com/sixolet/nb) the real nb library
# is loaded the way cheat codes 2 has it (lib/nb). prints "name: ok" / "name: FAIL ..." lines; exit 1 if any failed.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
OUT="${1:-$(mktemp -d)}"
mkdir -p "$OUT"
H="$(mktemp -d)"
trap 'rm -rf "$H"' EXIT
ln -s "$REPO" "$H/norns"
S="$H/dust/code/cc2probe"
mkdir -p "$S/lib/deep"
SELF='local mydir = debug.getinfo(1).source:match("@?" .. _path.code .. "(.*/)")'
cat > "$S/cc2probe.lua" <<L
$SELF
print("PROBE chunk script_dir", mydir)
print("PROBE chunk script_source", debug.getinfo(1, "S").source)
print("PROBE chunk lib", include(mydir .. "lib/libone"))
L
if [ -n "${NB_DIR:-}" ]; then
    mkdir -p "$S/lib" && cp -R "$NB_DIR" "$S/lib/nb" && rm -rf "$S/lib/nb/.git"
    cat >> "$S/cc2probe.lua" <<'L'
-- cheat codes 2 keeps nb in its own lib/nb and includes it by its path from dust/code; require by that path too
local nb = include("cc2probe/lib/nb/lib/nb")
print("PROBE chunk nb", type(nb), type(nb.players), type(nb.none))
local nb2 = require("cc2probe/lib/nb/lib/nb")
print("PROBE chunk nb require", type(nb2))
L
fi
cat >> "$S/cc2probe.lua" <<'L'
function init() print("PROBE chunk init") end
L
cat > "$S/lib/libone.lua" <<L
$SELF
return mydir .. "|" .. include(mydir .. "deep/libtwo")
L
cat > "$S/lib/deep/libtwo.lua" <<L
$SELF
return mydir .. "|" .. dofile(_path.code .. mydir .. "libthree.lua")
L
cat > "$S/lib/deep/libthree.lua" <<L
$SELF
return mydir .. "|" .. debug.getinfo(1, "S").source
L
NORNS_HOME="$H" "$HERE/norns_probe.sh" "$HERE/probe_chunkname.lua" "$OUT/chunkname.log" > /dev/null 2>&1
LOG="$OUT/chunkname.log"
FAIL=0
want() { # name, text that must be in the log
    if grep -qF -- "$2" "$LOG"; then echo "$1: ok"; else echo "$1: FAIL (no '$2' in $LOG)"; FAIL=1; fi
}
want "script finds its folder" "PROBE chunk script_dir	cc2probe/"
want "script chunk name is virtual" "PROBE chunk script_source	@/home/we/dust/code/cc2probe/cc2probe.lua"
want "libraries by include and dofile, nested" "PROBE chunk lib	cc2probe/lib/|cc2probe/lib/deep/|cc2probe/lib/deep/|@/home/we/dust/code/cc2probe/lib/deep/libthree.lua"
want "the script ran to init" "PROBE chunk init"
if [ -n "${NB_DIR:-}" ]; then
    want "real nb library loads (include of cc2probe/lib/nb/lib/nb, whose own include of lib/player works)" "PROBE chunk nb	table	table	table"
    want "and by require from dust/code" "PROBE chunk nb require	table"
else
    echo "real nb library: SKIP (NB_DIR not set)"
fi
if grep -q "load fail" "$LOG"; then echo "no load fail: FAIL"; grep -n "load fail" -B3 "$LOG" | head; FAIL=1; else echo "no load fail: ok"; fi
exit $FAIL
