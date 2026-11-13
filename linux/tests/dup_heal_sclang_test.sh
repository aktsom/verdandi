#!/usr/bin/env bash
# shellcheck disable=SC2015
# the owner's 0.8.2 failure with the real sclang: the pack in extensions and the same classes in the per-user folder (a script's copy). sclang stops: "duplicate Class found", "Library has not been compiled
# successfully". then the launcher's check (dup_heal.h, run through the dup_heal_test --tool) moves the copy aside and the same sclang starts.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
command -v sclang > /dev/null || { echo "no sclang: skipped"; exit 0; }
export QT_QPA_PLATFORM=offscreen QTWEBENGINE_DISABLE_SANDBOX=1 QTWEBENGINE_CHROMIUM_FLAGS="--no-sandbox --disable-gpu"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
cc -std=gnu11 -Wall -I "$REPO/windows/launcher" "$REPO/linux/tests/dup_heal_test.c" -o "$T/dht" || exit 1
H="$T/home"; EXT="$H/extensions"; USR="$H/.local/share/SuperCollider/Extensions"; DUST="$H/dust"; DIS="$H/disabled"
mkdir -p "$EXT/mi-UGens/Classes" "$USR/mi-UGens/Classes" "$DUST/code" "$DIS"
echo "abc-L2" > "$EXT/mi-UGens/PACK-ID.txt"
for c in MiBraids MiClouds MiPlaits; do printf '%s : UGen {\n\t*ar { ^this.multiNew(\x27audio\x27) }\n}\n' "$c" > "$EXT/mi-UGens/Classes/$c.sc"; cp "$EXT/mi-UGens/Classes/$c.sc" "$USR/mi-UGens/Classes/$c.sc"; done
printf 'includePaths:\n    - "%s"\n    - "%s"\n    - "%s"\n' "$USR" "$EXT" "$DUST" > "$T/conf.yaml"
echo '"SCLANG_STARTED".postln; 0.exit;' > "$T/t.scd"
fails=0
check() { if [ "$1" = ok ]; then echo "ok   $2"; else echo "FAIL $2"; fails=$((fails + 1)); fi; }
runsc() { (timeout 40 sclang -D -l "$T/conf.yaml" "$T/t.scd" > "$1" 2>&1; true); }
runsc "$T/before.txt"
grep -q "duplicate Class found: 'MiBraids'" "$T/before.txt" && grep -q "Library has not been compiled successfully" "$T/before.txt" && check ok "before: sclang stops with 'duplicate Class found' and 'Library has not been compiled successfully' (the report)" || { check FAIL "the failure is not reproduced"; grep -E "duplicate|Library" "$T/before.txt"; }
grep -q SCLANG_STARTED "$T/before.txt" && check FAIL "before: sclang must not have started" || check ok "before: sclang did not start"
"$T/dht" --tool "$EXT" "$USR" "$DUST" "$DIS" > "$T/heal.txt"
grep -q "moved=1 unresolved=0" "$T/heal.txt" && check ok "the check moved one copy and left nothing unresolved" || { check FAIL "heal result"; cat "$T/heal.txt"; }
[ -d "$DIS/mi-UGens-duplicate" ] && [ ! -d "$USR/mi-UGens" ] && [ -f "$EXT/mi-UGens/Classes/MiPlaits.sc" ] && check ok "the copy is in disabled, the shipped pack is kept" || check FAIL "disabled / kept"
runsc "$T/after.txt"
grep -q SCLANG_STARTED "$T/after.txt" && ! grep -q "duplicate Class" "$T/after.txt" && check ok "after: the same sclang starts" || { check FAIL "sclang after the heal"; grep -E "duplicate|Library" "$T/after.txt"; }
[ "$fails" = 0 ] || { echo "$fails FAILED"; exit 1; }
echo "dup_heal_sclang_test: ok"
