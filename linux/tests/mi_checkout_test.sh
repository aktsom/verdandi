#!/bin/bash
# linux/tests/mi_checkout_test.sh (docs/port/phase-m35.md): the mi-UGens pack of a CHECKOUT, built by linux/build.sh (linux/mi-ugens-build.sh checkout), not taken from the package:
#   1. the build step from nothing: the headers of the installed SuperCollider, the pinned commit + pull request, an x86_64 pack with MiPlaits, MiRings, MiBeads, stamped, the file list matches; a second run is "up to date"
#   2. the seed rules with that layout: seeded into an empty home; a foreign (not Verdandi's) mi-UGens folder is left alone; no second copy of a class; norns.sh finds the pack in build/linux/mi-ugens
#   3. an EMPTY home with the real sclang and scsynth: the classes MiPlaits and MiRings (the two the mods emplaitress and fx_resonator use) are found, and a synth that uses them is rendered; the control without the pack
#      shows the owner's symptom (no class, nothing rendered)
# needs the network, git, cmake, ninja, a C++ compiler (SKIP, exit 77, without) and sclang/scsynth for part 3. prints "name: ok" / "name: FAIL ...", exit 1 on a failure.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
B="$REPO/linux/mi-ugens-build.sh"
SEED="$REPO/linux/mi-ugens-seed.sh"
. "$REPO/linux/mi-ugens.pin"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
FAIL=0
ok() { echo "$1: ok"; }
bad() { echo "$1: FAIL $2"; FAIL=1; }
[ -x "$B" ] || { bad "script" "$B is missing (the checkout build of the mi-UGens pack)"; exit 1; }
for t in git cmake ninja c++ strip; do command -v $t > /dev/null || { echo "SKIP mi_checkout_test: $t is not installed"; exit 77; }; done

# 1. the checkout step, from nothing
mkdir -p "$T/repo"
OUT="$("$B" checkout "$T/repo" 2>&1)"; rc=$?
W="$T/repo/build/linux/mi-ugens"
P="$W/mi-ugens-pack/mi-UGens"
if [ ! -f "$P/.verdandi-stamp" ]; then
    case "$OUT" in *"Could not resolve"* | *"unable to access"* | *"Failed to connect"* | *"fatal: unable to"*) echo "SKIP mi_checkout_test: no network ($(printf '%s\n' "$OUT" | tail -n 1))"; exit 77 ;; esac
    bad "checkout step" "rc=$rc $(printf '%s\n' "$OUT" | tail -n 5)"
    exit 1
fi
[ $rc = 0 ] && ok "the checkout step builds the mi-UGens pack from nothing (headers of the installed SuperCollider, pinned sources)" || bad "rc" "$rc"
printf '%s\n' "$OUT" | grep -q "mi-ugens: pack .*: [0-9]* plug-ins, [0-9]* KB" && ok "...and says how many plug-ins and how big" || bad "summary" "$(printf '%s\n' "$OUT" | tail -n 2)"
for n in MiPlaits MiRings MiBeads; do
    [ -f "$P/Classes/$n.sc" ] && [ -f "$P/$n.so" ] || bad "pack has $n" "$(ls "$P" | head -5)"
done
ok "the pack has the class file and the plug-in of MiPlaits, MiRings and MiBeads"
n86=0; n_all=0
for so in "$P"/*.so; do
    n_all=$((n_all + 1))
    [ "$(od -An -tx1 -j18 -N2 "$so" | tr -d ' ')" = 3e00 ] && n86=$((n86 + 1))
done
[ "$n_all" -ge 10 ] && [ "$n86" = "$n_all" ] && ok "every plug-in ($n_all of them) is an x86_64 shared object (not the Raspberry Pi build)" || bad "arch" "$n86 of $n_all"
git -C "$W/mi-ugens" merge-base --is-ancestor "$MI_UGENS_PR_COMMIT" HEAD && git -C "$W/mi-ugens" merge-base --is-ancestor "$MI_UGENS_COMMIT" HEAD && ok "the source built is the pinned commit $MI_UGENS_COMMIT plus pull request $MI_UGENS_PR ($MI_UGENS_PR_COMMIT)" || bad "commit" "$(git -C "$W/mi-ugens" log --oneline -3)"
grep -q "^commit=$MI_UGENS_COMMIT$" "$P/.verdandi-stamp" && grep -q "^serial=$MI_UGENS_SERIAL$" "$P/.verdandi-stamp" && grep -q "^pack=mi-UGens$" "$P/.verdandi-stamp" && ok "the stamp names the pack, the serial and the commit" || bad "stamp" "$(cat "$P/.verdandi-stamp")"
(cd "$P" && sha256sum --quiet -c .verdandi-files) && ok "the file list of the stamp matches every file" || bad "list" ""
[ ! -d "$P/HelpSource" ] && [ -f "$W/mi-ugens-pack/LICENSE-GPL-3.0.md" ] && [ -f "$W/mi-ugens-pack/LICENSE-eurorack-MIT.txt" ] && [ -f "$W/mi-ugens-pack/LICENSE-libsamplerate-BSD-2.txt" ] && ok "no help files, the three licence texts are next to the pack" || bad "licences" "$(ls "$W/mi-ugens-pack")"
OUT2="$("$B" checkout "$T/repo" 2>&1)"
printf '%s\n' "$OUT2" | grep -q "mi-ugens: up to date" && ok "a second run changes nothing (up to date)" || bad "up to date" "$OUT2"
echo "serial=0 commit=$MI_UGENS_COMMIT pr=$MI_UGENS_PR_COMMIT sc=Version-3.13.0" > "$W/.built-for"
OUT3="$("$B" checkout "$T/repo" 2>&1)"
printf '%s\n' "$OUT3" | grep -q "mi-ugens: pack " && ok "a changed pin (serial) builds the pack again" || bad "rebuild" "$(printf '%s\n' "$OUT3" | tail -n 3)"

# 2. the seed rules with the checkout layout
H="$T/home"; mkdir -p "$H"
E="$H/.local/share/SuperCollider/Extensions"
SO="$("$SEED" seed "$P" "$H" 2>&1)"
printf '%s\n' "$SO" | grep -q '^mi-UGens: seeded' && [ -f "$E/mi-UGens/MiPlaits.so" ] && [ -f "$E/mi-UGens/Classes/MiRings.sc" ] && ok "the built pack is seeded into an empty home" || bad "seed" "$SO"
H2="$T/home2"; mkdir -p "$H2/.local/share/SuperCollider/Extensions/mi-UGens"
echo "someone else's" > "$H2/.local/share/SuperCollider/Extensions/mi-UGens/mine.txt"
SO2="$("$SEED" seed "$P" "$H2" 2>&1)"
[ -f "$H2/.local/share/SuperCollider/Extensions/mi-UGens/mine.txt" ] && [ ! -f "$H2/.local/share/SuperCollider/Extensions/mi-UGens/MiPlaits.so" ] && ok "a mi-UGens folder that is not Verdandi's is left alone" || bad "foreign" "$SO2"
# norns.sh: which pack it looks for (the .deb has $REPO/mi-ugens, a checkout has what linux/build.sh built)
SNIP="$(sed -n '/^if \[ -z "\${NORNS_MI_PACK:-}" \]; then/,/^fi$/p' "$REPO/linux/norns.sh")"
[ -n "$SNIP" ] || bad "norns.sh" "no default for NORNS_MI_PACK found"
got="$(REPO="$T/repo" bash -c "unset NORNS_MI_PACK; $SNIP; echo \$NORNS_MI_PACK")"
[ "$got" = "$P" ] && ok "norns.sh looks for the pack in build/linux/mi-ugens of the checkout" || bad "norns.sh default" "$got"
mkdir -p "$T/repo/mi-ugens/mi-UGens"
got="$(REPO="$T/repo" bash -c "unset NORNS_MI_PACK; $SNIP; echo \$NORNS_MI_PACK")"
[ "$got" = "$T/repo/mi-ugens/mi-UGens" ] && ok "...and in mi-ugens/ of the package, when that exists" || bad "norns.sh deb default" "$got"
rm -rf "$T/repo/mi-ugens"

# 3. the real sclang and scsynth in an empty home
command -v sclang > /dev/null && command -v scsynth > /dev/null || { echo "SKIP (part 3) mi_checkout_test: no sclang and scsynth"; exit $FAIL; }
run_sclang() { # home out
    HOME="$1" QT_QPA_PLATFORM=offscreen QTWEBENGINE_CHROMIUM_FLAGS="--no-sandbox" timeout 150 sclang -D "$REPO/linux/tests/mi_ugens.scd" "$2" MiPlaits MiRings MiBeads > "$2.log" 2>&1
}
run_sclang "$H" "$T/with.wav"
grep -q '^CLASS MiPlaits true' "$T/with.wav.log" && grep -q '^CLASS MiRings true' "$T/with.wav.log" && grep -q '^CLASS MiBeads true' "$T/with.wav.log" && ok "sclang in an empty home finds MiPlaits, MiRings and MiBeads" || bad "classes" "$(grep -a 'CLASS' "$T/with.wav.log" | head -4 | tr '\n' ' ')"
grep -qi "duplicate\|not understood\|ERROR: Class not defined" "$T/with.wav.log" && bad "errors" "$(grep -ai 'duplicate\|not understood\|ERROR' "$T/with.wav.log" | head -3)" || ok "the class library compiles with no duplicate class and no 'not understood'"
if grep -q '^RENDERED' "$T/with.wav.log" && [ -s "$T/with.wav" ]; then
    ok "scsynth loads MiPlaits and MiRings: a synth that uses them is rendered"
else
    bad "render" "$(grep -a 'RENDER\|not installed\|ERROR\|FAILURE' "$T/with.wav.log" | head -5 | tr '\n' ' ')"
fi
grep -aq "not installed" "$T/with.wav.log" && bad "ugen not installed" "$(grep -a 'not installed' "$T/with.wav.log" | head -3)" || ok "no 'UGen not installed' message"
E0="$T/empty"; mkdir -p "$E0"
run_sclang "$E0" "$T/without.wav"
if grep -q '^CLASS MiPlaits false' "$T/without.wav.log" && grep -q '^NOT RENDERED' "$T/without.wav.log"; then
    ok "control: without the pack sclang does not know MiPlaits and nothing is rendered (what the owner's log showed)"
else
    bad "control" "$(grep -a 'CLASS\|RENDER' "$T/without.wav.log" | head -4 | tr '\n' ' ')"
fi
exit $FAIL
