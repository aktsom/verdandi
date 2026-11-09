#!/usr/bin/env bash
# windows/ci/smoke-sc.sh: the SuperCollider half of the M0b boot smoke test. proves, without an audio device:
#   1. sclang starts and compiles the class library together with norns's own sc/core and sc/engines;
#   2. scsynth runs in non-realtime mode (-N) and renders a test SynthDef to a wav file that is not silent;
#   3. the same again from a directory with spaces and a non-ASCII character in its name (the Windows user name may have either).
# the realtime path (an audio device, the in-process pump of docs/port/windows-plan.md) is not part of M0b.
# bash only, so that it can be tried on Linux against any SuperCollider build:
#   SC_TREE      folder with sclang(.exe) and scsynth(.exe); the class library is $SC_TREE/SCClassLibrary
#   SCLANG, SCSYNTH, SC_CLASSLIB   override the three (for a build tree that is not an install tree)
#   SC_PLUGINS   optional, passed to scsynth as -U
#   NORNS_SC     norns's sc folder (default: <repository>/sc)
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

# a path in the form the tool wants: on Windows C:/..., elsewhere unchanged
native() {
    if command -v cygpath > /dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi
}

write_cfg() { # dir: the class library and the norns classes, nothing from the user's own folders
    {
        echo "includePaths:"
        echo "  - $(native "$SC_CLASSLIB")"
        echo "  - $(native "$NORNS_SC/core")"
        echo "  - $(native "$NORNS_SC/engines")"
        if [ -d "$NORNS_SC/linux-compat" ]; then echo "  - $(native "$NORNS_SC/linux-compat")"; fi
        echo "excludeDefaultPaths: true"
    } > "$1/sclang.cfg"
}

check_tools() {
    local ok=0 f
    for f in "$SCLANG" "$SCSYNTH" "$SC_CLASSLIB" "$NORNS_SC/core"; do
        if [ -e "$f" ]; then echo "found: $f"; else echo "MISSING: $f"; ok=1; fi
    done
    return "$ok"
}

# sclang: compile, define a SynthDef, write a score for the NRT render, exit
sclang_step() { # dir
    local d="$1" nd
    mkdir -p "$d"
    write_cfg "$d"
    nd="$(native "$d")"
    cat > "$d/job.scd" <<SCD
(
var def, score;
"M0B-CLASSLIB-OK".postln;
("M0B-NORNS-CLASSES: " ++ [\\Crone, \\CroneEngine, \\CronePoll].collect { |c| c.asClass.notNil }).postln;
def = SynthDef(\\m0sine, { |out = 0, freq = 440| Out.ar(out, SinOsc.ar(freq, 0, 0.3) ! 2) });
score = ([
    [0.0, ['/d_recv', def.asBytes]],
    [0.0, ['/s_new', \\m0sine, 1000, 0, 0]],
    [1.0, ['/c_set', 0, 0]]
]);
Score.write(score, "$nd/score.osc");
"M0B-SCORE-WRITTEN".postln;
0.exit;
)
SCD
    "$SCLANG" -D -l "$(native "$d/sclang.cfg")" "$(native "$d/job.scd")" 2>&1 | tee "$d/sclang.out"
    grep -q "M0B-CLASSLIB-OK" "$d/sclang.out" || { echo "class library did not compile or the script did not run"; return 1; }
    grep -q "M0B-NORNS-CLASSES: \[true, true, true\]" "$d/sclang.out" || { echo "norns classes (Crone, CroneEngine, CronePoll) not all compiled"; return 1; }
    grep -q "M0B-SCORE-WRITTEN" "$d/sclang.out" || { echo "score was not written"; return 1; }
}

# scsynth NRT: 1 s of the sine to a 16 bit wav, no audio device. the file must have audio in it
nrt_step() { # dir
    local d="$1" size nz plug=()
    if [ -n "${SC_PLUGINS:-}" ]; then plug=(-U "$(native "$SC_PLUGINS")"); fi
    "$SCSYNTH" -N "$(native "$d/score.osc")" _ "$(native "$d/out.wav")" 48000 WAV int16 -o 2 "${plug[@]}" 2>&1 | tee "$d/scsynth.out"
    [ -s "$d/out.wav" ] || { echo "no output file"; return 1; }
    size=$(wc -c < "$d/out.wav")
    nz=$(tail -c +45 "$d/out.wav" | tr -d '\000' | wc -c)
    echo "out.wav: $size bytes, $nz non-zero bytes of audio data"
    [ "$size" -gt 100000 ] && [ "$nz" -gt 1000 ] || { echo "output too small or silent"; return 1; }
}

run_all() { sclang_step "$1" && nrt_step "$1"; }

m0_init
m0_run smoke-tools check_tools || exit 1
m0_run smoke-sclang-nrt run_all "$T/plain"
m0_run smoke-spaces run_all "$T/path with spaces/Ünï code"
exit 0
