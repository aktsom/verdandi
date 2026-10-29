#!/bin/bash
# linux/scan-sc-paths.py (docs/port/KNOWN-ISSUES.md item 20): lists the scripts whose .sc/.scd name /home/we, skips comments, ignores look-alikes, never writes.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "${T:?}"' EXIT
FAIL=0
ok() { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; FAIL=1; }
mkdir -p "$T/a/engine" "$T/b" "$T/c" "$T/d"
echo 'x = PathName("/home/we/dust/code/a/engine").entries;' > "$T/a/engine/Engine_A.sc"
echo '// "/home/we/dust/x" only in a comment
y = Platform.userHomeDir;' > "$T/b/Engine_B.sc"
echo 'z = "/home/weird/x";' > "$T/c/Engine_C.sc"
echo '"cat /home/we/dust/data/x".unixCmdGetStdOut;' > "$T/d/run.scd"
sha="$(find "$T" -type f | sort | xargs sha256sum | sha256sum)"
OUT="$(python3 -I "$REPO/linux/scan-sc-paths.py" "$T" --json "$T/out.json")"
echo "$OUT" | grep -q "^a\b\|\ba\b" && ok "script a (folder listing) is listed" || bad "a not listed: $OUT"
echo "$OUT" | grep -q "\bd\b" && ok "script d (shell command) is listed" || bad "d not listed"
echo "$OUT" | grep -qE "(^|[^a-z])b([^a-z]|$)" && echo "$OUT" | grep -q "Engine_B" && bad "b (comment only) listed" || ok "a comment alone does not list a script"
echo "$OUT" | grep -q "Engine_C" && bad "look-alike /home/weird listed" || ok "/home/weird is not /home/we"
python3 -I -c "import json,sys; json.load(open(sys.argv[1]))" "$T/out.json" && ok "--json writes valid json" || bad "json"
[ "$sha" = "$(find "$T" -type f ! -name out.json | sort | xargs sha256sum | sha256sum)" ] && ok "the scanned files are unchanged" || bad "scanned files changed"
[ $FAIL = 0 ] && echo "scan_sc_paths_test: all passed"
exit $FAIL
