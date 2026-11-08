#!/bin/bash
# linux/tests/namamp_render_test.sh: the NamAmp plug-in Verdandi ships, rendered offline with the bundled SuperCollider's scsynth (non-real-time): a 110 Hz sine at 0.1 through a NAM model.
# the numbers are those of the NeuralAmpModelerCore example models in linux/tests/fixtures/nam (tiny, deterministic); active=0 and a missing file are silent; the gain argument of namLoad
# and the setting namamp_gain (NORNS_NAMAMP_GAIN, dB) scale the output. needs the built pack (linux/package.sh namamp) and the SuperCollider build of the package (no Qt): prints "SKIP ..."
# and exits 77 without them. prints "name: ok" / "name: FAIL ...".
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PACK="${NORNS_NAMAMP_PACK:-$REPO/build/package/cache/namamp-pack/NamAmp}"
SCB="${NORNS_SC_BUILD:-$REPO/build/package/cache/sc-build}"
SCSRC="$REPO/build/package/cache/supercollider"
[ -f "$PACK/NamAmp.so" ] || { echo "SKIP namamp_render_test: no pack at $PACK (linux/package.sh namamp)"; exit 77; }
[ -x "$SCB/lang/sclang" ] && [ -x "$SCB/server/scsynth/scsynth" ] && [ -d "$SCSRC/SCClassLibrary" ] || { echo "SKIP namamp_render_test: no SuperCollider build in $SCB (linux/package.sh sc)"; exit 77; }
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
FAIL=0
ok() { echo "$1: ok"; }
bad() { echo "$1: FAIL $2"; FAIL=1; }
mkdir -p "$T/plug" "$T/classes"
cp "$PACK/NamAmp.so" "$T/plug/NamAmp.so"
cp "$REPO/linux/tests/scripts/NamAmp.sc" "$T/classes/"
cat > "$T/conf.yaml" <<YAML
includePaths:
    - $SCSRC/SCClassLibrary
    - $T/classes
excludePaths: []
postInlineWarnings: false
YAML
render() { # model out act gain [env]
    local model="$1" out="$2" act="$3" gain="$4"
    ( cd "$T" && timeout 150 "$SCB/lang/sclang" -l "$T/conf.yaml" "$REPO/linux/tests/namamp_render.scd" "$model" "$out" "$act" 110 "$T/plug" "$SCB/server/plugins" "$SCB/server/scsynth/scsynth" "$gain" 2>&1 )
}
stats() { # wav: "rms peak nan rms_before"  of the part with the synth (0.6..3.4 s), the part before it
    python3 -I - "$1" <<'PY'
import struct, sys, math
d = open(sys.argv[1], 'rb').read()
i = d.find(b'data'); n = int.from_bytes(d[i+4:i+8], 'little')
x = struct.unpack('<%df' % (n // 4), d[i+8:i+8+n])
sr = 48000
seg = x[int(0.6*sr):int(3.4*sr)]
pre = x[:int(0.45*sr)]
rms = lambda v: math.sqrt(sum(a*a for a in v) / max(1, len(v)))
print("%.5f %.5f %d %.6f" % (rms(seg), max(abs(a) for a in x), sum(1 for a in x if a != a), rms(pre)))
PY
}
near() { python3 -I -c "import sys; a=float(sys.argv[1]); b=float(sys.argv[2]); sys.exit(0 if abs(a-b) <= abs(b)*float(sys.argv[3]) + 1e-9 else 1)" "$1" "$2" "$3"; }
M="$REPO/linux/tests/fixtures/nam"
# golden values from the pack of this commit (the models are tiny and deterministic: 0.5 percent covers a float rounding difference of another compiler)
OUT="$(render "$M/wavenet.nam" "$T/w.wav" 1 1.0)"
printf '%s\n' "$OUT" | grep -q "^NamAmp: loaded $M/wavenet.nam (gain 1.00)" && ok "the plug-in loads (the line of the original: NamAmp: loaded <file> (gain 1.00))" || bad "load line" "$OUT"
read -r RMS PEAK NAN PRE <<< "$(stats "$T/w.wav")"
near "$RMS" 0.00811 0.005 && near "$PEAK" 0.01204 0.005 && [ "$NAN" = 0 ] && ok "wavenet.nam: rms $RMS, peak $PEAK, no NaN" || bad "wavenet" "rms $RMS peak $PEAK nan $NAN"
[ "$PRE" = 0.000000 ] && ok "...exactly silent before the synth starts" || bad "pre" "$PRE"
OUT="$(render "$M/lstm.nam" "$T/l.wav" 1 1.0)"
read -r RMS PEAK NAN PRE <<< "$(stats "$T/l.wav")"
near "$RMS" 0.00542 0.005 && near "$PEAK" 0.00853 0.005 && [ "$NAN" = 0 ] && ok "lstm.nam: rms $RMS, peak $PEAK, no NaN" || bad "lstm" "rms $RMS peak $PEAK nan $NAN"
read -r W_RMS _ _ _ <<< "$(stats "$T/w.wav")"
# active = 0
render "$M/wavenet.nam" "$T/off.wav" 0 1.0 > /dev/null
read -r RMS PEAK NAN PRE <<< "$(stats "$T/off.wav")"
[ "$RMS" = 0.00000 ] && [ "$PEAK" = 0.00000 ] && ok "active = 0: exactly silent" || bad "inactive" "rms $RMS peak $PEAK"
# a missing file: said, silent, no crash
OUT="$(render "$T/doesnotexist.nam" "$T/bad.wav" 1 1.0)"
read -r RMS PEAK NAN PRE <<< "$(stats "$T/bad.wav")"
printf '%s\n' "$OUT" | grep -q "^NamAmp: failed to load $T/doesnotexist.nam" && [ "$PEAK" = 0.00000 ] && ok "a missing model: one line says so, the output is silent, nothing crashes" || bad "missing" "$OUT / $PEAK"
# not a model at all
echo "this is not a model" > "$T/junk.nam"
OUT="$(render "$T/junk.nam" "$T/junk.wav" 1 1.0)"
read -r RMS PEAK NAN PRE <<< "$(stats "$T/junk.wav")"
printf '%s\n' "$OUT" | grep -q "^NamAmp: failed to load $T/junk.nam" && [ "$PEAK" = 0.00000 ] && ok "a file that is not a NAM model: said, silent" || bad "junk" "$OUT"
# the gain argument of namLoad: a linear factor
render "$M/wavenet.nam" "$T/g.wav" 1 0.5 > /dev/null
read -r G_RMS _ _ _ <<< "$(stats "$T/g.wav")"
near "$G_RMS" "$(python3 -I -c "print($W_RMS*0.5)")" 0.002 && ok "namLoad <path> 0.5: the output is half (rms $G_RMS)" || bad "gain arg" "$G_RMS vs $W_RMS * 0.5"
# the setting namamp_gain (dB) is added: +6 dB is 1.9953 times; -6 dB 0.5012; the value is limited to the range -48..24; text that is no number is 0
render_env() { NORNS_NAMAMP_GAIN="$1" render "$M/wavenet.nam" "$T/e.wav" 1 1.0 > /dev/null; stats "$T/e.wav" | cut -d' ' -f1; }
near "$(render_env 6)" "$(python3 -I -c "print($W_RMS*10**(6/20))")" 0.003 && ok "NORNS_NAMAMP_GAIN=6 (namamp_gain=6): +6 dB" || bad "gain +6" ""
near "$(render_env -6)" "$(python3 -I -c "print($W_RMS*10**(-6/20))")" 0.003 && ok "namamp_gain=-6: -6 dB" || bad "gain -6" ""
near "$(render_env banana)" "$W_RMS" 0.003 && ok "namamp_gain=banana: 0 dB (a value that is no number is ignored)" || bad "gain text" ""
near "$(render_env 100)" "$(python3 -I -c "print($W_RMS*10**(24/20))")" 0.003 && ok "namamp_gain=100 is limited to +24 dB" || bad "gain limit" ""
# the plug-in is an x86-64 shared object for SuperCollider
[ "$(od -An -tx1 -j18 -N2 "$PACK/NamAmp.so" | tr -d ' ')" = 3e00 ] && ok "NamAmp.so is x86-64" || bad "arch" ""
exit $FAIL
