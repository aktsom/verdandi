#!/bin/bash
# linux/tests/mi_seed_test.sh: linux/mi-ugens-seed.sh (stamp + seed) on a fake pack and fake norns homes, and the detection the catalog scripts
# use (emplaitress, terrarium, fx_miUGens, oomph) against the seeded folder. prints "name: ok" / "name: FAIL ..." lines, exit 1 if any failed.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
S="$REPO/linux/mi-ugens-seed.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
FAIL=0
ok() { echo "$1: ok"; }
bad() { echo "$1: FAIL $2"; FAIL=1; }
[ -x "$S" ] || { bad "script" "$S missing"; exit 1; }

CLASSES="MiPlaits MiRings MiRipples MiClouds MiVerb MiBeads MiElements MiBraids MiGrids MiMu MiOmi MiTides MiWarps"
mkpack() { # dir tag: a fake built pack (classes, a binary, help), then stamped
    local d="$1"
    rm -rf "$d"; mkdir -p "$d/Classes" "$d/HelpSource"
    for c in $CLASSES; do echo "$c : UGen { *ar { ^1 } } // $2" > "$d/Classes/$c.sc"; printf '\x7fELF\x02\x01\x01' > "$d/$c.so"; done
    echo "help $2" > "$d/HelpSource/MiPlaits.schelp"
}
stamp() { "$S" stamp "$1" "$2" 10f6824f68ad63475f67dfe3fe5016e2d2634f84 2026-11-06 0.1~git20261106 ; }
newhome() { H="$T/h$1"; rm -rf "$H"; mkdir -p "$H"; E="$H/.local/share/SuperCollider/Extensions"; }

mkpack "$T/pack1/mi-UGens" one; stamp "$T/pack1/mi-UGens" 1 || bad "stamp" "failed"
P="$T/pack1/mi-UGens"
[ -f "$P/.verdandi-stamp" ] && [ -f "$P/.verdandi-files" ] && ok "stamp writes the stamp and the file list" || bad "stamp files" "$(ls -a $P)"
grep -q '^serial=1$' "$P/.verdandi-stamp" && grep -q '^commit=10f6824f68ad63475f67dfe3fe5016e2d2634f84$' "$P/.verdandi-stamp" && grep -q '^built=2026-11-06$' "$P/.verdandi-stamp" && grep -q '^verdandi=0.1~git20261106$' "$P/.verdandi-stamp" && ok "the stamp has serial, upstream commit, build date and Verdandi version" || bad "stamp keys" "$(cat $P/.verdandi-stamp)"
grep -q 'Classes/MiPlaits.sc' "$P/.verdandi-files" && ! grep -q 'verdandi-stamp' "$P/.verdandi-files" && ok "the file list holds the pack's files, not the stamp" || bad "file list" "$(cat $P/.verdandi-files)"

# 1. no extension folder at all
newhome 1
OUT="$("$S" seed "$P" "$H" 2>&1)"
[ -f "$E/mi-UGens/Classes/MiPlaits.sc" ] && [ -f "$E/mi-UGens/MiBeads.so" ] && [ -f "$E/mi-UGens/.verdandi-stamp" ] && ok "no extension folder: created and seeded" || bad "seed 1" "$OUT"
printf '%s\n' "$OUT" | grep -q '^mi-UGens: seeded' && ok "...and says so in one line" || bad "seed line" "$OUT"
[ "$(ls -A "$E" | wc -l)" = 1 ] && ok "nothing but the pack in the extension folder (no temp folder left)" || bad "leftovers" "$(ls -A $E)"

# 2. the same serial again: quiet, untouched
touch -d '2020-01-01' "$E/mi-UGens/Classes/MiPlaits.sc"
OUT="$("$S" seed "$P" "$H" 2>&1)"
[ -z "$OUT" ] && [ "$(stat -c %Y "$E/mi-UGens/Classes/MiPlaits.sc")" = "$(date -d 2020-01-01 +%s)" ] && ok "same serial again: silent, nothing rewritten" || bad "again" "$OUT"

# 3. a folder of that name that is not ours
newhome 3; mkdir -p "$E/mi-UGens/Classes"; echo "// theirs" > "$E/mi-UGens/Classes/MiPlaits.sc"
OUT="$("$S" seed "$P" "$H" 2>&1)"
grep -q theirs "$E/mi-UGens/Classes/MiPlaits.sc" && [ ! -e "$E/mi-UGens/.verdandi-stamp" ] && ok "an unstamped mi-UGens folder is left alone" || bad "foreign untouched" "$OUT"
[ "$(printf '%s\n' "$OUT" | wc -l)" = 1 ] && printf '%s\n' "$OUT" | grep -q 'not from Verdandi' && ok "...with one line in the log" || bad "foreign line" "$OUT"

# 4. another Mi*.sc somewhere in the extension folders
newhome 4; mkdir -p "$E/MiPlaits"; echo "// theirs" > "$E/MiPlaits/MiPlaits.sc"
OUT="$("$S" seed "$P" "$H" 2>&1)"
[ ! -e "$E/mi-UGens" ] && printf '%s\n' "$OUT" | grep -q "MiPlaits/MiPlaits.sc" && ok "another Mi*.sc in the extension folder: nothing seeded, the file is named" || bad "other Mi" "$OUT"
# 5. ... or in dust/code (it would be a duplicate class)
newhome 5; mkdir -p "$H/dust/code/mi-copy/Classes"; echo "// theirs" > "$H/dust/code/mi-copy/Classes/MiBeads.sc"
OUT="$("$S" seed "$P" "$H" 2>&1)"
[ ! -e "$E/mi-UGens" ] && printf '%s\n' "$OUT" | grep -q "dust/code/mi-copy/Classes/MiBeads.sc" && ok "a Mi*.sc in dust/code: nothing seeded (it would be a duplicate class)" || bad "dust Mi" "$OUT"

# 6. update: an older stamped copy is replaced by the newer pack
newhome 6
"$S" seed "$P" "$H" >/dev/null 2>&1
echo "stray" > /dev/null
mkpack "$T/pack2/mi-UGens" two; rm "$T/pack2/mi-UGens/Classes/MiWarps.sc"; stamp "$T/pack2/mi-UGens" 2
OUT="$("$S" seed "$T/pack2/mi-UGens" "$H" 2>&1)"
grep -q '// two' "$E/mi-UGens/Classes/MiPlaits.sc" && grep -q '^serial=2$' "$E/mi-UGens/.verdandi-stamp" && ok "an older stamp is replaced by the newer pack" || bad "update" "$OUT"
[ ! -e "$E/mi-UGens/Classes/MiWarps.sc" ] && ok "...files the new pack no longer has are gone" || bad "update removed" "$(ls $E/mi-UGens/Classes)"
printf '%s\n' "$OUT" | grep -q '^mi-UGens: updated' && ok "...one line says updated" || bad "update line" "$OUT"
[ "$(ls -A "$E" | wc -l)" = 1 ] && ok "...no old or temp folder is left behind" || bad "update leftovers" "$(ls -A $E)"
# an older pack never replaces a newer copy
OUT="$("$S" seed "$P" "$H" 2>&1)"
grep -q '^serial=2$' "$E/mi-UGens/.verdandi-stamp" && ok "a pack with a lower serial does not replace a newer copy" || bad "downgrade" "$OUT"

# 7. a user-modified stamped copy is left alone
newhome 7
"$S" seed "$P" "$H" >/dev/null 2>&1
echo "// my edit" >> "$E/mi-UGens/Classes/MiPlaits.sc"
OUT="$("$S" seed "$T/pack2/mi-UGens" "$H" 2>&1)"
grep -q "my edit" "$E/mi-UGens/Classes/MiPlaits.sc" && grep -q '^serial=1$' "$E/mi-UGens/.verdandi-stamp" && ok "a modified copy is not replaced" || bad "modified" "$OUT"
[ "$(printf '%s\n' "$OUT" | wc -l)" = 1 ] && printf '%s\n' "$OUT" | grep -q 'changed' && ok "...one line in the log" || bad "modified line" "$OUT"
# 8. an added file counts as a change
newhome 8
"$S" seed "$P" "$H" >/dev/null 2>&1
echo "// added" > "$E/mi-UGens/Classes/MiMine.sc"
OUT="$("$S" seed "$T/pack2/mi-UGens" "$H" 2>&1)"
[ -f "$E/mi-UGens/Classes/MiMine.sc" ] && grep -q '^serial=1$' "$E/mi-UGens/.verdandi-stamp" && ok "a file added to the copy is kept (the copy is not replaced)" || bad "added" "$OUT"

# 9. off switch, no pack
newhome 9
OUT="$(NORNS_MI_UGENS=0 "$S" seed "$P" "$H" 2>&1)"
[ ! -e "$E" ] && [ -z "$OUT" ] && ok "NORNS_MI_UGENS=0: nothing is done" || bad "off" "$OUT"
for v in off false no; do OUT="$(NORNS_MI_UGENS=$v "$S" seed "$P" "$H" 2>&1)"; [ ! -e "$E" ] || bad "off $v" "seeded"; done
OUT="$("$S" seed "$T/nopack" "$H" 2>&1)"
[ ! -e "$E" ] && [ -z "$OUT" ] && ok "no pack in this build (a source checkout): silent, nothing done" || bad "no pack" "$OUT"

# 10. a home that cannot be written: a line, exit 0 (never stops the launcher)
newhome 10; mkdir -p "$H/.local/share"; chmod 555 "$H/.local/share"
if [ "$(id -u)" != 0 ]; then
    "$S" seed "$P" "$H" >/dev/null 2>&1; rc=$?; chmod 755 "$H/.local/share"
    [ $rc = 0 ] && ok "an unwritable folder never fails the launcher" || bad "unwritable" "rc=$rc"
else chmod 755 "$H/.local/share"; echo "SKIP unwritable folder (running as root)"; fi

# detection the catalog scripts use, against a seeded home
newhome 11
"$S" seed "$P" "$H" >/dev/null 2>&1
U="$H/.local/share/SuperCollider/Extensions"
find "$U" -name MiPlaits.sc | grep -q . && ok "emplaitress: find ... -name MiPlaits.sc finds it" || bad "emplaitress" ""
miss=""; for c in MiPlaits MiRings MiRipples MiClouds MiVerb MiBeads MiElements; do find "$U" -name "Mi*.sc" | grep -q "/$c.sc" || miss="$miss $c"; done
[ -z "$miss" ] && ok "terrarium and fx_miUGens: all seven classes they look for are found by find -name 'Mi*.sc'" || bad "terrarium" "missing:$miss"
ls "$U" | grep -qi mi && ok "oomph: an entry with 'mi' in its name is in the user extension folder" || bad "oomph" "$(ls $U)"
[ -z "$(find "$H" -name '*.sh' -o -name 'wget*')" ] && ok "nothing to download: no installer is needed to satisfy them" || bad "extra" ""
# the pack linux/package.sh built (build/package/cache/mi-ugens-pack), when there is one: x86_64, stamped, intact, and the same detection finds it
RP="${NORNS_MI_TEST_PACK:-$REPO/build/package/cache/mi-ugens-pack/mi-UGens}"
if [ -f "$RP/.verdandi-stamp" ]; then
    newhome 12
    "$S" seed "$RP" "$H" > /dev/null 2>&1
    U="$H/.local/share/SuperCollider/Extensions"
    [ "$("$S" info "$H" | head -n1)" = state=own ] && ok "the built pack: seeded and intact" || bad "built pack state" "$("$S" info "$H")"
    miss=""; for c in MiPlaits MiRings MiRipples MiClouds MiVerb MiBeads MiElements; do [ -f "$U/mi-UGens/Classes/$c.sc" ] && [ -f "$U/mi-UGens/$c.so" ] || miss="$miss $c"; done
    [ -z "$miss" ] && ok "the built pack has the seven classes terrarium and fx_miUGens look for, each with its binary" || bad "built pack classes" "missing:$miss"
    arm=""; for f in "$U"/mi-UGens/*.so; do [ "$(od -An -tx1 -j18 -N1 "$f" | tr -d ' ')" = 3e ] || arm="$arm $(basename "$f")"; done
    [ -z "$arm" ] && ok "every .so of the built pack is x86_64 (machine 0x3e)" || bad "built pack arch" "$arm"
    grep -q '^source=.*pull request' "$RP/.verdandi-stamp" && ok "the stamp names the upstream source" || bad "built pack stamp" "$(cat "$RP/.verdandi-stamp")"
else
    echo "SKIP the built pack (linux/package.sh mi)"
fi
exit $FAIL
