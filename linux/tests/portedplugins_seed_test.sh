#!/bin/bash
# linux/tests/portedplugins_seed_test.sh: linux/portedplugins-seed.sh (stamp, seed, heal, info) on a fake pack and fake norns homes: the pack is copied before sclang starts, the rules
# that keep it from touching anything that is not Verdandi's, twins' own Raspberry Pi download (class files and ARM plug-ins) moved aside so that the pack can be copied, a working
# foreign copy left alone. prints "name: ok" / "name: FAIL ..." lines, exit 1 if any failed. docs/port/phase-m29.md
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
S="$REPO/linux/portedplugins-seed.sh"
export NORNS_TIDY="$REPO/linux/tidy.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
FAIL=0
ok() { echo "$1: ok"; }
bad() { echo "$1: FAIL $2"; FAIL=1; }
[ -x "$S" ] || { bad "script" "$S missing"; exit 1; }

CLASSES="AnalogChew AnalogLoss AnalogDegrade Fverb LPG"
x86() { printf '\177ELF\002\001\001\000\000\000\000\000\000\000\000\000\003\000\076\000'; }   # an ELF header of an x86-64 shared object
arm() { printf '\177ELF\001\001\001\000\000\000\000\000\000\000\000\000\003\000\050\000'; }  # ... of a 32 bit ARM one (the Raspberry Pi build)
mkpack() { # dir tag: a fake built pack, then stamped
    local d="$1" c
    rm -rf "$d"; mkdir -p "$d/Classes" "$d/licenses"
    for c in $CLASSES; do echo "$c : UGen { *ar { ^1 } } // $2" > "$d/Classes/$c.sc"; x86 > "$d/${c}_scsynth.so"; done
    echo "gpl $2" > "$d/licenses/LICENSE-GPL-3.0.txt"
}
stamp() { "$S" stamp "$1" "$2" def734c6d902a0be70caabb6f9f28b810e40f480 2026-11-20 0.10.18; }
newhome() { H="$T/h$1"; rm -rf "$H"; mkdir -p "$H"; E="$H/.local/share/SuperCollider/Extensions"; }

mkpack "$T/pack1/PortedPlugins" one; stamp "$T/pack1/PortedPlugins" 1 || bad "stamp" "failed"
P="$T/pack1/PortedPlugins"
[ -f "$P/.verdandi-stamp" ] && [ -f "$P/.verdandi-files" ] && ok "stamp writes the stamp and the file list" || bad "stamp files" "$(ls -a "$P")"
grep -q '^pack=PortedPlugins$' "$P/.verdandi-stamp" && grep -q '^serial=1$' "$P/.verdandi-stamp" && grep -q '^commit=def734c6d902a0be70caabb6f9f28b810e40f480$' "$P/.verdandi-stamp" && ok "the stamp names the pack, the serial and the upstream commit" || bad "stamp text" "$(cat "$P/.verdandi-stamp")"
grep -q 'Classes/AnalogChew.sc' "$P/.verdandi-files" && ! grep -q 'verdandi-stamp' "$P/.verdandi-files" && ok "the file list holds the pack's files, not the stamp" || bad "file list" "$(cat "$P/.verdandi-files")"

# 1. no extension folder at all
newhome 1
OUT="$("$S" seed "$P" "$H" 2>&1)"
[ -f "$E/PortedPlugins/Classes/AnalogChew.sc" ] && [ -f "$E/PortedPlugins/AnalogChew_scsynth.so" ] && [ -f "$E/PortedPlugins/.verdandi-stamp" ] && ok "no extension folder: created and seeded (class file and plug-in of every library)" || bad "seed 1" "$OUT"
printf '%s\n' "$OUT" | grep -q '^PortedPlugins: seeded' && [ "$(printf '%s\n' "$OUT" | wc -l)" = 1 ] && ok "...and says so in one line" || bad "seed line" "$OUT"
[ "$(ls -A "$E" | wc -l)" = 1 ] && ok "nothing but the pack in the extension folder (no temp folder left)" || bad "leftovers" "$(ls -A "$E")"
# twins' installer wants BOTH halves for each of its three libraries: the class file X.sc and X.so or X_scsynth.so, found by its find over the extension folder
for c in AnalogChew AnalogLoss AnalogDegrade; do
    [ -n "$(find "$E" -name "$c.sc" -type f)" ] && [ -n "$(find "$E" \( -name "$c.so" -o -name "${c}_scsynth.so" \) -type f)" ] || bad "two halves $c" "$(find "$E" -type f | tr '\n' ' ')"
done
ok "twins' two-halves check (X.sc and X_scsynth.so) finds all three libraries in the seeded folder"

# 2. the same serial again: quiet, untouched
touch -d '2020-01-01' "$E/PortedPlugins/Classes/AnalogChew.sc"
OUT="$("$S" seed "$P" "$H" 2>&1)"
[ -z "$OUT" ] && [ "$(stat -c %Y "$E/PortedPlugins/Classes/AnalogChew.sc")" = "$(date -d 2020-01-01 +%s)" ] && ok "same serial again: silent, nothing rewritten" || bad "again" "$OUT"

# 3. a folder of that name that is not ours
newhome 3; mkdir -p "$E/PortedPlugins/Classes"; echo "// theirs" > "$E/PortedPlugins/Classes/AnalogChew.sc"
OUT="$("$S" seed "$P" "$H" 2>&1)"
grep -q theirs "$E/PortedPlugins/Classes/AnalogChew.sc" && [ ! -e "$E/PortedPlugins/.verdandi-stamp" ] && ok "an unstamped PortedPlugins folder is left alone" || bad "foreign untouched" "$OUT"
[ "$(printf '%s\n' "$OUT" | wc -l)" = 1 ] && printf '%s\n' "$OUT" | grep -q 'not from Verdandi' && ok "...with one line in the log" || bad "foreign line" "$OUT"

# 4. a class of the pack defined elsewhere with a working x86-64 plug-in beside it (a second real copy): nothing seeded, nothing moved, the file is named
newhome 4; mkdir -p "$E/ported-theirs"; echo "AnalogLoss : UGen { }" > "$E/ported-theirs/AnalogLoss.sc"; x86 > "$E/ported-theirs/AnalogLoss_scsynth.so"
OUT="$("$S" seed "$P" "$H" 2>&1)"
[ ! -e "$E/PortedPlugins" ] && [ -f "$E/ported-theirs/AnalogLoss.sc" ] && [ -f "$E/ported-theirs/AnalogLoss_scsynth.so" ] && [ ! -e "$H/disabled" ] && printf '%s\n' "$OUT" | grep -q "ported-theirs/AnalogLoss.sc" && ok "a working second copy: nothing seeded, nothing moved, the file is named" || bad "other class" "$OUT"
# 5. ... in dust/code (it would be a duplicate class too)
newhome 5; mkdir -p "$H/dust/code/some-script/Classes"; echo "Fverb : UGen { }" > "$H/dust/code/some-script/Classes/Fverb.sc"; x86 > "$H/dust/code/some-script/Fverb_scsynth.so"
OUT="$("$S" seed "$P" "$H" 2>&1)"
[ ! -e "$E/PortedPlugins" ] && printf '%s\n' "$OUT" | grep -q "dust/code/some-script/Classes/Fverb.sc" && ok "a working class copy in dust/code: nothing seeded" || bad "dust class" "$OUT"

# 6. twins' own installer downloaded the Raspberry Pi PortedPlugins: class files and ARM plug-ins in <extensions>/supercollider-plugins. they cannot work here and they stand in the way
#    of the copy: moved aside (disabled/, manifest, restorable), then the pack is seeded
newhome 6; mkdir -p "$E/supercollider-plugins"
for c in AnalogChew AnalogLoss AnalogDegrade; do echo "$c : UGen { }" > "$E/supercollider-plugins/$c.sc"; arm > "$E/supercollider-plugins/${c}_scsynth.so"; done
echo "unrelated" > "$E/supercollider-plugins/Greyhole.sc"
OUT="$("$S" seed "$P" "$H" 2>&1)"
[ -f "$E/PortedPlugins/Classes/AnalogChew.sc" ] && ok "the Raspberry Pi class files and plug-ins do not stop the copy: the pack is seeded" || bad "rpi seed" "$OUT"
[ ! -e "$E/supercollider-plugins/AnalogChew.sc" ] && [ ! -e "$E/supercollider-plugins/AnalogLoss_scsynth.so" ] && [ -f "$E/supercollider-plugins/Greyhole.sc" ] && ok "...they were moved aside (the six files of the three libraries), a file of another name is not touched" || bad "rpi moved" "$(find "$E" -type f | tr '\n' ' ')"
[ "$(ls "$H"/disabled/*/ 2> /dev/null | grep -c '^AnalogChew\|^AnalogLoss\|^AnalogDegrade')" -ge 6 ] && [ -f "$H/disabled/MANIFEST.tsv" ] && [ "$(wc -l < "$H/disabled/MANIFEST.tsv")" -ge 6 ] && ok "...into disabled/, with a manifest line for each" || bad "rpi disabled" "$(find "$H/disabled" | head -20)"
printf '%s\n' "$OUT" | grep -q '^PortedPlugins: moved 6 foreign' && printf '%s\n' "$OUT" | grep -q '^PortedPlugins: seeded' && ok "...and the log says what was moved and that the pack was seeded" || bad "rpi lines" "$OUT"
ID="$(sed -n 's/.*(ids: *\([^ )]*\).*/\1/p' <<< "$OUT" | head -n 1)"
[ -n "$ID" ] && NORNS_HOME="$H" "$NORNS_TIDY" restore "$ID" > "$T/restore.out" 2>&1; [ -n "$ID" ] && [ -n "$(find "$E/supercollider-plugins" -name 'Analog*' | head -n 1)" ] && ok "verdandi tidy restore puts one of them back" || bad "restore" "$ID $(cat "$T/restore.out" 2> /dev/null)"

# 7. the launcher's heal (after the seed): files that turn up later, only while the own copy is intact
newhome 7; "$S" seed "$P" "$H" > /dev/null 2>&1
mkdir -p "$E/supercollider-plugins"; echo "AnalogChew : UGen { }" > "$E/supercollider-plugins/AnalogChew.sc"; arm > "$E/supercollider-plugins/AnalogChew_scsynth.so"
OUT="$("$S" heal "$P" "$H" 2>&1)"
[ ! -e "$E/supercollider-plugins/AnalogChew.sc" ] && [ -f "$H/.ported-heal-note" ] && printf '%s\n' "$OUT" | grep -q '^PortedPlugins: moved 2 foreign' && ok "heal: a later Raspberry Pi download is moved aside, a note is left for the window" || bad "heal moved" "$OUT"
newhome 71; "$S" seed "$P" "$H" > /dev/null 2>&1; echo "// edited" >> "$E/PortedPlugins/Classes/AnalogChew.sc"
mkdir -p "$E/supercollider-plugins"; echo "AnalogChew : UGen { }" > "$E/supercollider-plugins/AnalogChew.sc"; arm > "$E/supercollider-plugins/AnalogChew_scsynth.so"
OUT="$("$S" heal "$P" "$H" 2>&1)"
[ -f "$E/supercollider-plugins/AnalogChew.sc" ] && [ ! -e "$H/disabled" ] && [ -z "$OUT" ] && ok "heal: an own copy that was changed: nothing is moved" || bad "heal modified" "$OUT"
newhome 72; mkdir -p "$E/supercollider-plugins"; echo "AnalogChew : UGen { }" > "$E/supercollider-plugins/AnalogChew.sc"; arm > "$E/supercollider-plugins/AnalogChew_scsynth.so"
OUT="$("$S" heal "$P" "$H" 2>&1)"
[ -f "$E/supercollider-plugins/AnalogChew.sc" ] && [ ! -e "$H/disabled" ] && ok "heal: no own copy: nothing is moved (the seed does it when it copies)" || bad "heal no own" "$OUT"
# a working x86-64 copy next to our own: left alone, one line
newhome 73; "$S" seed "$P" "$H" > /dev/null 2>&1; mkdir -p "$E/second"; echo "LPG : UGen { }" > "$E/second/LPG.sc"; x86 > "$E/second/LPG_scsynth.so"
OUT="$("$S" heal "$P" "$H" 2>&1)"
[ -f "$E/second/LPG.sc" ] && [ -f "$E/second/LPG_scsynth.so" ] && [ ! -e "$H/disabled" ] && [ "$(printf '%s\n' "$OUT" | wc -l)" = 2 ] && printf '%s\n' "$OUT" | grep -q "second/LPG" && printf '%s\n' "$OUT" | grep -qi duplicate && ok "heal: a working second copy is left alone and named (class file and plug-in)" || bad "heal x86" "$OUT"

# 8. update: an older stamped copy is replaced by the newer pack
newhome 8
"$S" seed "$P" "$H" > /dev/null 2>&1
mkpack "$T/pack2/PortedPlugins" two; rm "$T/pack2/PortedPlugins/Classes/LPG.sc" "$T/pack2/PortedPlugins/LPG_scsynth.so"; stamp "$T/pack2/PortedPlugins" 2
OUT="$("$S" seed "$T/pack2/PortedPlugins" "$H" 2>&1)"
grep -q '// two' "$E/PortedPlugins/Classes/AnalogChew.sc" && grep -q '^serial=2$' "$E/PortedPlugins/.verdandi-stamp" && ok "an older stamp is replaced by the newer pack" || bad "update" "$OUT"
[ ! -e "$E/PortedPlugins/Classes/LPG.sc" ] && ok "...files the new pack no longer has are gone" || bad "update removed" "$(ls "$E/PortedPlugins/Classes")"
printf '%s\n' "$OUT" | grep -q '^PortedPlugins: updated' && ok "...one line says updated" || bad "update line" "$OUT"
[ "$(ls -A "$E" | wc -l)" = 1 ] && ok "...no old or temp folder is left behind" || bad "update leftovers" "$(ls -A "$E")"
OUT="$("$S" seed "$P" "$H" 2>&1)"
grep -q '^serial=2$' "$E/PortedPlugins/.verdandi-stamp" && ok "a pack with a lower serial does not replace a newer copy" || bad "downgrade" "$OUT"
# a copy the user changed is not replaced
newhome 9; "$S" seed "$P" "$H" > /dev/null 2>&1; echo "// my edit" >> "$E/PortedPlugins/Classes/Fverb.sc"
OUT="$("$S" seed "$T/pack2/PortedPlugins" "$H" 2>&1)"
grep -q 'my edit' "$E/PortedPlugins/Classes/Fverb.sc" && grep -q '^serial=1$' "$E/PortedPlugins/.verdandi-stamp" && printf '%s\n' "$OUT" | grep -q 'has changed since Verdandi put it there' && ok "a changed copy is left alone, one line says why" || bad "changed" "$OUT"
# a file the user added to the folder counts as a change too
newhome 91; "$S" seed "$P" "$H" > /dev/null 2>&1; echo x > "$E/PortedPlugins/mine.txt"
OUT="$("$S" seed "$T/pack2/PortedPlugins" "$H" 2>&1)"
[ -f "$E/PortedPlugins/mine.txt" ] && grep -q '^serial=1$' "$E/PortedPlugins/.verdandi-stamp" && ok "a file added to the folder: nothing replaced" || bad "added" "$OUT"

# 10. off switches, no pack, no home
for v in 0 off false no; do
    newhome 10
    OUT="$(NORNS_PORTED=$v "$S" seed "$P" "$H" 2>&1)"
    [ -z "$OUT" ] && [ ! -e "$E" ] || bad "off $v" "$OUT"
done
ok "NORNS_PORTED=0 / off / false / no: nothing is copied, nothing is said"
newhome 11; mkdir -p "$E/supercollider-plugins"; echo "AnalogChew : UGen { }" > "$E/supercollider-plugins/AnalogChew.sc"; arm > "$E/supercollider-plugins/AnalogChew_scsynth.so"
for v in 0 off; do OUT="$(NORNS_PORTED_HEAL=$v "$S" seed "$P" "$H" 2>&1)"; done
[ -f "$E/supercollider-plugins/AnalogChew.sc" ] && [ ! -e "$H/disabled" ] && ok "NORNS_PORTED_HEAL=0: the leftovers stay where they are (and so the pack is not copied: one line says why)" || bad "heal off" "$OUT"
printf '%s\n' "$OUT" | grep -q "AnalogChew.sc exists" || bad "heal off line" "$OUT"
newhome 12
OUT="$("$S" seed "$T/nopack" "$H" 2>&1)"; [ -z "$OUT" ] && [ ! -e "$E" ] && ok "no pack in this build (a checkout whose build step has not run): silent" || bad "no pack" "$OUT"
"$S" seed "$P" "$T/does-not-exist" > /dev/null 2>&1; [ $? = 0 ] && ok "a home that is not there: exit 0 (never stops the launcher)" || bad "exit" ""

# info
newhome 13; "$S" seed "$P" "$H" > /dev/null 2>&1
"$S" info "$H" | grep -q '^state=own$' && ok "info: own" || bad "info own" "$("$S" info "$H")"
echo "// e" >> "$E/PortedPlugins/Classes/LPG.sc"; "$S" info "$H" | grep -q '^state=modified$' && ok "info: modified" || bad "info modified" ""
newhome 14; "$S" info "$H" | grep -q '^state=none$' && ok "info: none" || bad "info none" ""
exit $FAIL
