#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2002
# the pack checks of windows/ci/build-sc3plugins.sh (finish_pack: UNITS.txt from the sources, a class for every UGen, no class defined twice, PACK-ID.txt only for a pack with plug-in files AND class files),
# run here on small fixtures. the owner's report: the mi-UGens pack had plug-in files and no class files at all.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
command -v perl > /dev/null || { echo "no perl: skipped"; exit 0; }
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
OUT="$T/out"; mkdir -p "$OUT/logs" "$OUT/seed"
REPORT="$OUT/report.txt"; : > "$REPORT"
say() { echo "$*" >> "$REPORT"; }
SC_SRC="$T/scsrc"; mkdir -p "$SC_SRC/SCClassLibrary"
echo 'SinOsc : UGen { }' > "$SC_SRC/SCClassLibrary/SinOsc.sc"
sed -n '/^# --- begin pack checks/,/^# --- end pack checks/p' "$REPO/windows/ci/build-sc3plugins.sh" > "$T/fn.sh"
# shellcheck source=/dev/null
. "$T/fn.sh"
fails=0
check() { if [ "$1" = ok ]; then echo "ok   $2"; else echo "FAIL $2"; fails=$((fails + 1)); fi; }
has() { grep -q -- "$1" "$REPORT"; }

# sources: two units with classes, one without, one in SuperCollider's own library, one with the name in a string call
mkdir -p "$T/src/proj"
cat > "$T/src/proj/p.cpp" <<'CPP'
PluginLoad(P) { DefineSimpleUnit(MiGood); DefineDtorUnit(MiOther); DefineSimpleCantAliasUnit(NoClassUnit); DefineSimpleUnit(SinOsc);
  (*ft->fDefineUnit)("StringUnit", sizeof(X), (UnitCtorFunc)&C, 0, 0); }
CPP
git -C "$T/src" init -q 2> /dev/null; git -C "$T/src" -c user.email=t@t -c user.name=t commit -q --allow-empty -m x

# A: the broken pack of the report: plug-in files, NO class files
d="$OUT/seed/A"; mkdir -p "$d/plugins"; touch "$d/plugins/MiGood.scx"
finish_pack A "$T/src/proj" "$T/src"
[ ! -f "$d/PACK-ID.txt" ] && check ok "a pack with plug-in files and no class files gets no PACK-ID (it is not put into the zip)" || check FAIL "no PACK-ID without classes"
has "A: NO PACK-ID" && check ok "...and the report says so" || check FAIL "the report says NO PACK-ID"
has "UGENS WITHOUT A CLASS.*MiGood" && check ok "...and names the UGens without a class" || check FAIL "names MiGood"

# B: classes: one file without a final newline (it must not glue to the next file), a class twice inside a comment (not a duplicate)
d="$OUT/seed/B"; mkdir -p "$d/plugins" "$d/Classes"; touch "$d/plugins/MiGood.scx"
printf 'MiGood : UGen {\n\t*ar { ^this.multiNew(\x27audio\x27) }\n}' > "$d/Classes/a.sc"    # no final newline
printf 'MiOther : UGen { }\n/* MiOther : UGen { } old copy */\n// MiOther : UGen {\nStringUnit : UGen { }\n' > "$d/Classes/b.sc"
: > "$REPORT"
finish_pack B "$T/src/proj" "$T/src"
[ -f "$d/PACK-ID.txt" ] && check ok "plug-in files + class files: PACK-ID.txt written" || check FAIL "PACK-ID written"
grep -qE '^[0-9a-f]{12}-L2$' "$d/PACK-ID.txt" 2> /dev/null && check ok "...as <revision>-L<layout>" || check FAIL "PACK-ID format"
has "B: UGENS WITHOUT A CLASS.*: NoClassUnit $" && check ok "units found in the sources (macro forms and the string form); NoClassUnit is the only one without a class (MiGood, which has no final newline in its file, is found)" || { check FAIL "only NoClassUnit has no class"; sed -n 1,8p "$REPORT"; }
[ "$(cat "$d/UNITS.txt" | tr '\n' ' ')" = "MiGood MiOther NoClassUnit SinOsc StringUnit " ] && check ok "UNITS.txt lists the unit names (macro forms and the string form)" || { check FAIL "UNITS.txt: $(tr '\n' ' ' < "$d/UNITS.txt")"; }
has "B: no class name is defined twice" && check ok "a class inside comments is not defined twice" || check FAIL "comments are not counted"

# C: a class defined twice for real
d="$OUT/seed/C"; mkdir -p "$d/plugins" "$d/Classes"; touch "$d/plugins/x.scx"
printf 'MiGood : UGen { }\n' > "$d/Classes/a.sc"; printf 'MiGood : UGen { }\n' > "$d/Classes/b.sc"
: > "$REPORT"
finish_pack C "$T/src/proj" "$T/src"
has "C: ERROR: class names defined twice.*MiGood" && check ok "a class defined twice is an ERROR in the report" || check FAIL "duplicate named"
[ ! -f "$d/PACK-ID.txt" ] && check ok "...and the pack gets no PACK-ID" || check FAIL "no PACK-ID with a duplicate"
[ "$fails" = 0 ] || { echo "$fails FAILED"; exit 1; }
echo "pack_check_test: ok"
