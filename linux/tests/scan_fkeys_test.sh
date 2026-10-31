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
mkdir -p "$D/four" "$D/five"
cat > "$D/four/four.lua" <<'L'
function keyboard.code(c, v)
  if keyboard.ctrl() and c == "M" and v == 1 then save() end
end
L
cat > "$D/five/five.lua" <<'L'
function keyboard.code(c, v)
  if keyboard.ctrl() and c == 'S' then save() end
end
L
echo 'F12 in a text file "F12"' > "$D/three/notes.txt"
before="$(cd "$T" && find . -type f -exec md5sum {} + | sort)"
OUT="$("$REPO/linux/scan-fkeys.sh" "$D" 2>&1)"
has() { printf '%s\n' "$OUT" | grep -qF -- "$1"; }
has "5 .lua files, 4 of them set keyboard.code" && ok "counts the scripts and the keyboard readers" || bad "counts: $OUT"
has "F9: 1 script file(s) name it" && has "one/one.lua:1:" && ok "F9 found, with the file and line" || bad "F9"
has "F11: 1 script file(s) name it" && has "two/two.lua:2:" && ok "F11 found, with the file and line (single quotes)" || bad "F11"
has "F12: no script names it" && ok "F12: none (a .txt file does not count)" || bad "F12"
has "RESULT some scripts name those keys" && ok "the result sentence says what is given up" || bad "result"
# Ctrl+M (mute, docs/port/box-style-plan.md): scripts that test keyboard.ctrl() and name the letter M
has "Ctrl+M: 2 script file(s) test keyboard.ctrl(); 1 of them name the letter M:" && has "four/four.lua:2:" && ok "Ctrl+M: found, with the file and line; five.lua tests ctrl but not M" || bad "Ctrl+M: $OUT"
has "RESULT Ctrl+M (mute) may be read by the script(s) above" && ok "the Ctrl+M result sentence" || bad "Ctrl+M result"
[ "$(cd "$T" && find . -type f -exec md5sum {} + | sort)" = "$before" ] && ok "nothing was changed" || bad "files changed"
# the arc keys (docs/port/arc-plan.md 5.3): 5 6 T Y G H B N, only in scripts that read the keyboard (keyboard.code names "5", "T"; keyboard.char gets "h")
mkdir -p "$D/six" "$D/seven"
cat > "$D/six/six.lua" <<'L'
function keyboard.code(c, v)
  if c == "5" and v == 1 then a() elseif c == 'T' then b() end
end
function keyboard.char(ch)
  if ch == "h" then c() end
end
L
cat > "$D/seven/seven.lua" <<'L'
-- no keyboard handler: a string "T" or "5" here is not a key
local names = {"T", "5", "H"}
L
OUT="$("$REPO/linux/scan-fkeys.sh" "$D" 2>&1)"
has "Arc keys 5 6 T Y G H B N: 1 script file(s) that read the keyboard name them:" && ok "arc keys: one script reads them" || bad "arc keys: $OUT"
has "six/six.lua:2:" && has "six/six.lua:5:" && ok "arc keys: the lines of keyboard.code and keyboard.char" || bad "arc keys lines: $OUT"
printf '%s\n' "$OUT" | grep -q "seven/seven.lua" && bad "a script with no keyboard handler is not reported" || ok "arc keys: a script that does not read the keyboard is not reported"
has "RESULT arc keys: scripts above read some of them" && ok "arc keys: the result sentence" || bad "arc keys result"
[ "$(cd "$T" && find . -type f -exec md5sum {} + | sort)" != "$before" ] || bad "the fixtures were not added"
rm -f "$D/six/six.lua"
OUT="$("$REPO/linux/scan-fkeys.sh" "$D" 2>&1)"
has "Arc keys 5 6 T Y G H B N: no script that reads the keyboard names them" && has "RESULT arc keys: no script reads them: nothing is given up" && ok "arc keys: none named, nothing given up" || bad "arc keys none: $OUT"
before="$(cd "$T" && find . -type f -exec md5sum {} + | sort)"
"$REPO/linux/scan-fkeys.sh" "$D" > /dev/null 2>&1
[ "$(cd "$T" && find . -type f -exec md5sum {} + | sort)" = "$before" ] && ok "still nothing was changed" || bad "files changed by the second scan"
rm -f "$D/one/one.lua" "$D/two/two.lua"
OUT="$("$REPO/linux/scan-fkeys.sh" "$D" 2>&1)"
has "RESULT none of your scripts name F9, F11 or F12" && ok "no script: nothing is given up" || bad "empty result: $OUT"
has "Ctrl+M: 2 script file(s) test keyboard.ctrl(); 1 of them name the letter M:" && ok "Ctrl+M still reported" || bad "Ctrl+M still"
rm -f "$D/four/four.lua"
OUT="$("$REPO/linux/scan-fkeys.sh" "$D" 2>&1)"
has "Ctrl+M: 1 script file(s) test keyboard.ctrl(); none of them name the letter M" && has "RESULT no script combines keyboard.ctrl with the letter M: Ctrl+M (mute) takes nothing" && ok "no script names M with ctrl: Ctrl+M takes nothing from anyone" || bad "Ctrl+M none: $OUT"
# Ctrl+Shift+M (the MIDI actions on and off, docs/port/midi-actions-plan.md): scripts that test keyboard.ctrl() AND keyboard.shift() and name the letter M
mkdir -p "$D/eight" "$D/nine" "$D/ten"
cat > "$D/eight/eight.lua" <<'L'
function keyboard.code(c, v)
  if keyboard.ctrl() and keyboard.shift() and c == "M" and v == 1 then both() end
end
L
cat > "$D/nine/nine.lua" <<'L'
function keyboard.code(c, v)
  if keyboard.ctrl() and c == "M" then only_ctrl() end
end
L
cat > "$D/ten/ten.lua" <<'L'
function keyboard.code(c, v)
  if keyboard.shift() and c == 'M' then only_shift() end
end
L
before="$(cd "$T" && find . -type f -exec md5sum {} + | sort)"
OUT="$("$REPO/linux/scan-fkeys.sh" "$D" 2>&1)"
has "Ctrl+Shift+M: 1 script file(s) test both keyboard.ctrl() and keyboard.shift(); 1 of them name the letter M:" && has "eight/eight.lua:2:" && ok "Ctrl+Shift+M: found, with the file and line; ctrl alone and shift alone are not reported" || bad "Ctrl+Shift+M: $OUT"
printf '%s\n' "$OUT" | grep -A3 "^Ctrl+Shift+M" | grep -q "nine/nine.lua\|ten/ten.lua" && bad "a script with only ctrl or only shift is not a Ctrl+Shift+M reader" || ok "Ctrl+Shift+M: nine.lua (ctrl) and ten.lua (shift) are not listed"
has "RESULT Ctrl+Shift+M (MIDI actions on/off) may be read by the script(s) above" && ok "the Ctrl+Shift+M result sentence names the choice" || bad "Ctrl+Shift+M result"
[ "$(cd "$T" && find . -type f -exec md5sum {} + | sort)" = "$before" ] && ok "Ctrl+Shift+M scan changed nothing" || bad "files changed by the Ctrl+Shift+M scan"
rm -f "$D/eight/eight.lua"
OUT="$("$REPO/linux/scan-fkeys.sh" "$D" 2>&1)"
has "Ctrl+Shift+M: 0 script file(s) test both keyboard.ctrl() and keyboard.shift(); none of them name the letter M" && has "RESULT no script combines keyboard.ctrl and keyboard.shift with the letter M: Ctrl+Shift+M (MIDI actions on/off) takes nothing" && ok "no script names Ctrl+Shift+M: it takes nothing from anyone" || bad "Ctrl+Shift+M none: $OUT"
"$REPO/linux/scan-fkeys.sh" "$T/missing" > /dev/null 2>&1 && bad "a missing folder is an error" || ok "a missing folder is an error"
[ $FAIL = 0 ] && echo "scan_fkeys_test: all passed"
exit $FAIL
