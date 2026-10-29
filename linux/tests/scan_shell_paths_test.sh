#!/bin/bash
# linux/scan-shell-paths.py (docs/port/KNOWN-ISSUES.md item 22): lists the scripts whose Lua runs shell commands naming /home/we or _path.*, with what each line does; skips comments; look-alikes ignored; read only
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "${T:?}"' EXIT
FAIL=0
ok() { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; FAIL=1; }
mkdir -p "$T/a" "$T/b" "$T/c" "$T/d" "$T/e"
echo 'local n = os.capture("ls /home/we/dust/audio/x/*.wav")' > "$T/a/a.lua"
echo 'os.execute("mkdir -p " .. _path.audio .. "x")' > "$T/b/b.lua"
printf -- '-- os.execute("rm /home/we/dust/x")\n--[[ os.capture("ls /home/we") ]]\nlocal p = "/home/weird"\nprint(os.capture("ls /home/weird"))\n' > "$T/c/c.lua"
echo 'local cmd = "curl -L -o " .. _path.data .. "f.zip " .. url' > "$T/d/d.lua"
echo 'local f = io.open("/home/we/dust/data/x", "r")' > "$T/e/e.lua"
sha="$(find "$T" -type f | sort | xargs sha256sum | sha256sum)"
OUT="$(python3 -I "$REPO/linux/scan-shell-paths.py" "$T" --json "$T/out.json")"
echo "$OUT" | grep -q "^a  .*reads output" && ok "a: os.capture of ls is 'reads output'" || bad "a: $OUT"
echo "$OUT" | grep -q "^b  .*runs" && ok "b: os.execute with _path.audio is 'runs'" || bad "b"
echo "$OUT" | grep -q "^d  .*builds" && ok "d: a curl command string with _path.data is 'builds'" || bad "d"
echo "$OUT" | grep -qE "^c  |^e  " && bad "c (comments, /home/weird) or e (io.open) listed" || ok "comments, /home/weird and plain file functions are not listed"
echo "$OUT" | grep -q "3 script(s)" && ok "3 scripts counted" || bad "count: $(echo "$OUT" | head -1)"
python3 -I -c "import json,sys; json.load(open(sys.argv[1]))" "$T/out.json" && ok "--json is valid" || bad "json"
[ "$sha" = "$(find "$T" -type f ! -name out.json | sort | xargs sha256sum | sha256sum)" ] && ok "the scanned files are unchanged" || bad "files changed"
[ $FAIL = 0 ] && echo "scan_shell_paths_test: all passed"
exit $FAIL
