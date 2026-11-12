#!/usr/bin/env bash
# shellcheck disable=SC2015
# sc/desktop-safe (Windows build, run here with the Linux sclang): (1) the failure: an extension whose initClass raises ("Class 'MiPlaits' not found" inside Meta_Emplaitress:initClass in the owner's report) stops
# Process.startup: no "Class tree inited", no StartUp callback; (2) with VerdandiSafeInit.sc the failure is one line naming the class, the tree goes on and the StartUp callbacks run (so crone and the server would boot);
# (3) VerdandiPackCheck.sc: a pack with UNITS.txt names the UGens that have no class in sclang, in one line, and says so when all have one.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
command -v sclang > /dev/null || { echo "no sclang: skipped"; exit 0; }
export QT_QPA_PLATFORM=offscreen QTWEBENGINE_DISABLE_SANDBOX=1 QTWEBENGINE_CHROMIUM_FLAGS="--no-sandbox --disable-gpu"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/ext" "$T/home/extensions/GoodPack" "$T/home/extensions/BadPack" "$T/home/logs"
cat > "$T/ext/Emplaitress.sc" <<'SC'
Emplaitress {
	*initClass {
		StartUp.add { "STARTUP_CALLBACK_RAN".postln };
		MiNoSuchPlaits.ar(60);
	}
}
SC
printf 'SinOsc\nSaw\n' > "$T/home/extensions/GoodPack/UNITS.txt"
printf 'SinOsc\nMiNoSuchPlaits\nDecimatorNot\n' > "$T/home/extensions/BadPack/UNITS.txt"
echo '"MAIN_RAN".postln; 0.exit;' > "$T/t.scd"
fails=0
check() { if [ "$1" = ok ]; then echo "ok   $2"; else echo "FAIL $2"; fails=$((fails + 1)); fi; }
runs() { # conf-name -> output
    NORNS_HOME="$T/home" timeout 120 sclang -D -l "$T/$1" "$T/t.scd" 2>&1
}
printf 'includePaths:\n    - "%s/ext"\n' "$T" > "$T/plain.yaml"
printf 'includePaths:\n    - "%s/ext"\n    - "%s/sc/desktop-safe"\n' "$T" "$REPO" > "$T/safe.yaml"
A="$(runs plain.yaml)"
echo "$A" | grep -q "Class tree inited" && check FAIL "(1) without the fix the start-up is cut off: 'Class tree inited' must not appear" || check ok "(1) without the fix: the start-up is cut off by the failing initClass (no 'Class tree inited')"
echo "$A" | grep -q "STARTUP_CALLBACK_RAN" && check FAIL "(1) without the fix no StartUp callback runs" || check ok "(1) without the fix: no StartUp callback runs (crone would never start)"
B="$(runs safe.yaml)"
echo "$B" | grep -q "### initClass of Emplaitress failed, start-up goes on" && check ok "(2) the failing class is named in one line" || check FAIL "(2) the failing class is named in one line"
echo "$B" | grep -q "Class tree inited" && check ok "(2) the class tree is initialised" || check FAIL "(2) the class tree is initialised"
echo "$B" | grep -q "STARTUP_CALLBACK_RAN" && check ok "(2) the StartUp callbacks run" || check FAIL "(2) the StartUp callbacks run"
echo "$B" | grep -q "MAIN_RAN" && check ok "(2) the interpreter runs the script" || check FAIL "(2) the interpreter runs the script"
echo "$B" | grep -q "^### plug-in packs: 2 UGens have no class in sclang: MiNoSuchPlaits (BadPack), DecimatorNot (BadPack)" && check ok "(3) one line names the UGens without a class (SinOsc and Saw are known)" || { check FAIL "(3) the pack line"; echo "$B" | grep "plug-in packs"; }
[ "$(echo "$B" | grep -c '^### plug-in packs')" = 1 ] && check ok "(3) it is one line" || check FAIL "(3) it is one line"
[ "$(wc -l < "$T/home/logs/pack-check.txt")" = 2 ] && check ok "(3) the full list is in logs/pack-check.txt" || check FAIL "(3) the full list"
rm -rf "$T/home/extensions/BadPack"
C="$(runs safe.yaml)"
echo "$C" | grep -q "plug-in packs: every UGen of the packs has its class" && check ok "(3) all UGens known: the line says so" || check FAIL "(3) all known"
[ "$fails" = 0 ] || { echo "$fails FAILED"; exit 1; }
echo "safe_init_test: ok"
