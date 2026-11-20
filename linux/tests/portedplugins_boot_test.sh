#!/bin/bash
# linux/tests/portedplugins_boot_test.sh: the PortedPlugins pack (the libraries the script twins asks for) in an EMPTY norns home, with the real sclang and the real scsynth:
#   1. the build step's pack (build/linux/portedplugins/PortedPlugins from linux/build.sh; or NORNS_PORTED_TEST_PACK; or one built here, which needs the network) is seeded
#      into the empty home by linux/portedplugins-seed.sh, the way norns.sh does it before sclang starts
#   2. sclang started with HOME = that home finds the class of AnalogChew, AnalogLoss and AnalogDegrade (and every other library of the pack) and compiles without a duplicate-class error
#   3. a synth that uses the three UGENS the way twins' engine does is rendered offline (scsynth, non-real-time): the plug-ins load, the output is not silent and has no NaN
#   4. twins' own installer check (installer.lua `probe`: find over the extension folder for X.sc and X.so or X_scsynth.so) is true for the three libraries
#   5. the control: the same sclang run in a home WITHOUT the pack says the classes are missing and renders nothing (the check can fail, and this is what the owner's log showed)
# prints "name: ok" / "name: FAIL ...", exit 1 on a failure, "SKIP ..." and exit 77 when there is no sclang or no pack. docs/port/phase-m29.md
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SEED="$REPO/linux/portedplugins-seed.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
FAIL=0
ok() { echo "$1: ok"; }
bad() { echo "$1: FAIL $2"; FAIL=1; }
command -v sclang > /dev/null && command -v scsynth > /dev/null || { echo "SKIP portedplugins_boot_test: no sclang and scsynth (supercollider-language, supercollider-server)"; exit 77; }
PACK="${NORNS_PORTED_TEST_PACK:-$REPO/build/linux/portedplugins/PortedPlugins}"
if [ ! -f "$PACK/.verdandi-stamp" ]; then
    # one built here (the checkout build step, into a folder of ours): needs the network
    if "$REPO/linux/portedplugins-build.sh" checkout "$T/buildrepo" > "$T/build.log" 2>&1 && [ -f "$T/buildrepo/build/linux/portedplugins/PortedPlugins/.verdandi-stamp" ]; then
        PACK="$T/buildrepo/build/linux/portedplugins/PortedPlugins"
    else
        echo "SKIP portedplugins_boot_test: no stamped pack at $PACK and it could not be built here ($(tail -n 1 "$T/build.log"))"
        exit 77
    fi
fi
NEEDS="AnalogChew AnalogLoss AnalogDegrade"
ALL="$(ls "$PACK/Classes" | sed -n 's/\.sc$//p' | tr '\n' ' ')"

run_sclang() { # home out
    local rc
    HOME="$1" QT_QPA_PLATFORM=offscreen QTWEBENGINE_CHROMIUM_FLAGS="--no-sandbox" timeout 150 sclang -D "$REPO/linux/tests/twins_ugens.scd" "$2" $ALL > "$2.log" 2>&1
    rc=$?
    return $rc
}
stats() { # wav: rms nan count
    python3 -I - "$1" << 'PY'
import struct, sys, math
d = open(sys.argv[1], 'rb').read()
i = d.find(b'data'); n = int.from_bytes(d[i+4:i+8], 'little')
x = struct.unpack('<%df' % (n // 4), d[i+8:i+8+n])
print("%.5f %d" % (math.sqrt(sum(a * a for a in x) / max(1, len(x))), sum(1 for a in x if a != a)))
PY
}

# 1. the seed into an empty home
H="$T/home"; mkdir -p "$H"
OUT="$("$SEED" seed "$PACK" "$H" 2>&1)"
E="$H/.local/share/SuperCollider/Extensions"
printf '%s\n' "$OUT" | grep -q '^PortedPlugins: seeded' && [ -f "$E/PortedPlugins/.verdandi-stamp" ] && ok "the pack is seeded into an empty home" || bad "seed" "$OUT"

# 4. twins' installer check, as installer.lua writes it
found=1
for n in $NEEDS; do
    [ -n "$(find "$E" -name .git -prune -o \( -name "$n.sc" -o -name "$n.so" -o -name "${n}_scsynth.so" \) -not -path '*ignore*' -type f -print | grep "$n.sc$")" ] \
        && [ -n "$(find "$E" -name .git -prune -o \( -name "$n.sc" -o -name "$n.so" -o -name "${n}_scsynth.so" \) -not -path '*ignore*' -type f -print | grep "\.so$")" ] || found=0
done
[ $found = 1 ] && ok "twins' installer check (class file X.sc AND plug-in X.so or X_scsynth.so, found by its own find) is true for AnalogChew, AnalogLoss and AnalogDegrade" || bad "two halves" "$(find "$E" -type f | head -5)"

# 2. + 3. the real sclang and the real scsynth
run_sclang "$H" "$T/with.wav"
for n in $ALL; do
    grep -q "^CLASS $n true" "$T/with.wav.log" || bad "class $n" "$(grep -a 'CLASS\|ERROR' "$T/with.wav.log" | head -5)"
done
[ "$(grep -c '^CLASS .* true' "$T/with.wav.log")" = "$(echo $ALL | wc -w)" ] && ok "sclang finds the class of all $(echo $ALL | wc -w) libraries of the pack in the empty home" || bad "classes" "$(grep -a 'CLASS' "$T/with.wav.log" | head -30 | tr '\n' ' ')"
grep -qi "duplicate\|ERROR: Class not defined\|redefinition" "$T/with.wav.log" && bad "duplicate" "$(grep -ai 'duplicate\|ERROR' "$T/with.wav.log" | head -3)" || ok "the class library compiles with no duplicate class and no error"
if grep -q '^RENDERED' "$T/with.wav.log" && [ -s "$T/with.wav" ]; then
    read -r RMS NAN <<< "$(stats "$T/with.wav")"
    awk -v r="$RMS" 'BEGIN { exit !(r > 0.001) }' && [ "$NAN" = 0 ] && ok "scsynth loads the three plug-ins: the synth that uses them is not silent (rms $RMS) and has no NaN" || bad "render" "rms $RMS nan $NAN"
else
    bad "render" "$(grep -a 'RENDER\|not installed\|ERROR\|FAILURE' "$T/with.wav.log" | head -5 | tr '\n' ' ')"
fi
grep -aq "not installed" "$T/with.wav.log" && bad "ugen not installed" "$(grep -a 'not installed' "$T/with.wav.log" | head -3)" || ok "no 'UGen not installed' message"

# 5. the control: an empty home with no pack
E0="$T/empty"; mkdir -p "$E0"
run_sclang "$E0" "$T/without.wav"
if grep -q '^CLASS AnalogChew false' "$T/without.wav.log" && grep -q '^NOT RENDERED' "$T/without.wav.log" && [ ! -s "$T/without.wav" ]; then
    ok "control: without the pack sclang does not know AnalogChew and nothing is rendered (what the owner's log showed)"
else
    bad "control" "$(grep -a 'CLASS\|RENDER' "$T/without.wav.log" | head -4 | tr '\n' ' ')"
fi
exit $FAIL
