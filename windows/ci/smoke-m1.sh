#!/usr/bin/env bash
# windows/ci/smoke-m1.sh (M1): start the built program headless and look at what it did. bash (Git Bash on the runner).
#   ZIP   Verdandi-windows-<version>-<hash>.zip (assemble-m1.sh)     WORK   a scratch folder (default: a temp folder)     SMOKE_SECONDS   how long the program runs (default 90)
# the program is unpacked into a folder whose name has SPACES, started with the launcher in its headless mode (SDL dummy video driver, no dialogs; the null audio driver is always used in M1), with a
# seeded system.state that makes norns resume the script smoke/verdandi_smoke.lua, which draws, saves its screen as a PNG and prints VERDANDI_SMOKE_OK. then the logs and the picture are checked.
# what this proves: the exe starts, matron boots Lua, sclang compiles the class library with norns's classes, scsynth runs with no audio device, the sidecar and the logs work, a script runs and draws.
# what it does not: how the window looks and feels (the owner's checklist).
# shellcheck disable=SC2329
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=windows/ci/lib.sh
. "$HERE/lib.sh"
ZIP="${ZIP:?ZIP is not set}"
WORK="${WORK:-$(mktemp -d)}"
SECONDS_RUN="${SMOKE_SECONDS:-90}"
PYTHON="${PYTHON:-$(command -v python3 || command -v python || command -v py)}"
EXE=""
case "$(uname -s)" in MINGW* | MSYS* | CYGWIN*) EXE=".exe" ;; esac
native() { if command -v cygpath > /dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }

APPPARENT="$WORK/Verdandi test folder"
APP="$APPPARENT/Verdandi" # (set again by unpack: the zip holds one folder, Verdandi-<version>-<hash>)
HOMEDIR="$WORK/user home"
LOGS="$HOMEDIR/logs"

# the zip holds one folder, Verdandi-<version>-<hash> (m0_run runs a step in a subshell: the main script calls this again after unpack)
set_app() { APP="$(find "$APPPARENT" -maxdepth 1 -mindepth 1 -type d -name 'Verdandi*' | head -n 1)"; }

unpack() {
    rm -rf "$APPPARENT" "$HOMEDIR"
    mkdir -p "$APPPARENT"
    if command -v 7z > /dev/null 2>&1; then 7z x "$ZIP" "-o$APPPARENT" -y > /dev/null; else unzip -q -o "$ZIP" -d "$APPPARENT"; fi
    set_app
    [ -n "$APP" ] && [ -f "$APP/Verdandi$EXE" ] || { echo "no Verdandi$EXE in a folder of $APPPARENT"; return 1; }
    echo "unpacked: $APP"
    [ -f "$APP/BUILD.txt" ] && head -n 1 "$APP/BUILD.txt"
}

seed() { seed_home "$HOMEDIR"; }
seed_home() { # a home folder in which norns resumes the smoke script
    local H="$1"
    mkdir -p "$H/dust/code/verdandi_smoke" "$H/dust/data/verdandi_smoke"
    cp "$APP/smoke/verdandi_smoke.lua" "$H/dust/code/verdandi_smoke/verdandi_smoke.lua"
    # norns resumes the last script when it shut down cleanly (lua/core/state.lua): the seeded state says so. the script paths are the virtual /home/we ones
    cat > "$H/dust/data/system.state" <<'ST'
-- norns system state (seeded by the smoke test)
norns.state.clean_shutdown = true
norns.state.script = '/home/we/dust/code/verdandi_smoke/verdandi_smoke.lua'
norns.state.name = 'verdandi_smoke'
norns.state.shortname = 'verdandi_smoke'
norns.state.path = '/home/we/dust/code/verdandi_smoke/'
norns.state.data = '/home/we/dust/data/verdandi_smoke/'
ST
}

run_program() {
    local rc
    # a hard limit well above the run time of the program itself
    if command -v timeout > /dev/null 2>&1; then
        timeout -k 10 $((SECONDS_RUN + 60)) "$APP/Verdandi$EXE" --headless --exit-after="$SECONDS_RUN" --home="$(native "$HOMEDIR")"
    else
        "$APP/Verdandi$EXE" --headless --exit-after="$SECONDS_RUN" --home="$(native "$HOMEDIR")"
    fi
    rc=$?
    echo "launcher exit code $rc"
    if command -v taskkill > /dev/null 2>&1; then taskkill //F //IM norns.exe //IM sclang.exe //IM scsynth.exe > /dev/null 2>&1 || true; fi
    return 0
}

has() { # file pattern what
    if grep -q -E "$2" "$1" 2> /dev/null; then echo "found: $3"; else echo "NOT FOUND: $3 (pattern '$2' in $1)"; return 1; fi
}
chk_launcher() { has "$LOGS/launcher.log" "norns.exe started" "norns.exe started" && has "$LOGS/launcher.log" "sclang.exe started" "sclang.exe started"; }
chk_lua() { has "$LOGS/norns.log" "norns.startup_status.ok|startup_status" "matron's Lua reached the start-up handshake with the SuperCollider side"; }
chk_script() { has "$LOGS/norns.log" "VERDANDI_SMOKE init" "the smoke script was resumed and its init ran" && has "$LOGS/norns.log" "VERDANDI_SMOKE_OK" "the smoke script drew and exported its screen"; }
chk_keyboard() { has "$LOGS/norns.log" "VERDANDI_SMOKE keyboard device yes" "the window keyboard is a HID device" && has "$LOGS/norns.log" "VERDANDI_SMOKE key event A" "a key event reaches keyboard.code"; }
# the shared Lua must not run Linux tools on Windows: "'ls' is not recognized" and the like, and no metro_stop spam, and no select.lua error
chk_noise() {
    if grep -n -E "norns CRASHED|is not recognized|pthread_cancel|menu key handler error|failed to read from stdin|unknown \(0\)" "$LOGS/norns.log" | head -10 | grep .; then return 1; fi
    echo "none of: not recognized, pthread_cancel, menu key handler error, failed to read from stdin, unknown (0)"
}
# M2: the audio chain on the runner (it has no sound card, so null audio or a card, whichever it is, is reported)
chk_audio() {
    has "$LOGS/norns.log" "^audio: PortAudio .*host APIs:" "PortAudio and its host APIs are listed in the log" \
        && has "$LOGS/norns.log" "^audio: output chosen: .*input: .*block " "the choice (output, input, rate, block) is in the log" \
        && has "$LOGS/norns.log" "^audio: input is OFF at the start" "the input is OFF at the start (no feedback)" \
        && has "$LOGS/norns.log" "VERDANDI_SMOKE_AUDIO .*input=off" "norns reports the input as off" \
        && { [ "${EXPECT_ASIO:-0}" != 1 ] || has "$LOGS/norns.log" "^audio: PortAudio .*host APIs:.*ASIO\\(" "this is the ASIO build: PortAudio lists the ASIO host API (with 0 drivers on a runner)"; } \
        && { [ "${EXPECT_ASIO:-0}" = 1 ] || ! grep -q -E "^audio: PortAudio .*host APIs:.*ASIO\\(" "$LOGS/norns.log" 2> /dev/null || { echo "NOT EXPECTED: ASIO in the WASAPI-only build"; false; }; } \
        && has "$LOGS/norns.log" "^audio: (device '|null audio|.*null audio is used)" "the audio decision (device or null audio) is in the log" \
        && has "$LOGS/norns.log" "^audio bridge: '.*' ready" "norns.exe made the audio bridge" \
        && has "$LOGS/sclang.log" "SC_BridgeAudioDriver: the first block was computed" "scsynth computed its first block from the bridge" \
        && has "$LOGS/norns.log" "VERDANDI_SMOKE_AUDIO mode=(device|null|fallback) .*scsynth=true" "scsynth is attached to the bridge" \
        && awk '/VERDANDI_SMOKE_AUDIO mode=/ { for (i = 1; i <= NF; i++) { split($i, kv, "="); v[kv[1]] = kv[2] }; if (v["blocks_to_scsynth"] + 0 > 50 && v["blocks_from_scsynth"] + 0 > 50 && v["drops"] + 0 <= 5) ok = 1 } END { exit ok ? 0 : 1 }' "$LOGS/norns.log" \
        && echo "found: blocks flow both ways (more than 50 in 3 s) with at most 5 drops (underruns are reported, not judged: a loaded runner)"
}
chk_audio_numbers() { grep -h -E "^audio: |^audio bridge: |VERDANDI_SMOKE_AUDIO" "$LOGS/norns.log" 2> /dev/null | head -20; }
# the list of devices (all host APIs), with no program running: norns.exe alone, VERDANDI_AUDIO_LIST=1
list_audio() {
    local out
    out=$(cd "$APP" && VERDANDI_AUDIO_LIST=1 HOME="$HOMEDIR" timeout 60 "./norns$EXE" 2>&1) || true
    echo "$out" | head -20
    echo "$out" | grep -q -E "^[0-9]+ devices"
}
# a device that does not exist: no hang, a plain note, null audio, and the bridge still works
run_fallback() {
    local h2="$WORK/user home fallback"
    rm -rf "$h2"
    mkdir -p "$h2"
    # (an output that is not there, an input that is not there, channels: all of audio.conf's M3 keys at once)
    printf 'output=wasapi:No Such Speakers 4711\ninput=wasapi:No Such Microphone 4711\nrate=48000\nblock=128\nout_first=1\nin_l=3\nin_r=4\n' > "$h2/audio.conf"
    if command -v timeout > /dev/null 2>&1; then
        timeout -k 10 120 "$APP/Verdandi$EXE" --headless --exit-after=45 --home="$(native "$h2")"
    else
        "$APP/Verdandi$EXE" --headless --exit-after=45 --home="$(native "$h2")"
    fi
    echo "launcher exit code $?"
    if command -v taskkill > /dev/null 2>&1; then taskkill //F //IM norns.exe //IM sclang.exe //IM scsynth.exe > /dev/null 2>&1 || true; fi
    cp -r "$h2/logs" "$M0_OUT/m2-fallback-logs" 2> /dev/null || true
    return 0
}
chk_fallback() {
    local l="$WORK/user home fallback/logs/norns.log"
    has "$l" "not found.*null audio is used|null audio is used" "a device that does not exist is said in plain words, with null audio instead" \
        && has "$l" "^audio: output chosen: 'wasapi:No Such Speakers 4711', input: 'wasapi:No Such Microphone 4711'" "the log says what was chosen: output and input" \
        && has "$l" "^audio: channels: .*input left 3 right 4" "and the channels" \
        && has "$l" "^audio bridge: '.*' ready" "the bridge was made anyway" \
        && has "$WORK/user home fallback/logs/sclang.log" "SC_BridgeAudioDriver: audio from norns.exe" "scsynth still runs, on the bridge" \
        && [ -f "$WORK/user home fallback/audio.conf.failed" ] && echo "found: audio.conf.failed (the AUDIO page says it)"
}
# M3: an ASIO driver that does not exist (in the ASIO build this goes through the ASIO host API, in the WASAPI-only build through the same "not found" path): a plain note, never a hang.
# and the input switch with VERDANDI_SMOKE_INPUT=1: MIC and SYS answer yes or no on a runner that may have no input, OFF always works, nothing crashes
IN_HOME="$WORK/user home input"
run_input() {
    rm -rf "$IN_HOME"
    # a freshly seeded home (the first version copied system.state from the first run's home: after that run norns had rewritten it, no script was resumed, and the probe never ran)
    seed_home "$IN_HOME"
    printf 'output=asio:No Such Driver 4711\ninput=asio:No Such Driver 4711\nrate=48000\nblock=128\n' > "$IN_HOME/audio.conf"
    if command -v timeout > /dev/null 2>&1; then
        VERDANDI_SMOKE_INPUT=1 timeout -k 10 150 "$APP/Verdandi$EXE" --headless --exit-after=100 --home="$(native "$IN_HOME")"
    else
        VERDANDI_SMOKE_INPUT=1 "$APP/Verdandi$EXE" --headless --exit-after=100 --home="$(native "$IN_HOME")"
    fi
    echo "launcher exit code $?"
    if command -v taskkill > /dev/null 2>&1; then taskkill //F //IM norns.exe //IM sclang.exe //IM scsynth.exe > /dev/null 2>&1 || true; fi
    cp -r "$IN_HOME/logs" "$M0_OUT/m3-input-logs" 2> /dev/null || true
    return 0
}
chk_input() {
    local l="$IN_HOME/logs/norns.log"
    # the lines that explain a failure, always in the report: what the program decided, what the probe printed, whether the script ran at all
    echo "--- relevant lines of norns.log ($l):"
    grep -a -E "^audio: |VERDANDI_SMOKE|SCRIPT|script clear|norns.state|error|ERROR" "$l" 2> /dev/null | head -60
    echo "--- system.state of this home:"; head -n 12 "$IN_HOME/dust/data/system.state" 2> /dev/null
    echo "--- launcher.log (last 15):"; tail -n 15 "$IN_HOME/logs/launcher.log" 2> /dev/null
    echo "---"
    has "$l" "^audio: output chosen: 'asio:No Such Driver 4711'" "the ASIO choice is in the log" \
        && has "$l" "null audio is used|not found, using the default device" "an ASIO driver that is not there is said in plain words (null audio, or the default device)" \
        && has "$l" "VERDANDI_SMOKE_INPUT start ok=true state=off" "the input is off at the start" \
        && has "$l" "VERDANDI_SMOKE_INPUT mic ok=false state=off note=\\[MIC: " "MIC without an input device says no, with the reason" \
        && has "$l" "VERDANDI_SMOKE_INPUT sys-2s ok=true state=(system|off)" "SYS answers (loopback or a note), and the program runs on" \
        && has "$l" "VERDANDI_SMOKE_INPUT off ok=true state=off" "OFF always works" \
        && has "$l" "VERDANDI_SMOKE_INPUT measured=-[12]" "the measurement with no input does not invent a number (no signal, or still waiting)" \
        && has "$l" "VERDANDI_SMOKE_APPLY rc=[0-2] msg=" "a live change to a device that does not exist is answered (reverted or silent), no hang" \
        && has "$l" "VERDANDI_SMOKE_APPLY after: mode=(device|fallback|null)" "and norns and the script run on afterwards" \
        && has "$l" "VERDANDI_SMOKE_INPUT_DONE" "the whole input run finished" \
        && ! grep -q "norns CRASHED" "$l"
}
# M2: ten starts and restarts in a row. norns.exe ends with exit code 42 when it asks for a restart (SYSTEM > RESTART, APPLY on the AUDIO page), the launcher starts everything again.
# the restarts are asked for by lua/core/test_cycles.lua, switched on by VERDANDI_TEST_CYCLES (the launcher numbers the starts in VERDANDI_ROUND): not by a script. (the first version seeded a script that
# asked for the restart: but a restart clears the script before it saves the state, as on a norns, so only the first start ran it and the run hung in the second: "NO SCRIPT", 27 minutes, then the time limit.)
CYCLES="${SMOKE_CYCLES:-10}"
CYCLE_HOME="$WORK/user home cycles"
leftovers() { # the programs of the zoo that are still alive
    if command -v tasklist > /dev/null 2>&1; then tasklist //FO CSV //NH 2> /dev/null | grep -i -E '"(norns|sclang|scsynth|Verdandi)\.exe"' || true; fi
}
run_cycles() {
    rm -rf "$CYCLE_HOME"
    mkdir -p "$CYCLE_HOME"
    # every start may take as long as the 150 s start-up wait of matron plus the restart itself; a hang is cut after cycles * 100 s + 2 minutes, never after half an hour
    local limit=$((CYCLES * 100 + 120)) rc
    if command -v timeout > /dev/null 2>&1; then
        VERDANDI_TEST_CYCLES="$CYCLES" timeout -k 10 "$limit" "$APP/Verdandi$EXE" --headless --home="$(native "$CYCLE_HOME")"
    else
        VERDANDI_TEST_CYCLES="$CYCLES" "$APP/Verdandi$EXE" --headless --home="$(native "$CYCLE_HOME")"
    fi
    rc=$?
    echo "launcher exit code $rc"
    echo "$rc" > "$CYCLE_HOME/launcher.rc"
    sleep 2
    leftovers > "$CYCLE_HOME/leftovers.txt"
    if [ -s "$CYCLE_HOME/leftovers.txt" ] && command -v taskkill > /dev/null 2>&1; then taskkill //F //IM norns.exe //IM sclang.exe //IM scsynth.exe > /dev/null 2>&1 || true; fi
    cp -r "$CYCLE_HOME/logs" "$M0_OUT/m2-cycle-logs" 2> /dev/null || true
    return 0
}
# what went wrong, from the logs: the launcher log, and the log of the LAST round (norns.log and sclang.log are appended by every round: from the last start line on), without the lists of OSC commands
cycle_failure_report() {
    local L="$CYCLE_HOME/logs" first
    echo "=== the failing round: the logs of the last start ==="
    echo "--- launcher.log (all):"
    tr -d '\r' < "$L/launcher.log" 2> /dev/null
    first=$(grep -n '^Verdandi Windows build' "$L/norns.log" 2> /dev/null | tail -n 1 | cut -d: -f1)
    echo "--- norns.log of the last start (from line ${first:-1}, the lists of OSC commands left out, the last 150 lines):"
    tail -n +"${first:-1}" "$L/norns.log" 2> /dev/null | tr -d '\r' | grep -v -E '^/(set|softcut|poll|tape)/|^/(hello|goodbye|quit) ' | tail -n 150
    first=$(grep -n -i 'compiling class library' "$L/sclang.log" 2> /dev/null | tail -n 1 | cut -d: -f1)
    echo "--- sclang.log of the last start (from line ${first:-1}, the last 80 lines):"
    tail -n +"${first:-1}" "$L/sclang.log" 2> /dev/null | tr -d '\r' | tail -n 80
    echo "--- crash reports: $(find "$L/crash" -type f 2> /dev/null | tr '\n' ' ')"
    echo "--- programs still running: $(tr -d '\r' < "$CYCLE_HOME/leftovers.txt" 2> /dev/null | tr '\n' ' ')"
}
cnt() { local n; n=$(grep -c "$1" "$2" 2> /dev/null || true); echo "${n:-0}"; } # (grep -c prints 0 and fails when nothing matches)
chk_cycles() {
    local L="$CYCLE_HOME/logs" starts restarts ok=0
    starts=$(cnt "norns.exe started" "$L/launcher.log")
    restarts=$(cnt "asked for a restart" "$L/launcher.log")
    echo "norns.exe started $starts times, restarted $restarts times (wanted $CYCLES and $((CYCLES - 1)))"
    echo "stale programs stopped before a start: $(cnt "of an earlier start that is still there" "$L/launcher.log") (should be 0: every round ends clean)"
    echo "rounds that ended with the exit code 42: $(cnt "norns.exe ended with exit code 0x0000002a" "$L/launcher.log")"
    [ "$starts" -eq "$CYCLES" ] && [ "$restarts" -eq $((CYCLES - 1)) ] || ok=1
    grep -q "VERDANDI_CYCLE_DONE $CYCLES" "$L/norns.log" 2> /dev/null || { echo "NOT FOUND: the last round did not reach its end (VERDANDI_CYCLE_DONE $CYCLES)"; ok=1; }
    if grep -q -E "norns CRASHED|0xc0000005" "$L/norns.log" 2> /dev/null; then echo "a crash is in norns.log"; ok=1; fi
    if ls "$L/crash"/* > /dev/null 2>&1; then echo "crash reports exist"; ok=1; fi
    [ "$(cat "$CYCLE_HOME/launcher.rc" 2> /dev/null)" = "0" ] || { echo "the launcher did not end with 0 (it ended with $(cat "$CYCLE_HOME/launcher.rc" 2> /dev/null))"; ok=1; }
    [ ! -s "$CYCLE_HOME/leftovers.txt" ] || { echo "programs are left behind"; ok=1; }
    if [ "$ok" -ne 0 ]; then
        cycle_failure_report
        return 1
    fi
    echo "found: $CYCLES starts, $((CYCLES - 1)) restarts with exit code 42, no crash report, the launcher ended with 0 and no norns.exe, sclang.exe or scsynth.exe is left"
}
chk_sclang() {
    has "$LOGS/sclang.log" "Norns startup" "norns's Crone class started in sclang" \
        && has "$LOGS/sclang.log" "SC_BridgeAudioDriver: audio from norns.exe" "scsynth took its audio from norns.exe through the bridge (no sound device of its own)" \
        && ! grep -q -E "^ERROR: Class not defined|Device unavailable" "$LOGS/sclang.log"
}
chk_png() {
    local png="$HOMEDIR/dust/data/verdandi_smoke/verdandi_smoke.png"
    [ -f "$png" ] || { echo "no screenshot at $png"; return 1; }
    [ -n "$PYTHON" ] || { echo "no python: only the existence of the file is checked"; return 0; }
    "$PYTHON" "$(native "$HERE/png_nonblank.py")" "$(native "$png")"
}
# always last: what the program said, so that a failed start can be read from the report without the artifact. FAIL when the start did not reach the smoke script
chk_diagnostics() {
    echo "--- launcher.log:"; tail -n 20 "$LOGS/launcher.log" 2> /dev/null
    echo "--- norns.log (last 70 lines):"; tail -n 70 "$LOGS/norns.log" 2> /dev/null
    echo "--- sclang.log (last 30 lines):"; tail -n 30 "$LOGS/sclang.log" 2> /dev/null
    grep -q "VERDANDI_SMOKE_OK" "$LOGS/norns.log" 2> /dev/null
}
chk_crash() { if ls "$LOGS/crash"/* > /dev/null 2>&1; then echo "crash reports:"; ls -l "$LOGS/crash"; return 1; fi; echo "no crash reports"; }
collect() {
    mkdir -p "$M0_OUT/m1-run"
    cp -r "$LOGS" "$M0_OUT/m1-run/logs" 2> /dev/null || true
    cp "$HOMEDIR/dust/data/verdandi_smoke/verdandi_smoke.png" "$M0_OUT/m1-run/" 2> /dev/null || true
    cp "$HOMEDIR/.config/SuperCollider/sclang_conf.yaml" "$M0_OUT/m1-run/" 2> /dev/null || true
    echo "collected into $M0_OUT/m1-run"
}

m0_init
m0_run m1-unpack unpack || exit 0
set_app
m0_run m1-seed seed
m0_run m1-run run_program
collect > /dev/null 2>&1
m0_run m1-check-launcher chk_launcher
m0_run m1-check-lua chk_lua
m0_run m2-list-audio list_audio
m0_run m2-check-audio chk_audio
m0_run m2-audio-numbers chk_audio_numbers
m0_run m2-run-fallback run_fallback
m0_run m2-check-fallback chk_fallback
m0_run m3-run-input run_input
m0_run m3-check-input chk_input
m0_run m2-run-cycles run_cycles
m0_run m2-check-cycles chk_cycles
m0_run m1-check-keyboard chk_keyboard
m0_run m1-check-noise chk_noise
m0_run m1-check-sclang chk_sclang
m0_run m1-check-script chk_script
m0_run m1-check-screen chk_png
m0_run m1-check-crash chk_crash
m0_run m1-check-diagnostics chk_diagnostics
exit 0
