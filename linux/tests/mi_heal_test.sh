#!/bin/bash
# linux/tests/mi_heal_test.sh: linux/mi-ugens-seed.sh heal on fake norns homes: Raspberry Pi mi-UGens files (fake ELF headers) next to Verdandi's own pack are moved
# aside with `verdandi tidy disable` only when the own pack is there and intact. prints "name: ok" / "name: FAIL ..." lines, exit 1 if any failed.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
S="$REPO/linux/mi-ugens-seed.sh"
TIDY="$REPO/linux/tidy.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
FAIL=0
ok() { echo "$1: ok"; }
bad() { echo "$1: FAIL $2"; FAIL=1; }
g++ -std=c++14 -I "$REPO/matron/src" "$REPO/linux/mi_heal.cc" -o "$T/mi_heal" 2> "$T/cc.log" || { cat "$T/cc.log"; echo "build: FAIL mi_heal does not build"; exit 1; }
export MI_HEAL_TOOL="$T/mi_heal" NORNS_TIDY="$TIDY" PLUGIN_ARCH_UNAME=x86_64
elf() { # class machine-low
    printf "\\x7fELF\\x$1\\x01\\x01\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x03\\x00\\x$2\\x00\\x00\\x00"
    head -c 64 /dev/zero
}
arm32() { elf 01 28; }
x86() { elf 02 3e; }
CLASSES="MiPlaits MiRings MiBeads"
mkpack() { # dir: a built pack with real-looking x86-64 binaries, stamped
    rm -rf "$1"; mkdir -p "$1/Classes"
    for c in $CLASSES; do echo "$c : UGen { }" > "$1/Classes/$c.sc"; x86 > "$1/$c.so"; done
    "$S" stamp "$1" 1 10f6824f68ad63475f67dfe3fe5016e2d2634f84 2026-11-06 0.1~gitX
}
PACK="$T/pack/mi-UGens"; mkpack "$PACK"
newhome() { # n: a norns home with the own pack seeded and intact, and foreign Raspberry Pi mi-UGens in three places
    H="$T/h$1"; rm -rf "$H"; mkdir -p "$H"; E="$H/.local/share/SuperCollider/Extensions"
    "$S" seed "$PACK" "$H" > /dev/null 2>&1
}
foreign() {
    mkdir -p "$E/arm-pack/Classes" "$E/mixed" "$H/dust/code/terrarium/lib" "$H/dust/audio"
    for c in $CLASSES; do arm32 > "$E/arm-pack/$c.so"; echo "// theirs" > "$E/arm-pack/Classes/$c.sc"; done
    arm32 > "$E/mixed/MiRings.so"; echo "// theirs" > "$E/mixed/MiRings.sc"; arm32 > "$E/mixed/Other_scsynth.so"; echo "x" > "$E/mixed/readme.txt"
    arm32 > "$H/dust/code/terrarium/lib/MiBeads.so"; echo "// theirs" > "$H/dust/code/terrarium/lib/MiBeads.sc"
    arm32 > "$H/dust/code/terrarium/lib/cjson.so"; echo "print(1)" > "$H/dust/code/terrarium/lib/terrarium.lua"
    echo "sample" > "$H/dust/audio/MiSample.so"
}
tree_sum() { (cd "$1" && find . -type f -not -path './disabled/*' -not -name '.mi-heal-note' -exec sha1sum {} + | sort); }

# 1. own pack intact, foreign Raspberry Pi mi-UGens in the extension folder, in a mixed folder and in dust/code
newhome 1; foreign
find "$H" -type f \( -name 'Other_scsynth.so' -o -name cjson.so -o -name readme.txt -o -name terrarium.lua -o -name MiSample.so \) -exec sha1sum {} + | sort > "$T/keep.before"
sha1sum "$E"/mi-UGens/*.so | sort > "$T/own.before"
OUT="$("$S" heal "$PACK" "$H" 2>&1)"
[ ! -e "$E/arm-pack" ] && ok "a folder of Raspberry Pi mi-UGens (binaries and classes) is moved aside whole" || bad "folder moved" "$OUT"
[ ! -e "$E/mixed/MiRings.so" ] && [ ! -e "$E/mixed/MiRings.sc" ] && ok "in a mixed folder only the Mi binary and the Mi class move" || bad "mixed moved" "$(ls $E/mixed)"
[ ! -e "$H/dust/code/terrarium/lib/MiBeads.so" ] && [ ! -e "$H/dust/code/terrarium/lib/MiBeads.sc" ] && [ -d "$H/dust/code/terrarium" ] && ok "in dust/code the Mi files move, the script's folder stays" || bad "dust moved" "$(ls -R $H/dust/code)"
find "$H" -type f \( -name 'Other_scsynth.so' -o -name cjson.so -o -name readme.txt -o -name terrarium.lua -o -name MiSample.so \) -exec sha1sum {} + | sort > "$T/keep.after"
cmp -s "$T/keep.before" "$T/keep.after" && ok "other plug-ins, Lua libraries, scripts, samples and notes: not one byte touched" || bad "others touched" "$(diff $T/keep.before $T/keep.after)"
sha1sum "$E"/mi-UGens/*.so | sort > "$T/own.after"
cmp -s "$T/own.before" "$T/own.after" && "$S" info "$H" | grep -q '^state=own' && ok "Verdandi's own pack is untouched and still intact" || bad "own changed" ""
[ "$(printf '%s\n' "$OUT" | wc -l)" = 1 ] && printf '%s\n' "$OUT" | grep -q '^mi-UGens: moved 5 ' && printf '%s\n' "$OUT" | grep -q 'disabled/' && printf '%s\n' "$OUT" | grep -q 'verdandi tidy restore' && ok "one log line: how many, where to, how to restore" || bad "log line" "$OUT"
MF="$H/disabled/MANIFEST.tsv"
[ "$(grep -c 'foreign mi-UGens plug-in' "$MF")" = 5 ] && ok "the manifest has a line for each item with the reason (what, from where, when, why, how to restore)" || bad "manifest lines" "$(cat $MF)"
grep -q "arm-pack" "$MF" && grep -q "mv " "$MF" && grep -qE '20[0-9]{2}-[0-9]{2}-[0-9]{2}' "$MF" && ok "...with the folder, the date and the restore command" || bad "manifest fields" "$(cat $MF)"
[ -f "$H/.mi-heal-note" ] && grep -q "A script downloaded Raspberry Pi mi-UGens. Moved aside; Verdandi's own copy is in use." "$H/.mi-heal-note" && ok "the window note is left for the menu (once)" || bad "note file" "$(cat $H/.mi-heal-note 2>&1)"

# 8. idempotent: the next start finds nothing, says nothing, writes no note
rm -f "$H/.mi-heal-note"
tree_sum "$H" > "$T/t.before"
OUT2="$("$S" heal "$PACK" "$H" 2>&1)"
tree_sum "$H" > "$T/t.after"
[ -z "$OUT2" ] && [ ! -e "$H/.mi-heal-note" ] && cmp -s "$T/t.before" "$T/t.after" && ok "a second start: nothing to do, no line, no note, nothing changed" || bad "idempotent" "$OUT2"
[ "$(grep -c 'foreign mi-UGens plug-in' "$MF")" = 5 ] && ok "...and no new manifest lines" || bad "manifest grew" ""

# 7. restore through the tidy tool puts a folder back
ID="$(awk -F'\t' '/arm-pack/ { print $1; exit }' "$MF")"
NORNS_HOME="$H" "$TIDY" restore "$ID" > "$T/restore.out" 2>&1
[ -f "$E/arm-pack/MiPlaits.so" ] && [ -f "$E/arm-pack/Classes/MiPlaits.sc" ] && ok "verdandi tidy restore puts the folder back where it was" || bad "restore" "$(cat $T/restore.out)"
# ...and the next start moves it again (the own pack is still intact)
OUT3="$("$S" heal "$PACK" "$H" 2>&1)"
[ ! -e "$E/arm-pack" ] && ok "a restored folder is moved aside again at the next start" || bad "moved again" "$OUT3"

# 3. own pack missing: nothing is moved (the PLUGINS note and CLEAN UP stay)
newhome 3; foreign; rm -rf "$E/mi-UGens"
tree_sum "$H" > "$T/t.before"
OUT="$("$S" heal "$PACK" "$H" 2>&1)"
tree_sum "$H" > "$T/t.after"
cmp -s "$T/t.before" "$T/t.after" && [ ! -e "$H/disabled" ] && [ ! -e "$H/.mi-heal-note" ] && ok "own pack missing: nothing is moved, no note" || bad "missing moved" "$OUT"
printf '%s\n' "$OUT" | grep -q "own copy is missing or changed" && [ "$(printf '%s\n' "$OUT" | wc -l)" = 1 ] && ok "...one line says why" || bad "missing line" "$OUT"

# 4. own pack modified: nothing is moved
newhome 4; foreign; echo "// edited" >> "$E/mi-UGens/Classes/MiPlaits.sc"
tree_sum "$H" > "$T/t.before"
OUT="$("$S" heal "$PACK" "$H" 2>&1)"
tree_sum "$H" > "$T/t.after"
cmp -s "$T/t.before" "$T/t.after" && [ ! -e "$H/disabled" ] && ok "own pack modified: nothing is moved" || bad "modified moved" "$OUT"
printf '%s\n' "$OUT" | grep -q "own copy is missing or changed" && ok "...with the same line" || bad "modified line" "$OUT"
# an own pack with a foreign file added counts as changed too
newhome 41; foreign; echo "x" > "$E/mi-UGens/extra.txt"
"$S" heal "$PACK" "$H" > /dev/null 2>&1; [ -d "$E/arm-pack" ] && ok "a file added to the own pack: nothing is moved" || bad "added file" ""

# 5. a foreign x86-64 copy: left alone, one line
newhome 5; mkdir -p "$E/other-mi/Classes"; x86 > "$E/other-mi/MiClouds.so"; echo "// theirs" > "$E/other-mi/Classes/MiClouds.sc"
tree_sum "$H" > "$T/t.before"
OUT="$("$S" heal "$PACK" "$H" 2>&1)"
tree_sum "$H" > "$T/t.after"
cmp -s "$T/t.before" "$T/t.after" && [ ! -e "$H/disabled" ] && [ ! -e "$H/.mi-heal-note" ] && ok "a foreign x86-64 copy is left alone, no note" || bad "x86 touched" "$OUT"
[ "$(printf '%s\n' "$OUT" | wc -l)" = 1 ] && printf '%s\n' "$OUT" | grep -q "other-mi" && printf '%s\n' "$OUT" | grep -q "left alone" && printf '%s\n' "$OUT" | grep -qi "duplicate" && ok "...one line names it and says the class check reports duplicates" || bad "x86 line" "$OUT"

# 6. off
for v in 0 off false no; do
    newhome 6; foreign
    tree_sum "$H" > "$T/t.before"
    OUT="$(NORNS_MI_UGENS_HEAL=$v "$S" heal "$PACK" "$H" 2>&1)"
    tree_sum "$H" > "$T/t.after"
    cmp -s "$T/t.before" "$T/t.after" && [ -z "$OUT" ] && [ ! -e "$H/disabled" ] || bad "off $v" "$OUT"
done
ok "NORNS_MI_UGENS_HEAL=0 / off / false / no: nothing is done, nothing is said"
# no tool (a source checkout without the build): silent
newhome 61; foreign
OUT="$(MI_HEAL_TOOL="$T/nonexistent" "$S" heal "$PACK" "$H" 2>&1)"
[ -z "$OUT" ] && [ -d "$E/arm-pack" ] && ok "no scanner built: silent, nothing moved" || bad "no tool" "$OUT"
# no pack in this build: silent
newhome 62; foreign
OUT="$("$S" heal "$T/nopack" "$H" 2>&1)"
[ -z "$OUT" ] && [ -d "$E/arm-pack" ] && ok "no pack in this build: silent, nothing moved" || bad "no pack" "$OUT"
# never fails the launcher
"$S" heal "$PACK" "$T/does-not-exist" > /dev/null 2>&1; [ $? = 0 ] && ok "a home that is not there: exit 0" || bad "exit" ""
exit $FAIL
