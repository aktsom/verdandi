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
    # M6: a script that brought plug-ins for another system (a Raspberry Pi ELF file and a Mac Mach-O file named .scx) and one real Windows x86-64 plug-in (a PE header): the first two must be moved aside
    mkdir -p "$H/dust/code/plugin_test/Extensions"
    printf '\177ELF\002\001\001\000plug-in for the raspberry pi' > "$H/dust/code/plugin_test/Extensions/PiOnly.scx"
    printf '\317\372\355\376plug-in for the mac' > "$H/dust/code/plugin_test/Extensions/MacOnly.scx"
    "$PYTHON" -c "
import sys
b=bytearray(512); b[0:2]=b'MZ'; b[0x3c]=0x80; b[0x80:0x84]=b'PE\0\0'; b[0x84]=0x64; b[0x85]=0x86
open(sys.argv[1],'wb').write(bytes(b))" "$H/dust/code/plugin_test/Extensions/WinX64.scx"
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
        && { [ "${EXPECT_ASIO:-0}" != 1 ] || { grep -a -q "ASIO" "$APP/libportaudio-2.dll" && echo "found: this is the ASIO build: its PortAudio DLL contains the ASIO host API (PortAudio lists it in the log only when an ASIO driver is installed: a runner has none)"; }; } \
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
    # M6: a plug-in pack in the program folder that the launcher must copy to <home>\extensions
    # M7: an older copy of a pack (the first release of the packs: SOURCE-REVISION.txt and plugins\\, no PACK-ID.txt) must be replaced and moved to disabled\\; a folder of the owner's own must not be touched
    mkdir -p "$IN_HOME/extensions/mi-UGens/plugins" "$IN_HOME/extensions/MyOwnExt" && echo oldrev > "$IN_HOME/extensions/mi-UGens/SOURCE-REVISION.txt" && echo x > "$IN_HOME/extensions/mi-UGens/plugins/Old.txt" && echo "MyOwnExt { }" > "$IN_HOME/extensions/MyOwnExt/MyOwnExt.sc"
    # M7 round 3: the class also scans a /home/we path at the start of sclang (the virtual home of the Windows build: dronecaster compiles its drones from such a path)
    mkdir -p "$APP/extensions-seed/SmokePack" && printf 'SmokePack {\n\t*smoke { ^42 }\n\t*initClass { StartUp.add { ("VT_VHOME " ++ PathName("/home/we/dust/code/plugin_test").entries.size).postln; ("VT_VHOME_GLOB " ++ "/home/we/dust/code/plugin_test/*".pathMatch.size).postln; } }\n}\n' > "$APP/extensions-seed/SmokePack/SmokePack.sc"
    # M7 round 3: a maiden.exe of ANOTHER program folder holds maiden's port when the program starts (an earlier build left running): the launcher must stop it and start its own
    STALE="$WORK/stale maiden folder"
    rm -rf "$STALE"; mkdir -p "$STALE"
    if [ -d "$APP/maiden" ]; then
        cp -r "$APP/maiden"/. "$STALE/" 2> /dev/null
        (cd "$STALE" && ./maiden.exe server --host 127.0.0.1 --port 5000 --app app/build --data "$(native "$IN_HOME")/dust" --doc "$(native "$IN_HOME")/doc" --config maiden.yaml > /dev/null 2>&1 &)
        sleep 3
        echo "stale maiden started from $STALE: $(tasklist //FI 'IMAGENAME eq maiden.exe' 2> /dev/null | grep -c maiden.exe) maiden.exe process(es)"
    fi
    # M6: maiden and the consoles are asked from outside while the program runs (windows/ci/maiden_probe.py)
    PROBE_OUT="$M0_OUT/m6-probe.txt"
    rm -f "$PROBE_OUT"
    if [ -n "$PYTHON" ]; then "$PYTHON" "$(native "$HERE/maiden_probe.py")" "$(native "$IN_HOME")" "$(native "$PROBE_OUT")" > "$M0_OUT/m6-probe.log" 2>&1 & fi
    if command -v timeout > /dev/null 2>&1; then
        VERDANDI_SMOKE_INPUT=1 timeout -k 10 260 "$APP/Verdandi$EXE" --headless --exit-after=190 --home="$(native "$IN_HOME")"
    else
        VERDANDI_SMOKE_INPUT=1 "$APP/Verdandi$EXE" --headless --exit-after=190 --home="$(native "$IN_HOME")"
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
# M6: maiden, the consoles, the tools, the plug-in heal and the seeded pack
chk_maiden() {
    echo "--- the probe (windows/ci/maiden_probe.py):"; cat "$M0_OUT/m6-probe.txt" 2> /dev/null; echo "--- maiden.log (last 15):"; tail -n 15 "$IN_HOME/logs/maiden.log" 2> /dev/null
    echo "---"
    has "$IN_HOME/logs/launcher.log" "maiden started: http://127.0.0.1:5000/maiden" "the launcher started maiden on 127.0.0.1" \
        && has "$M0_OUT/m6-probe.txt" "PROBE maiden-api ok" "maiden's API answers" \
        && has "$M0_OUT/m6-probe.txt" "PROBE maiden-web ok" "the web app is served" \
        && has "$M0_OUT/m6-probe.txt" "PROBE maiden-install ok" "a script with an accented, spaced name was installed from a zip into dust/code"
}
chk_repl() {
    has "$M0_OUT/m6-probe.txt" "PROBE repl-norns ok" "the norns console (websocket 5555, ws-wrapper.exe around norns.exe) ran a line of Lua" \
        && has "$M0_OUT/m6-probe.txt" "PROBE repl-origin ok" "a page from another site gets no console" \
        && has "$M0_OUT/m6-probe.txt" "PROBE repl-sclang ok" "the sclang console (websocket 5556) evaluated a line" \
        && has "$M0_OUT/m6-probe.txt" "PROBE repl-ugens ok" "SynthDefs with MiPlaits.ar, MiBraids.ar and Decimator.ar were built (the classes of the packs are known to sclang)" \
        && has "$M0_OUT/m6-probe.txt" "PROBE repl-server ok" "the server answered after a SynthDef with Decimator.ar was added"
}
chk_tools() {
    local l="$IN_HOME/logs/norns.log"
    grep -a -E "VERDANDI_SMOKE_TOOLS" "$l" 2> /dev/null | head -10
    has "$l" "VERDANDI_SMOKE_TOOLS git \\[git version" "git (MinGit) runs through the program's own PATH" \
        && has "$l" "VERDANDI_SMOKE_TOOLS busybox ok" "busybox sh: cp and cmp work (scripts that copy files)" \
        && has "$l" "VERDANDI_SMOKE_TOOLS applets .*unzip.*wget" "busybox has unzip and wget" \
        && has "$l" "VERDANDI_SMOKE_TOOLS submodule ok" "git clones a repository with a submodule (nb voices)"
}
# M7: the plug-in packs: copied with their class files and marker, an older copy replaced (moved to disabled), the owner's own folder untouched, sclang started cleanly with them (no class missing, none twice, no initClass failure)
chk_packs() {
    local H="$IN_HOME" S="$IN_HOME/logs/sclang.log" bad=0 f
    grep -a -E "plug-in pack" "$H/logs/launcher.log" 2> /dev/null | head
    for f in mi-UGens/PACK-ID.txt mi-UGens/Classes/MiPlaits.sc mi-UGens/UNITS.txt sc3-plugins/PACK-ID.txt sc3-plugins/UNITS.txt sc3-plugins/classes/DistortionUGens/sc/DistortionPlugins.sc; do
        [ -f "$H/extensions/$f" ] && echo "found: extensions/$f" || { echo "NOT FOUND: extensions/$f"; bad=1; }
    done
    ls "$H"/extensions/mi-UGens/plugins/*.scx > /dev/null 2>&1 && echo "found: plug-in files in extensions/mi-UGens/plugins" || { echo "NOT FOUND: .scx in extensions/mi-UGens/plugins"; bad=1; }
    [ -d "$H/disabled/mi-UGens-replaced" ] && [ -f "$H/disabled/mi-UGens-replaced/plugins/Old.txt" ] && echo "found: the old copy of mi-UGens was moved to disabled/mi-UGens-replaced" || { echo "NOT FOUND: disabled/mi-UGens-replaced"; bad=1; }
    [ ! -f "$H/extensions/mi-UGens/plugins/Old.txt" ] && echo "found: the new mi-UGens does not hold the old file" || { echo "NOT FOUND: the old file is still in extensions/mi-UGens"; bad=1; }
    [ -f "$H/extensions/MyOwnExt/MyOwnExt.sc" ] && echo "found: the owner's own folder in extensions was not touched" || { echo "NOT FOUND: MyOwnExt untouched"; bad=1; }
    has "$S" "Class tree inited" "sclang initialised its class tree with the packs" || bad=1
    # (the pack check line of VerdandiPackCheck.sc is not an error: it is left out)
    if grep -a -v "^### plug-in packs" "$S" | grep -a -n -E "Class '?[A-Za-z0-9_]+'? not found|duplicate Class found|### initClass of" | head -5 | grep -q .; then
        echo "NOT FOUND (must be absent): class not found / duplicate / initClass failure in sclang.log:"; grep -a -v "^### plug-in packs" "$S" | grep -a -n -E "Class '?[A-Za-z0-9_]+'? not found|duplicate Class found|### initClass of" | head -10; bad=1
    else
        echo "found: no 'Class not found', no 'duplicate Class', no initClass failure in sclang.log"
    fi
    echo "--- the pack check line of sclang:"; grep -a "plug-in packs" "$S" | head -3
    grep -a -q "plug-in packs" "$S" || { echo "NOT FOUND: the pack check line (VerdandiPackCheck.sc ran)"; bad=1; }
    return "$bad"
}
# M7 round 3: scsynth itself, with the packs' folder in SC_PLUGIN_PATH, loads every plug-in (-N: no audio device; the plug-ins are loaded when the world is made): any load error is a line "*** ERROR: LoadLibrary '<file>' err '...'"
# (a missing DLL: FFTW, libsamplerate), "API version" (the wrong SuperCollider) or "ERROR: open directory failed". the job fails on every one
PLUGIN_LOG="$M0_OUT/m7-scsynth-plugins.log"
run_plugin_load() {
    local sc="$APP/supercollider/scsynth$EXE"
    [ -f "$sc" ] || { echo "no scsynth at $sc"; return 1; }
    mkdir -p "$M0_OUT"
    (cd "$IN_HOME" && SC_PLUGIN_PATH="$(native "$IN_HOME/extensions");$(native "$IN_HOME/.local/share/SuperCollider/Extensions")" limited_scsynth "$sc" -N _ _ "$(native "$M0_OUT/plugin-load.wav")" 48000 WAV int16 -V 2 < /dev/null) > "$PLUGIN_LOG" 2>&1
    echo "scsynth exit code $?; $(wc -l < "$PLUGIN_LOG") lines in $PLUGIN_LOG"
    return 0
}
limited_scsynth() { if command -v timeout > /dev/null 2>&1; then timeout -k 5 90 "$@"; else "$@"; fi; }
chk_plugin_load() {
    local bad=0
    sed -n 1,12p "$PLUGIN_LOG" 2> /dev/null
    if grep -a -n -E "\*\*\* ERROR|ERROR: |API version|not installed|Could not load|could not load|open directory failed" "$PLUGIN_LOG" | head -20 | grep -q .; then
        echo "NOT FOUND (must be absent): plug-in load errors of scsynth:"; grep -a -n -E "\*\*\* ERROR|ERROR: |API version|not installed|Could not load|could not load|open directory failed" "$PLUGIN_LOG" | head -30; bad=1
    else
        echo "found: scsynth loaded every plug-in of the packs without one error line"
    fi
    return "$bad"
}
# the real server and sclang.log after SynthDefs with the UGens of the packs were sent (probe repl-plugins): nothing may say "not installed"
chk_plugins_server() {
    local S="$IN_HOME/logs/sclang.log" bad=0 f
    has "$M0_OUT/m6-probe.txt" "PROBE repl-plugins ok" "the real server started a synth of each of MiPlaits, MiBraids, Decimator, MoogLadder and SawDPW (5 nodes, 0 failures)" || bad=1
    if grep -a -n -E "not installed|exception in GraphDef_Recv|\*\*\* ERROR: LoadLibrary|FAILURE IN SERVER /(s_new|d_recv)" "$S" | head -10 | grep -q .; then
        echo "NOT FOUND (must be absent): the server could not use a plug-in:"; grep -a -n -E "not installed|exception in GraphDef_Recv|\*\*\* ERROR: LoadLibrary|FAILURE IN SERVER /(s_new|d_recv)" "$S" | head -20; bad=1
    else
        echo "found: no 'not installed', no GraphDef_Recv exception and no LoadLibrary error in sclang.log"
    fi
    grep -a -q "scsynth plug-in folders besides its own" "$IN_HOME/logs/launcher.log" && echo "found: the launcher put the extension folders on the plug-in path (SC_PLUGIN_PATH)" || { echo "NOT FOUND: the SC_PLUGIN_PATH line in launcher.log"; bad=1; }
    [ -d "$IN_HOME/.local/share/SuperCollider/Extensions" ] && echo "found: the per-user extensions folder of a real norns was created" || { echo "NOT FOUND: .local/share/SuperCollider/Extensions"; bad=1; }
    for f in "VT_VHOME [1-9]" "VT_VHOME_GLOB [1-9]"; do
        has "$S" "$f" "sclang resolved /home/we ($f): PathName and pathMatch found the entries of dust/code/plugin_test" || bad=1
    done
    return "$bad"
}
# the stale maiden of another folder was stopped, ours served, and nothing is left when the program ended
chk_maiden_stale() {
    local L="$IN_HOME/logs/launcher.log" bad=0
    if [ ! -d "$WORK/stale maiden folder/app" ] && [ ! -f "$WORK/stale maiden folder/maiden.exe" ]; then echo "no stale maiden was prepared (no maiden in the zip): skipped"; return 0; fi
    grep -a -E "maiden:" "$L" | head -5
    grep -a -q "maiden: a maiden.exe (process .*holds port .*stopping it" "$L" && echo "found: the launcher stopped the maiden.exe of another folder" || { echo "NOT FOUND: 'a maiden.exe ... holds port ... stopping it' in launcher.log"; bad=1; }
    grep -a -q "maiden started: http://127.0.0.1" "$L" && echo "found: the launcher started its own maiden" || { echo "NOT FOUND: maiden started"; bad=1; }
    if command -v tasklist > /dev/null 2>&1 && tasklist //FI 'IMAGENAME eq maiden.exe' 2> /dev/null | grep -q maiden.exe; then echo "NOT FOUND (must be absent): a maiden.exe is still running after the program ended"; bad=1; else echo "found: no maiden.exe is left after the program ended"; fi
    grep -a -q "maiden stopped with the round" "$L" && echo "found: maiden ended with the round (launcher.log)" || { echo "NOT FOUND: 'maiden stopped with the round'"; bad=1; }
    return "$bad"
}
chk_heal() {
    local H="$IN_HOME"
    grep -a -E "plug-in heal|plug-in pack" "$H/logs/launcher.log" 2> /dev/null | head
    [ ! -f "$H/dust/code/plugin_test/Extensions/PiOnly.scx" ] && [ -f "$H/disabled/plugin_test/Extensions/PiOnly.scx" ] && echo "found: the Raspberry Pi plug-in was moved to disabled" || { echo "NOT FOUND: PiOnly.scx moved to disabled"; return 1; }
    [ ! -f "$H/dust/code/plugin_test/Extensions/MacOnly.scx" ] && [ -f "$H/disabled/plugin_test/Extensions/MacOnly.scx" ] && echo "found: the Mac plug-in was moved to disabled" || { echo "NOT FOUND: MacOnly.scx moved"; return 1; }
    [ -f "$H/dust/code/plugin_test/Extensions/WinX64.scx" ] && echo "found: the Windows x86-64 plug-in stayed" || { echo "NOT FOUND: WinX64.scx stayed"; return 1; }
    grep -a -q "plug-in heal" "$H/disabled/MANIFEST.txt" 2> /dev/null && echo "found: MANIFEST.txt says what was moved and why" || { echo "NOT FOUND: MANIFEST.txt"; return 1; }
    [ -f "$H/extensions/SmokePack/SmokePack.sc" ] && echo "found: the pack of extensions-seed was copied to <home>/extensions" || { echo "NOT FOUND: SmokePack in extensions"; return 1; }
}
# M4: the MIDI layer, OSC and Link on the runner (it has no MIDI device: the OSC input is the one device there is). the numbers of the OSC route (round trip, jitter) and of the clock go to the report
chk_midi() {
    local l="$IN_HOME/logs/norns.log"
    echo "--- midi and clock lines of norns.log:"
    grep -a -E "^midi: |^clock: |^grid: |VERDANDI_SMOKE_MIDI|VERDANDI_SMOKE_GRID" "$l" 2> /dev/null | head -40
    echo "---"
    has "$l" "^midi: WinMM \\(midiIn / midiOut\\)" "the MIDI layer started (WinMM)" \
        && has "$l" "OSC input on 127.0.0.1:" "the OSC input is bound to the loopback only" \
        && has "$l" "^midi: found osc " "the OSC input is a device in the list" \
        && has "$l" "VERDANDI_SMOKE_MIDI osc-route osc.*200 of 200|VERDANDI_SMOKE_MIDI osc-route OSC \\(127.0.0.1\\): .* 200 of 200" "the OSC route came back 200 of 200 times: round trip and jitter above" \
        && has "$l" "VERDANDI_SMOKE_MIDI link peers=[0-9]+ tempo=" "Ableton Link switched on and read" \
        && has "$l" "^grid: serial ports are looked at for monome grids" "the grid monitor started (serial ports, no grid on the runner is expected)" \
        && has "$l" "VERDANDI_SMOKE_GRID status \\[" "the grid page's table can be read" \
        && ! grep -a -q -E "^grid: found " "$l" \
        && has "$l" "VERDANDI_SMOKE_MIDI done" "and off again, the program runs on" \
        && has "$l" "^clock: the internal clock thread is registered with MMCSS" "the clock thread has MMCSS" \
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
    # settings that must survive a restart: every round saved ui.conf, the next round read it back (the Windows rename bug lost every save but the first)
    echo "settings kept across restarts: $(cnt "VERDANDI_CYCLE_KEEP .* ok=true" "$L/norns.log") of $((CYCLES - 1)) rounds read back what the round before saved"
    if grep -q "VERDANDI_CYCLE_KEEP .* ok=false" "$L/norns.log" 2> /dev/null; then echo "A SAVED SETTING WAS LOST AT A RESTART:"; grep "VERDANDI_CYCLE_KEEP" "$L/norns.log"; ok=1; fi
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
m0_run m4-check-midi chk_midi
m0_run m6-check-maiden chk_maiden
m0_run m6-check-repl chk_repl
m0_run m6-check-tools chk_tools
m0_run m6-check-heal chk_heal
m0_run m7-check-packs chk_packs
m0_run m7-run-plugin-load run_plugin_load
m0_run m7-check-plugin-load chk_plugin_load
m0_run m7-check-plugins-server chk_plugins_server
m0_run m7-check-maiden-stale chk_maiden_stale
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
