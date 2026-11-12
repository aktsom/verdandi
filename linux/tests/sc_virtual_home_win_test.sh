#!/usr/bin/env bash
# the virtual /home/we of the Windows build (sc/desktop-safe/NornsVirtualHome.sc), run here with the Linux sclang. the owner's report: dronecaster compiled its drones from
# /home/we/dust/code/dronecaster/engine/drones and got "Dictionary[]" ("dronecaster does not know this drone: Apparatus"). a script-like engine scans that path with PathName, pathMatch and File;
# it must find the drones in the real folder named by NORNS_HOME (not HOME: on Windows HOME is not a POSIX path), and the Windows copy must not drift from the Linux file.
# shellcheck disable=SC2015
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
fails=0
check() { if [ "$1" = ok ]; then echo "ok   $2"; else echo "FAIL $2"; fails=$((fails + 1)); fi; }
# no drift: from the method isNameChar on, the two files are the same text
if diff <(sed -n '/^\t\*isNameChar/,$p' "$REPO/sc/linux/NornsVirtualHome.sc") <(sed -n '/^\t\*isNameChar/,$p' "$REPO/sc/desktop-safe/NornsVirtualHome.sc") > /dev/null; then check ok "the Windows copy is the same code as the Linux file (only the home differs)"; else check FAIL "the Windows copy has drifted from sc/linux/NornsVirtualHome.sc"; fi
command -v sclang > /dev/null || { echo "no sclang: the sclang part is skipped"; [ "$fails" = 0 ] && exit 0 || exit 1; }
export QT_QPA_PLATFORM=offscreen QTWEBENGINE_DISABLE_SANDBOX=1 QTWEBENGINE_CHROMIUM_FLAGS="--no-sandbox --disable-gpu"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
H="$T/Verdandi home" # a folder with a blank, like C:/Users/x/Verdandi on a PC with an accent or a blank in the name
mkdir -p "$H/dust/code/dronecaster/engine/drones" "$T/ext"
printf '"Apparatus drone".postln;\n' > "$H/dust/code/dronecaster/engine/drones/Apparatus.scd"
printf '"Boreal drone".postln;\n' > "$H/dust/code/dronecaster/engine/drones/Boreal.scd"
# a script-like engine: it builds its dictionary of drones from the path in its source, as dronecaster does
cat > "$T/ext/FakeDronecaster.sc" <<'SC'
FakeDronecaster {
	*initClass {
		StartUp.add {
			var drones = Dictionary.new;
			PathName("/home/we/dust/code/dronecaster/engine/drones").entries.do { |e| drones.put(e.fileNameWithoutExtension.asSymbol, e.fullPath) };
			("FAKE_DRONES_ENTRIES " ++ drones.keys.asArray.sort).postln;
			("FAKE_DRONES_GLOB " ++ "/home/we/dust/code/dronecaster/engine/drones/*.scd".pathMatch.size).postln;
			("FAKE_DRONES_FILE " ++ File.exists("/home/we/dust/code/dronecaster/engine/drones/Apparatus.scd")).postln;
			("FAKE_DRONES_READ " ++ File.readAllString("/home/we/dust/code/dronecaster/engine/drones/Boreal.scd").size).postln;
			("FAKE_DRONES_STD " ++ "/home/we/dust/code".standardizePath.beginsWith("/home/we").not).postln;
			("FAKE_DRONES_WEIRD " ++ ("/home/weird/x".standardizePath == "/home/weird/x")).postln;
		};
	}
}
SC
printf 'includePaths:\n    - "%s/ext"\n    - "%s/sc/desktop-safe"\n' "$T" "$REPO" > "$T/conf.yaml"
echo '0.exit;' > "$T/t.scd"
OUT="$(NORNS_HOME="$H" HOME="$T/not-used" timeout 120 sclang -D -l "$T/conf.yaml" "$T/t.scd" 2>&1)"
echo "$OUT" | grep -q "FAKE_DRONES_ENTRIES \[ Apparatus, Boreal \]" && check ok "PathName(\"/home/we/.../drones\").entries finds the drones in the real folder (NORNS_HOME, with a blank in its name)" || { check FAIL "PathName entries"; echo "$OUT" | grep FAKE_DRONES; }
echo "$OUT" | grep -q "FAKE_DRONES_GLOB 2" && check ok "pathMatch (glob) finds both files" || check FAIL "pathMatch"
echo "$OUT" | grep -q "FAKE_DRONES_FILE true" && check ok "File.exists" || check FAIL "File.exists"
echo "$OUT" | grep -q "FAKE_DRONES_READ 2[0-9]" && check ok "File.readAllString reads a file below /home/we" || check FAIL "File.readAllString"
echo "$OUT" | grep -q "FAKE_DRONES_STD true" && check ok "standardizePath leaves no /home/we" || check FAIL "standardizePath"
echo "$OUT" | grep -q "FAKE_DRONES_WEIRD true" && check ok "/home/weird is left alone (whole component only)" || check FAIL "/home/weird"
# without the file the scan is empty: the owner's bug
printf 'includePaths:\n    - "%s/ext"\n' "$T" > "$T/conf0.yaml"
OUT0="$(NORNS_HOME="$H" HOME="$T/not-used" timeout 120 sclang -D -l "$T/conf0.yaml" "$T/t.scd" 2>&1)"
echo "$OUT0" | grep -q "FAKE_DRONES_ENTRIES \[  \]" && check ok "without the file the scan finds nothing (the report: Dictionary[], 'does not know this drone')" || { check FAIL "the bug is not reproduced without the file"; echo "$OUT0" | grep FAKE_DRONES; }
# a Windows home with backslashes and a blank (what NORNS_HOME could look like): slashes in, the drive kept
echo '("VH_REAL " ++ NornsVirtualHome.real).postln; ("VH_MAPPED " ++ NornsVirtualHome.mapped("/home/we/dust/code")).postln; 0.exit;' > "$T/t2.scd"
OUT2="$(NORNS_HOME='C:\Users\a b\Verdandi' timeout 120 sclang -D -l "$T/conf.yaml" "$T/t2.scd" 2>&1)"
echo "$OUT2" | grep -q "VH_REAL C:/Users/a b/Verdandi" && echo "$OUT2" | grep -q "VH_MAPPED C:/Users/a b/Verdandi/dust/code" && check ok "a Windows NORNS_HOME (drive, backslashes, blank) becomes C:/Users/a b/Verdandi and /home/we maps to it" || { check FAIL "Windows home form"; echo "$OUT2" | grep VH_; }
[ "$fails" = 0 ] || { echo "$fails FAILED"; exit 1; }
echo "sc_virtual_home_win_test: ok"
