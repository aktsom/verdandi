#!/usr/bin/env bash
# windows/ci/smoke-sc.sh: the SuperCollider half of the M0b boot smoke test. proves, without an audio device:
#   1. sclang starts and compiles the class library together with norns's own sc/core and sc/engines;
#   2. scsynth runs in non-realtime mode (-N) and renders a test SynthDef to a wav file that is not silent;
#   3. the same again from a directory with spaces (core), and from a directory with a non-ASCII letter (information: sclang on Windows takes its command line in the ANSI code page, so a UTF-8 path
#      fails with "bad conversion"; the second variant works from inside the folder with relative names, which is what the launcher has to do).
# NO realtime server is ever booted: a runner has no audio device. norns's own boot at start-up is switched off by sc-smoke/SmokeNoBoot.sc, scsynth only runs with -N, and every sclang and scsynth call has a hard
# timeout (SMOKE_TIMEOUT, default 300 s) so that a hang fails fast. the realtime path (an audio device, the in-process pump) is not part of M0b.
# bash only, so that it can be tried on Linux against any SuperCollider build:
#   SC_TREE      folder with sclang(.exe) and scsynth(.exe); the class library is $SC_TREE/SCClassLibrary
#   SCLANG, SCSYNTH, SC_CLASSLIB   override the three (for a build tree that is not an install tree)
#   SC_PLUGINS   optional, passed to scsynth as -U
#   NORNS_SC     norns's sc folder (default: <repository>/sc)
#   SMOKE_TIMEOUT  seconds per sclang/scsynth call (default 300)
#   M0_OUT       logs and status (lib.sh)
# the functions below are called through m0_run (shellcheck cannot see that)
# shellcheck disable=SC2329
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=windows/ci/lib.sh
. "$HERE/lib.sh"
REPO="$(cd "$HERE/../.." && pwd)"
NORNS_SC="${NORNS_SC:-$REPO/sc}"
EXE=""
case "$(uname -s)" in MINGW* | MSYS* | CYGWIN*) EXE=".exe" ;; esac
SC_TREE="${SC_TREE:-}"
SCLANG="${SCLANG:-$SC_TREE/sclang$EXE}"
SCSYNTH="${SCSYNTH:-$SC_TREE/scsynth$EXE}"
SC_CLASSLIB="${SC_CLASSLIB:-$SC_TREE/SCClassLibrary}"
T="${SMOKE_TMP:-$(mktemp -d)}"

SMOKE_TIMEOUT="${SMOKE_TIMEOUT:-300}"
# a hard limit for every external program: TERM after the limit, KILL 10 s later. exit 124 = it hung
limited() {
    if command -v timeout > /dev/null 2>&1; then timeout -k 10 "$SMOKE_TIMEOUT" "$@"; else "$@"; fi
}
# a hung or crashed program must not stay behind on the runner
cleanup_procs() {
    if command -v taskkill > /dev/null 2>&1; then
        taskkill //F //IM scsynth.exe //IM sclang.exe > /dev/null 2>&1 || true
    fi
}
trap cleanup_procs EXIT

# a path in the form the tool wants: on Windows C:/..., elsewhere unchanged
native() {
    if command -v cygpath > /dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi
}

write_cfg() { # dir: the class library, norns's classes and the no-boot class, nothing from the user's own folders
    {
        echo "includePaths:"
        echo "  - $(native "$SC_CLASSLIB")"
        echo "  - $(native "$NORNS_SC/core")"
        echo "  - $(native "$NORNS_SC/engines")"
        if [ -d "$NORNS_SC/linux-compat" ]; then echo "  - $(native "$NORNS_SC/linux-compat")"; fi
        echo "  - $(native "$HERE/sc-smoke")"
        echo "excludeDefaultPaths: true"
    } > "$1/sclang.cfg"
}

check_tools() {
    local ok=0 f
    for f in "$SCLANG" "$SCSYNTH" "$SC_CLASSLIB" "$NORNS_SC/core" "$HERE/sc-smoke/SmokeNoBoot.sc"; do
        if [ -e "$f" ]; then echo "found: $f"; else echo "MISSING: $f"; ok=1; fi
    done
    return "$ok"
}

# sclang: compile, define a SynthDef, write a score for the NRT render, exit. mode abs: absolute paths on the command line; mode rel: cd into the folder and use relative names only
sclang_step() { # dir mode
    local d="$1" mode="$2" nd score cfg job rc
    mkdir -p "$d"
    write_cfg "$d"
    nd="$(native "$d")"
    if [ "$mode" = rel ]; then score="score.osc"; cfg="sclang.cfg"; job="job.scd"; else score="$nd/score.osc"; cfg="$(native "$d/sclang.cfg")"; job="$(native "$d/job.scd")"; fi
    cat > "$d/job.scd" <<SCD
(
var def, score;
"M0B-CLASSLIB-OK".postln;
("M0B-NORNS-CLASSES: " ++ [\\Crone, \\CroneEngine, \\CronePoll].collect { |c| c.asClass.notNil }).postln;
("M0B-NOBOOT: " ++ Crone.bootOnInit).postln;
def = SynthDef(\\m0sine, { |out = 0, freq = 440| Out.ar(out, SinOsc.ar(freq, 0, 0.3) ! 2) });
score = ([
    [0.0, ['/d_recv', def.asBytes]],
    [0.0, ['/s_new', \\m0sine, 1000, 0, 0]],
    [1.0, ['/c_set', 0, 0]]
]);
Score.write(score, "$score");
"M0B-SCORE-WRITTEN".postln;
0.exit;
)
SCD
    (cd "$d" && limited "$SCLANG" -D -l "$cfg" "$job") 2>&1 | tee "$d/sclang.out"
    rc=${PIPESTATUS[0]}
    [ "$rc" -eq 124 ] && { echo "sclang TIMED OUT after $SMOKE_TIMEOUT s"; return 1; }
    grep -q "M0B-CLASSLIB-OK" "$d/sclang.out" || { echo "class library did not compile or the script did not run (sclang exit $rc)"; return 1; }
    grep -q "M0B-NORNS-CLASSES: \[true, true, true\]" "$d/sclang.out" || { echo "norns classes (Crone, CroneEngine, CronePoll) not all compiled"; return 1; }
    grep -q "M0B-NOBOOT: false" "$d/sclang.out" || { echo "norns's server boot was not switched off"; return 1; }
    grep -q "Booting server" "$d/sclang.out" && { echo "a server was booted: not allowed in the smoke test"; return 1; }
    grep -q "M0B-SCORE-WRITTEN" "$d/sclang.out" || { echo "score was not written"; return 1; }
}

# scsynth NRT only (-N): 1 s of the sine to a 16 bit wav, no audio device. the file must have audio in it
nrt_step() { # dir mode
    local d="$1" mode="$2" size nz plug=() sc out rc
    if [ -n "${SC_PLUGINS:-}" ]; then plug=(-U "$(native "$SC_PLUGINS")"); fi
    if [ "$mode" = rel ]; then sc="score.osc"; out="out.wav"; else sc="$(native "$d/score.osc")"; out="$(native "$d/out.wav")"; fi
    (cd "$d" && limited "$SCSYNTH" -N "$sc" _ "$out" 48000 WAV int16 -o 2 "${plug[@]}") 2>&1 | tee "$d/scsynth.out"
    rc=${PIPESTATUS[0]}
    [ "$rc" -eq 124 ] && { echo "scsynth TIMED OUT after $SMOKE_TIMEOUT s"; return 1; }
    [ -s "$d/out.wav" ] || { echo "no output file (scsynth exit $rc)"; return 1; }
    size=$(wc -c < "$d/out.wav")
    nz=$(tail -c +45 "$d/out.wav" | tr -d '\000' | wc -c)
    echo "out.wav: $size bytes, $nz non-zero bytes of audio data"
    [ "$size" -gt 100000 ] && [ "$nz" -gt 1000 ] || { echo "output too small or silent"; return 1; }
}

run_all() { sclang_step "$1" "$2" && nrt_step "$1" "$2"; }

# the REAL-TIME scsynth without an audio device: Verdandi's null audio driver (windows/patches/scsynth-null-audio.patch, VERDANDI_NULL_AUDIO=1). boots, answers /status over UDP, its clock runs at the nominal rate, quits
PYTHON="${PYTHON:-$(command -v python3 || command -v python || command -v py)}"
null_audio_step() {
    local d="$T/null-audio" port=57199 pid rc plug=()
    mkdir -p "$d"
    if [ -n "${SC_PLUGINS:-}" ]; then plug=(-U "$(native "$SC_PLUGINS")"); fi
    [ -n "$PYTHON" ] || { echo "no python on this machine"; return 1; }
    (cd "$d" && VERDANDI_NULL_AUDIO=1 limited "$SCSYNTH" -u "$port" -a 1024 -i 2 -o 2 "${plug[@]}" > scsynth-rt.out 2>&1) &
    pid=$!
    "$PYTHON" "$(native "$HERE/osc_status.py")" "$port" --quit
    rc=$?
    sleep 2
    kill "$pid" 2> /dev/null || true
    wait "$pid" 2> /dev/null || true
    cat "$d/scsynth-rt.out"
    grep -q "SC_NullAudioDriver" "$d/scsynth-rt.out" || { echo "the null audio driver was not used (is the patch applied?)"; return 1; }
    return "$rc"
}

m0_init
m0_run smoke-tools check_tools || exit 1
m0_run smoke-sclang-nrt run_all "$T/plain" abs
m0_run smoke-null-audio null_audio_step
m0_run smoke-spaces run_all "$T/path with spaces/second folder" abs
# information only (names start with info-): not part of the pass/fail mark of the run
m0_run info-nonascii-abs run_all "$T/non-ascii/Ünï code" abs
m0_run info-nonascii-rel run_all "$T/non-ascii/Ünï rel" rel
cleanup_procs
exit 0
