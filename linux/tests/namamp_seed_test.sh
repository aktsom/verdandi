#!/bin/bash
# linux/tests/namamp_seed_test.sh: linux/namamp-seed.sh (stamp, seed, info) on a fake pack and fake norns homes. the pack is Verdandi's x86-64 NamAmp plug-in; it is copied to
# <extensions>/princeton/NamAmp.so (the place princeton and its engine look) before sclang starts. prints "name: ok" / "name: FAIL ...", exit 1 if any failed.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
S="$REPO/linux/namamp-seed.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
FAIL=0
ok() { echo "$1: ok"; }
bad() { echo "$1: FAIL $2"; FAIL=1; }
[ -x "$S" ] || { bad "script" "$S missing"; exit 1; }
elf() { # class machine-low: the first bytes of an ELF file and some padding
    printf "\\x7fELF\\x$1\\x01\\x01\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x03\\x00\\x$2\\x00\\x00\\x00"
    head -c 64 /dev/zero
}
mkpack() { # dir tag
    rm -rf "$1"; mkdir -p "$1"
    { elf 02 3e; echo "plugin $2"; } > "$1/NamAmp.so"
    touch -d "2026-01-01" "$1/NamAmp.so"
    "$S" stamp "$1" "$3" 0b3d3c97b0859a3a8c92a8628c4dd89a25eb5842 2026-11-08 0.1~gitX "NeuralAmpModelerCore + Eigen"
}
newhome() { H="$T/h$1"; rm -rf "$H"; mkdir -p "$H"; E="$H/.local/share/SuperCollider/Extensions"; D="$E/princeton"; }
mkpack "$T/p1/NamAmp" one 1; P="$T/p1/NamAmp"
[ -f "$P/.verdandi-namamp" ] && grep -q '^pack=NamAmp$' "$P/.verdandi-namamp" && grep -q '^serial=1$' "$P/.verdandi-namamp" && grep -q "^sha256=$(sha256sum "$P/NamAmp.so" | cut -d' ' -f1)$" "$P/.verdandi-namamp" && grep -q '^commit=0b3d3c97' "$P/.verdandi-namamp" && grep -q '^built=2026-11-08$' "$P/.verdandi-namamp" && grep -q '^verdandi=0.1~gitX$' "$P/.verdandi-namamp" && ok "stamp: pack, serial, upstream commit, build date, Verdandi version and the sha256 of the plug-in" || bad "stamp" "$(cat $P/.verdandi-namamp 2>&1)"

# 1. nobody wants it: no princeton script and no extension folder of it
newhome 1
OUT="$("$S" seed "$P" "$H" 2>&1)"
[ ! -e "$E" ] && [ -z "$OUT" ] && ok "no princeton in dust/code: nothing is created, silent" || bad "no script" "$OUT"

# 2. the script is there
newhome 2; mkdir -p "$H/dust/code/princeton/lib"
OUT="$("$S" seed "$P" "$H" 2>&1)"
[ -f "$D/NamAmp.so" ] && [ -f "$D/.verdandi-namamp" ] && cmp -s "$D/NamAmp.so" "$P/NamAmp.so" && cmp -s "$D/.verdandi-namamp" "$P/.verdandi-namamp" && ok "the script is there: seeded to Extensions/princeton/NamAmp.so with the stamp" || bad "seed" "$OUT"
printf '%s\n' "$OUT" | grep -q '^NamAmp: seeded' && [ "$(printf '%s\n' "$OUT" | wc -l)" = 1 ] && ok "...one line says so" || bad "seed line" "$OUT"
[ "$(stat -c %Y "$D/NamAmp.so")" = "$(stat -c %Y "$P/NamAmp.so")" ] && ok "the file keeps the date of the package (older than any start of sclang: the engine's check needs that)" || bad "mtime" "$(stat -c %Y $D/NamAmp.so) vs $(stat -c %Y $P/NamAmp.so)"
[ "$(ls -A "$D" | wc -l)" = 2 ] && [ "$(ls -A "$E" | wc -l)" = 1 ] && ok "no temp folder or file left behind" || bad "leftovers" "$(ls -A $D $E)"
"$S" info "$H" | grep -q '^state=own' && ok "info: own" || bad "info own" "$("$S" info "$H")"
touch -d 2020-01-01 "$D/NamAmp.so"
OUT="$("$S" seed "$P" "$H" 2>&1)"
[ -z "$OUT" ] && [ "$(stat -c %Y "$D/NamAmp.so")" = "$(date -d 2020-01-01 +%s)" ] && ok "the same serial again: silent, nothing rewritten" || bad "again" "$OUT"

# 3. the extension folder of the script exists (the script ran before) but no script folder: seeded too
newhome 3; mkdir -p "$D"
"$S" seed "$P" "$H" > /dev/null 2>&1
[ -f "$D/NamAmp.so" ] && ok "Extensions/princeton exists without dust/code/princeton: seeded" || bad "ext exists" ""

# 4. something that is not ours is there: left alone, one line (an ARM file is the start-up heal's business)
newhome 4; mkdir -p "$H/dust/code/princeton" "$D"; { elf 01 28; echo arm; } > "$D/NamAmp.so"
cp "$D/NamAmp.so" "$T/arm.copy"
OUT="$("$S" seed "$P" "$H" 2>&1)"
cmp -s "$D/NamAmp.so" "$T/arm.copy" && [ ! -e "$D/.verdandi-namamp" ] && ok "a file that is not ours (a Raspberry Pi build) is not overwritten by the seed" || bad "foreign kept" "$OUT"
[ "$(printf '%s\n' "$OUT" | wc -l)" = 1 ] && printf '%s\n' "$OUT" | grep -q 'not from Verdandi' && printf '%s\n' "$OUT" | grep -qi 'moved aside\|heal' && ok "...one line: not ours, and the start-up heal moves a wrong-architecture one aside" || bad "foreign line" "$OUT"
newhome 41; mkdir -p "$H/dust/code/princeton" "$D"; { elf 02 3e; echo "someone elses"; } > "$D/NamAmp.so"
OUT="$("$S" seed "$P" "$H" 2>&1)"
grep -q "someone elses" "$D/NamAmp.so" && [ "$(printf '%s\n' "$OUT" | wc -l)" = 1 ] && ok "an x86-64 file that is not ours: left alone, one line" || bad "x86 foreign" "$OUT"

# 5. update by serial, only of an untouched copy of our own
newhome 5; mkdir -p "$H/dust/code/princeton"
"$S" seed "$P" "$H" > /dev/null 2>&1
mkpack "$T/p2/NamAmp" two 2
OUT="$("$S" seed "$T/p2/NamAmp" "$H" 2>&1)"
grep -q "plugin two" "$D/NamAmp.so" && grep -q '^serial=2$' "$D/.verdandi-namamp" && ok "an older stamp of ours is replaced by the newer pack" || bad "update" "$OUT"
printf '%s\n' "$OUT" | grep -q '^NamAmp: updated' && ok "...one line says updated" || bad "update line" "$OUT"
[ "$(ls -A "$D" | wc -l)" = 2 ] && ok "...nothing left behind" || bad "update leftovers" "$(ls -A $D)"
"$S" seed "$P" "$H" > /dev/null 2>&1
grep -q '^serial=2$' "$D/.verdandi-namamp" && ok "a pack with a lower serial does not replace a newer copy" || bad "downgrade" ""
newhome 51; mkdir -p "$H/dust/code/princeton"
"$S" seed "$P" "$H" > /dev/null 2>&1
echo "tuned by hand" >> "$D/NamAmp.so"
OUT="$("$S" seed "$T/p2/NamAmp" "$H" 2>&1)"
grep -q "tuned by hand" "$D/NamAmp.so" && grep -q '^serial=1$' "$D/.verdandi-namamp" && ok "a modified copy is not replaced" || bad "modified" "$OUT"
[ "$(printf '%s\n' "$OUT" | wc -l)" = 1 ] && printf '%s\n' "$OUT" | grep -q 'changed' && ok "...one line in the log" || bad "modified line" "$OUT"
"$S" info "$H" | grep -q '^state=modified' && ok "info: modified" || bad "info modified" "$("$S" info "$H")"

# 6. off switch, no pack, a home that cannot be written
newhome 6; mkdir -p "$H/dust/code/princeton"
for v in 0 off false no; do OUT="$(NORNS_NAMAMP=$v "$S" seed "$P" "$H" 2>&1)"; [ ! -e "$E" ] && [ -z "$OUT" ] || bad "off $v" "$OUT"; done
ok "NORNS_NAMAMP=0 / off / false / no: nothing is done, nothing is said"
OUT="$("$S" seed "$T/nopack" "$H" 2>&1)"
[ ! -e "$E" ] && [ -z "$OUT" ] && ok "no pack in this build (a source checkout): silent, nothing done" || bad "no pack" "$OUT"
newhome 7; mkdir -p "$H/dust/code/princeton" "$H/.local/share"; chmod 555 "$H/.local/share"
if [ "$(id -u)" != 0 ]; then "$S" seed "$P" "$H" > /dev/null 2>&1; rc=$?; chmod 755 "$H/.local/share"; [ $rc = 0 ] && ok "an unwritable folder never fails the launcher" || bad "unwritable" "rc=$rc"; else chmod 755 "$H/.local/share"; echo "SKIP unwritable folder (running as root)"; fi
newhome 8; mkdir -p "$H/dust/code/princeton"; "$S" info "$H" | grep -q '^state=none' && ok "info: none before the seed" || bad "info none" ""
exit $FAIL
