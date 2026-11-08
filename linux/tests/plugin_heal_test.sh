#!/bin/bash
# linux/tests/plugin_heal_test.sh: linux/plugin-heal.sh on fake norns homes. at every start any wrong-architecture SuperCollider plug-in that would stop sclang (the ones
# linux/plugin_arch_check finds in the user's extension folder and dust/code) is moved aside into disabled/ with a manifest line (verdandi tidy disable), one log line and one
# plain note; when Verdandi ships an x86-64 replacement (NamAmp, mi-UGens) the note says so and the seed puts it in. prints "name: ok" / "name: FAIL ...", exit 1 if any failed.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HEAL="$REPO/linux/plugin-heal.sh"
NS="$REPO/linux/namamp-seed.sh"
TIDY="$REPO/linux/tidy.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
FAIL=0
ok() { echo "$1: ok"; }
bad() { echo "$1: FAIL $2"; FAIL=1; }
[ -x "$HEAL" ] || { bad "script" "$HEAL missing"; exit 1; }
g++ -std=c++14 -I "$REPO/matron/src" "$REPO/linux/plugin_arch_check.cc" -o "$T/plugin_arch_check" 2> "$T/cc.log" || { cat "$T/cc.log"; echo "build: FAIL plugin_arch_check does not build"; exit 1; }
export PLUGIN_ARCH_CHECK_TOOL="$T/plugin_arch_check" NORNS_TIDY="$TIDY" PLUGIN_ARCH_UNAME=x86_64
elf() { printf "\\x7fELF\\x$1\\x01\\x01\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x03\\x00\\x$2\\x00\\x00\\x00"; head -c 64 /dev/zero; }
arm32() { elf 01 28; }
x86() { elf 02 3e; }
PACK="$T/pack/NamAmp"; mkdir -p "$PACK"; { x86; echo ours; } > "$PACK/NamAmp.so"; "$NS" stamp "$PACK" 1 0b3d3c9 2026-11-08 0.1~gitX test
newhome() { H="$T/h$1"; rm -rf "$H"; mkdir -p "$H"; E="$H/.local/share/SuperCollider/Extensions"; }
tree_sum() { (cd "$1" && find . -type f -not -path './disabled/*' -not -name '.plugin-*' -exec sha1sum {} + | sort); }

# 1. wrong-architecture plug-ins of any name, in the three shapes: a folder that is all bad, a mixed folder, dust/code
newhome 1
mkdir -p "$E/arm-only" "$E/mixed" "$H/dust/code/synthy/lib" "$H/dust/code/other"
arm32 > "$E/arm-only/Whatever_scsynth.so"; arm32 > "$E/arm-only/Second.so"
arm32 > "$E/mixed/Bad_scsynth.so"; x86 > "$E/mixed/Good_scsynth.so"; echo "x" > "$E/mixed/readme.txt"
arm32 > "$H/dust/code/synthy/lib/PulsePTR_scsynth.so"
# things that are never touched: a Lua library, a non-ELF .so, an x86-64 plug-in, a sample named like a plug-in outside the two places
arm32 > "$H/dust/code/synthy/lib/cjson.so"; echo "not elf" > "$E/notelf.so"; x86 > "$E/good_scsynth.so"; mkdir -p "$H/dust/audio"; arm32 > "$H/dust/audio/Sample_scsynth.so"
find "$H" -type f \( -name cjson.so -o -name notelf.so -o -name good_scsynth.so -o -name Good_scsynth.so -o -name Sample_scsynth.so -o -name readme.txt \) -exec sha1sum {} + | sort > "$T/keep.before"
OUT="$("$HEAL" heal "$H" 2>&1)"
[ ! -e "$E/arm-only" ] && ok "a folder whose plug-ins are all wrong-architecture is moved whole" || bad "folder" "$OUT"
[ ! -e "$E/mixed/Bad_scsynth.so" ] && [ -f "$E/mixed/Good_scsynth.so" ] && [ -f "$E/mixed/readme.txt" ] && ok "in a mixed folder only the bad file moves" || bad "mixed" "$(ls $E/mixed)"
[ ! -e "$H/dust/code/synthy/lib/PulsePTR_scsynth.so" ] && [ -d "$H/dust/code/synthy" ] && ok "in dust/code the plug-in file moves, the script's folder stays" || bad "dust" ""
find "$H" -type f \( -name cjson.so -o -name notelf.so -o -name good_scsynth.so -o -name Good_scsynth.so -o -name Sample_scsynth.so -o -name readme.txt \) -exec sha1sum {} + | sort > "$T/keep.after"
cmp -s "$T/keep.before" "$T/keep.after" && ok "a Lua library, a non-ELF file, x86-64 plug-ins, a file outside the two places: not one byte touched" || bad "others touched" "$(diff $T/keep.before $T/keep.after)"
MF="$H/disabled/MANIFEST.tsv"
[ "$(grep -c 'wrong-architecture plug-in' "$MF")" = 3 ] && grep -q "arm-only" "$MF" && grep -q "mv " "$MF" && grep -qE '20[0-9]{2}-[0-9]{2}-[0-9]{2}' "$MF" && ok "three manifest lines: what, from where, when, why, the restore command" || bad "manifest" "$(cat $MF 2>&1)"
[ "$(printf '%s\n' "$OUT" | wc -l)" = 1 ] && printf '%s\n' "$OUT" | grep -q '^plugin heal: moved 3 ' && printf '%s\n' "$OUT" | grep -q 'disabled/' && printf '%s\n' "$OUT" | grep -q 'verdandi tidy restore' && ok "one log line: how many, where to, how to restore" || bad "log line" "$OUT"
NOTE="$(cat "$H/.plugin-heal-note" 2>&1)"
printf '%s\n' "$NOTE" | grep -q "Raspberry Pi plug-in" && printf '%s\n' "$NOTE" | grep -q "Moved aside so that SuperCollider can start" && printf '%s\n' "$NOTE" | grep -qi "will not work" && ok "the plain note: what, moved aside so that SuperCollider can start, the script's engine will not work" || bad "note" "$NOTE"
[ "$(printf '%s' "$NOTE" | wc -l)" -le 1 ] && ok "...one line" || bad "note lines" ""

# 2. nothing left: the next start is silent, nothing changes, no second note
rm -f "$H/.plugin-heal-note"; tree_sum "$H" > "$T/t.before"
OUT2="$("$HEAL" heal "$H" 2>&1)"; tree_sum "$H" > "$T/t.after"
[ -z "$OUT2" ] && [ ! -e "$H/.plugin-heal-note" ] && cmp -s "$T/t.before" "$T/t.after" && ok "a second start: nothing to do, no line, no note" || bad "idempotent" "$OUT2"

# 3. restore through tidy
ID="$(awk -F'\t' '/arm-only/ { print $1; exit }' "$MF")"
NORNS_HOME="$H" "$TIDY" restore "$ID" > "$T/restore.out" 2>&1
[ -f "$E/arm-only/Whatever_scsynth.so" ] && ok "verdandi tidy restore puts the folder back" || bad "restore" "$(cat $T/restore.out)"
OUT3="$("$HEAL" heal "$H" 2>&1)"
[ ! -e "$E/arm-only" ] && ok "...and the next start moves it aside again" || bad "again" "$OUT3"
# the note is said once per day for the same set of plug-ins (the line is always in the log)
rm -f "$H/.plugin-heal-note"
NORNS_HOME="$H" "$TIDY" restore "$(awk -F'\t' '/arm-only/ { id = $1 } END { print id }' "$MF")" > /dev/null 2>&1
OUT4="$("$HEAL" heal "$H" 2>&1)"; rm -f "$H/.plugin-heal-note"
NORNS_HOME="$H" "$TIDY" restore "$(awk -F'\t' '/arm-only/ { id = $1 } END { print id }' "$MF")" > /dev/null 2>&1
OUT5="$("$HEAL" heal "$H" 2>&1)"
printf '%s\n' "$OUT5" | grep -q '^plugin heal: moved 1 ' && [ ! -e "$H/.plugin-heal-note" ] && ok "the same plug-ins again the same day: the log line every time, no second window note" || bad "note once" "$OUT5 / $(ls -A $H)"
newhome 12; mkdir -p "$E/p1" "$E/p2"; arm32 > "$E/p1/A_scsynth.so"; arm32 > "$E/p2/B_scsynth.so"
"$HEAL" heal "$H" > /dev/null 2>&1; rm -f "$H/.plugin-heal-note"
mkdir -p "$E/p1" "$E/p2"; arm32 > "$E/p1/A_scsynth.so"; arm32 > "$E/p2/B_scsynth.so"; "$HEAL" heal "$H" > /dev/null 2>&1
[ ! -e "$H/.plugin-heal-note" ] && ok "(the same two again: still no note)" || bad "note same" ""
mkdir -p "$E/p3"; arm32 > "$E/p3/C_scsynth.so"; "$HEAL" heal "$H" > /dev/null 2>&1
[ -f "$H/.plugin-heal-note" ] && ok "a different plug-in: a new note" || bad "note new" ""

# 4. a replacement is shipped (NamAmp): the note says Verdandi's own copy is in use, and the seed puts it in
newhome 4; mkdir -p "$H/dust/code/princeton" "$E/princeton"; arm32 > "$E/princeton/NamAmp.so"
OUT="$(NORNS_NAMAMP_PACK="$PACK" "$HEAL" heal "$H" 2>&1)"
[ ! -e "$E/princeton/NamAmp.so" ] && ok "princeton's NamAmp.so (Raspberry Pi) is moved aside" || bad "namamp moved" "$OUT"
grep -q "Verdandi's own x86-64 copy is in use" "$H/.plugin-heal-note" && ! grep -q "will not work" "$H/.plugin-heal-note" && ok "the note says Verdandi's own copy is in use (it ships one)" || bad "replacement note" "$(cat $H/.plugin-heal-note)"
"$NS" seed "$PACK" "$H" > /dev/null 2>&1
"$NS" info "$H" | grep -q '^state=own' && ok "...and the seed that follows puts the x86-64 copy in its place" || bad "seed after" ""
# no pack in this build, or the setting off: it is a plug-in with no replacement
newhome 41; mkdir -p "$H/dust/code/princeton" "$E/princeton"; arm32 > "$E/princeton/NamAmp.so"
NORNS_NAMAMP=0 NORNS_NAMAMP_PACK="$PACK" "$HEAL" heal "$H" > /dev/null 2>&1
grep -q "will not work" "$H/.plugin-heal-note" && ok "namamp=0: no replacement is promised" || bad "no replacement" "$(cat $H/.plugin-heal-note 2>&1)"

# 5. outside the norns home: not moved (the plug-in check reports it)
newhome 5; mkdir -p "$T/system/ext"; arm32 > "$T/system/ext/Sys_scsynth.so"
cat > "$T/fake_check" <<FAKE
#!/bin/sh
printf '%s\\t%s\\n' "$T/system/ext" "wrong-architecture plug-in (32-bit ARM) on x86_64" > "\$1/.plugin-fix"
FAKE
chmod +x "$T/fake_check"
OUT="$(PLUGIN_ARCH_CHECK_TOOL="$T/fake_check" "$HEAL" heal "$H" 2>&1)"
[ -f "$T/system/ext/Sys_scsynth.so" ] && [ -z "$OUT" ] && [ ! -e "$H/disabled" ] && ok "a plug-in outside the norns home is never moved, nothing said" || bad "outside" "$OUT"

# 6. off switches
newhome 6; mkdir -p "$E/p"; arm32 > "$E/p/X_scsynth.so"
for v in 0 off false no; do OUT="$(NORNS_PLUGIN_HEAL=$v "$HEAL" heal "$H" 2>&1)"; [ -f "$E/p/X_scsynth.so" ] && [ -z "$OUT" ] || bad "off $v" "$OUT"; done
ok "NORNS_PLUGIN_HEAL=0 / off / false / no: nothing is done, nothing is said"
OUT="$(NORNS_PLUGIN_CHECK=0 "$HEAL" heal "$H" 2>&1)"; [ -f "$E/p/X_scsynth.so" ] && [ -z "$OUT" ] && ok "NORNS_PLUGIN_CHECK=0 (the plug-in check is off) turns the heal off too" || bad "check off" "$OUT"
OUT="$(PLUGIN_ARCH_CHECK_TOOL="$T/nonexistent" "$HEAL" heal "$H" 2>&1)"; [ -z "$OUT" ] && [ -f "$E/p/X_scsynth.so" ] && ok "no scanner built: silent" || bad "no tool" "$OUT"
"$HEAL" heal "$T/does-not-exist" > /dev/null 2>&1; [ $? = 0 ] && ok "a home that is not there: exit 0" || bad "exit" ""
# a machine that is not x86_64: its own architecture is not wrong
newhome 7; mkdir -p "$E/p"; arm32 > "$E/p/Y_scsynth.so"
OUT="$(PLUGIN_ARCH_UNAME=armv7l "$HEAL" heal "$H" 2>&1)"; [ -f "$E/p/Y_scsynth.so" ] && [ -z "$OUT" ] && ok "on a 32-bit ARM machine its own plug-ins are not moved" || bad "arm machine" "$OUT"
exit $FAIL
