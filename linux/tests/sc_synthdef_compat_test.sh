#!/bin/bash
# sc/linux-compat/NornsSynthDefCompat.sc (docs/port/KNOWN-ISSUES.md item 21): SuperCollider 3.14 refuses Clip.ar with a control-rate first input ("Clip first input is not audio rate").
# The extension lets ONLY the SynthDefs on a short list of names (mx_malone of the mod nb_mxsynths) build, by turning that input into K2A.ar while the def is built; no file of the user is
# edited. client side only (a SynthDef is built in sclang, no server needed). run with each sclang found: the system one (3.13.0) and the packaged build tree's (3.14.1), SC314=<sclang> to name it:
#   - without the extension (control): 3.14 refuses mx_malone; 3.13 accepts it
#   - with it: mx_malone builds on both (a single input and an array input), the graph has a K2A.ar and the Clip is audio rate
#   - scoped: a def with another name and the same pattern still fails on 3.14; a listed def with a proper audio-rate Clip.ar gets the same graph with and without the extension (no K2A added);
#     Clip.kr and a def built after a listed one are not changed (nothing leaks); the list is data (NORNS_SYNTHDEF_COMPAT adds names)
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d)"
. "$REPO/linux/tests/sc314_env.sh"
trap 'sc314_unlink_tree; rm -rf "${T:?}"' EXIT
FAIL=0
ok() { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; FAIL=1; }
export QTWEBENGINE_DISABLE_SANDBOX=1 QTWEBENGINE_CHROMIUM_FLAGS=--no-sandbox QT_QPA_PLATFORM=offscreen

cat > "$T/fake.scd" << 'SC'
var try1 = { |name, f| var r = "ok"; try { SynthDef(name, f) } { |e| r = "fail" }; r };
var kids = { |name, f| var n = 0; var k2a = 0; var clipRates = List.new; try { var d = SynthDef(name, f); d.children.do { |u| if(u.class == K2A) { k2a = k2a + 1 }; if(u.class == Clip) { clipRates.add(u.rate) } }; n = d.children.size }; [n, k2a, clipRates.asArray] };
var single = { var hz = \hz.kr(220); Out.ar(0, MoogFF.ar(Saw.ar(110), Clip.ar(hz * 3, 20, 16000), 1)) };
var array = { Out.ar(0, MoogFF.ar(Saw.ar(110), 800, Clip.ar(LFTri.kr([0.5, 0.45]).range(0.3, 1) * \res.kr(1), 0.2, 3.8))) };
var proper = { Out.ar(0, Clip.ar(Saw.ar(110) * 2, -1, 1)) };
var kr = { Out.ar(0, K2A.ar(Clip.kr(\hz.kr(220) * 3, 20, 16000))) };
var r;
("RESULT version=" ++ Main.version).postln;
("RESULT malone_single=" ++ try1.value(\mx_malone, single)).postln;
("RESULT malone_array=" ++ try1.value(\mx_malone, array)).postln;
("RESULT other_name=" ++ try1.value(\other_bad, single)).postln;
("RESULT after_listed_still_scoped=" ++ try1.value(\other_bad2, single)).postln;
r = kids.value(\mx_malone, single);
("RESULT malone_k2a=" ++ r[1]).postln;
("RESULT malone_clip_rates=" ++ r[2]).postln;
("RESULT proper_listed=" ++ kids.value(\mx_malone, proper)).postln;
("RESULT proper_other=" ++ kids.value(\other_ok, proper)).postln;
("RESULT kr_listed=" ++ kids.value(\mx_malone, kr)).postln;
("RESULT kr_other=" ++ kids.value(\other_kr, kr)).postln;
("RESULT extra_name=" ++ try1.value(\my_extra_def, single)).postln;
0.exit;
SC

run_sc() { # sclang, name, extra include folders... -> $T/<name>.out
    local scl="$1" name="$2"; shift 2
    { if [ $# = 0 ]; then echo "includePaths: []"; else echo "includePaths:"; for d in "$@"; do echo "  - \"$d\""; done; fi; echo "excludePaths: []"; echo "postInlineWarnings: false"; } > "$T/$name.yaml"
    timeout 90 "$scl" -D -l "$T/$name.yaml" "$T/fake.scd" > "$T/$name.out" 2>&1
}
res() { sed -n "s/^RESULT $2=//p" "$T/$1.out" | tail -n 1; }

found=0
for scl in "${SC313:-sclang}" "${SC314:-$REPO/build/package/cache/sc-build/lang/sclang}"; do
    command -v "$scl" > /dev/null || [ -x "$scl" ] || { echo "SKIP: no $scl"; continue; }
    case "$scl" in */sc-build/*) sc314_link_tree "$REPO" || { echo "SKIP: the build tree's sclang cannot find its class library here"; continue; } ;; esac
    found=1
    run_sc "$scl" ctl
    V="$(res ctl version)"
    [ -n "$V" ] || { bad "$scl did not run: $(tail -3 "$T/ctl.out")"; continue; }
    echo "== SuperCollider $V"
    run_sc "$scl" fix "$REPO/sc/linux-compat"
    NORNS_SYNTHDEF_COMPAT="my_extra_def" run_sc "$scl" extra "$REPO/sc/linux-compat"
    case "$V" in
        3.14*) [ "$(res ctl malone_single)" = fail ] && ok "control: 3.14 refuses mx_malone (Clip.ar with a control-rate input)" || bad "control: mx_malone should fail on 3.14, got '$(res ctl malone_single)'" ;;
        *) [ "$(res ctl malone_single)" = ok ] && ok "control: $V accepts it (the old, unchecked behaviour)" || bad "control $V: '$(res ctl malone_single)'" ;;
    esac
    [ "$(res fix malone_single)" = ok ] && ok "with the extension: mx_malone builds (single input)" || bad "mx_malone single: '$(res fix malone_single)'"
    [ "$(res fix malone_array)" = ok ] && ok "with the extension: mx_malone builds (array input, as in the mod's second Clip)" || bad "mx_malone array: '$(res fix malone_array)'"
    case "$V" in
        3.14*)
            [ "$(res fix other_name)" = fail ] && ok "scoped: another name with the same pattern still fails" || bad "other_bad should still fail: '$(res fix other_name)'"
            [ "$(res fix after_listed_still_scoped)" = fail ] && ok "nothing leaks: a def built after a listed one is still checked" || bad "leak: '$(res fix after_listed_still_scoped)'"
            [ "$(res extra extra_name)" = ok ] && ok "NORNS_SYNTHDEF_COMPAT adds a name to the list" || bad "extra name: '$(res extra extra_name)'" ;;
    esac
    K="$(res fix malone_k2a)"
    [ "${K:-0}" -ge 1 ] 2> /dev/null && ok "the built graph has $K K2A.ar" || bad "no K2A in the graph ('$K')"
    echo "$(res fix malone_clip_rates)" | grep -q "audio" && ok "the Clip runs at audio rate" || bad "clip rates: '$(res fix malone_clip_rates)'"
    [ "$(res ctl proper_listed)" = "$(res fix proper_listed)" ] && ok "a listed def with a proper audio-rate Clip.ar: the same graph, no K2A added ($(res fix proper_listed))" || bad "proper_listed differs: $(res ctl proper_listed) vs $(res fix proper_listed)"
    [ "$(res ctl proper_other)" = "$(res fix proper_other)" ] && ok "another def with Clip.ar at audio rate: unchanged" || bad "proper_other differs"
    [ "$(res ctl kr_listed)" = "$(res fix kr_listed)" ] && [ "$(res ctl kr_other)" = "$(res fix kr_other)" ] && ok "Clip.kr is unchanged" || bad "Clip.kr changed"
done
[ $found = 1 ] || { echo "SKIP: no sclang"; exit 0; }
[ $FAIL = 0 ] && echo "sc_synthdef_compat_test: all passed"
exit $FAIL
