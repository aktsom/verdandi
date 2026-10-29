#!/bin/bash
# linux/scan-fkeys.sh: finds the function keys scripts name, reads only, and says so
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "${T:?}"' EXIT
FAIL=0
ok() { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; FAIL=1; }
D="$T/dust/code"
mkdir -p "$D/one" "$D/two" "$D/three"
cat > "$D/one/one.lua" <<'L'
keyboard.code = function(c, v) if c == "F9" and v == 1 then print("x") end end
L
cat > "$D/two/two.lua" <<'L'
function keyboard.code(c, v)
  if c == 'F11' then toggle() elseif c == "F5" then other() end
end
L
echo 'print("no keys here")' > "$D/three/three.lua"
echo 'F12 in a text file "F12"' > "$D/three/notes.txt"
before="$(cd "$T" && find . -type f -exec md5sum {} + | sort)"
OUT="$("$REPO/linux/scan-fkeys.sh" "$D" 2>&1)"
has() { printf '%s\n' "$OUT" | grep -qF -- "$1"; }
has "3 .lua files, 2 of them set keyboard.code" && ok "counts the scripts and the keyboard readers" || bad "counts: $OUT"
has "F9: 1 script file(s) name it" && has "one/one.lua:1:" && ok "F9 found, with the file and line" || bad "F9"
has "F11: 1 script file(s) name it" && has "two/two.lua:2:" && ok "F11 found, with the file and line (single quotes)" || bad "F11"
has "F12: no script names it" && ok "F12: none (a .txt file does not count)" || bad "F12"
has "RESULT some scripts name those keys" && ok "the result sentence says what is given up" || bad "result"
[ "$(cd "$T" && find . -type f -exec md5sum {} + | sort)" = "$before" ] && ok "nothing was changed" || bad "files changed"
rm -f "$D/one/one.lua" "$D/two/two.lua"
OUT="$("$REPO/linux/scan-fkeys.sh" "$D" 2>&1)"
has "RESULT none of your scripts name F9, F11 or F12" && ok "no script: nothing is given up" || bad "empty result: $OUT"
"$REPO/linux/scan-fkeys.sh" "$T/missing" > /dev/null 2>&1 && bad "a missing folder is an error" || ok "a missing folder is an error"
[ $FAIL = 0 ] && echo "scan_fkeys_test: all passed"
exit $FAIL
