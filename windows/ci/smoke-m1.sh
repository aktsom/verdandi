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
    # M7 round 4: the situation of the owner's report on 0.8.2, prepared before the program starts: (1) our OLD pack in extensions\\mi-UGens (it has a PACK-ID.txt) with the classes, (2) a Linux-style copy of the same classes in the per-user
    # folder as the emplaitress mod unpacks it (no marker, a Linux plug-in file), so every Mi* class is defined twice; (3) the pack of the first release in extensions\\sc3-plugins (SOURCE-REVISION.txt and plugins\\, no marker) must be
    # replaced; (4) a folder of the owner's own in extensions must not be touched. the launcher has to put the shipped packs in their places, move the old copies to disabled\\ and start sclang without a duplicate class
    PER_USER="$IN_HOME/.local/share/SuperCollider/Extensions"
    if [ -d "$APP/extensions-seed/mi-UGens/Classes" ]; then
        mkdir -p "$IN_HOME/extensions/mi-UGens/Classes" "$IN_HOME/extensions/mi-UGens/plugins" "$PER_USER/mi-UGens/Classes" "$PER_USER/mi-UGens/plugins"
        cp "$APP/extensions-seed/mi-UGens/Classes"/*.sc "$IN_HOME/extensions/mi-UGens/Classes/" && cp "$APP/extensions-seed/mi-UGens/Classes"/*.sc "$PER_USER/mi-UGens/Classes/"
        echo "old-L1" > "$IN_HOME/extensions/mi-UGens/PACK-ID.txt"; echo x > "$IN_HOME/extensions/mi-UGens/plugins/Old.txt"
        printf '\177ELF\002\001\001\000' > "$PER_USER/mi-UGens/plugins/MiPlaits.scx"
    fi
    mkdir -p "$IN_HOME/extensions/sc3-plugins/plugins" "$IN_HOME/extensions/MyOwnExt" && echo oldrev > "$IN_HOME/extensions/sc3-plugins/SOURCE-REVISION.txt" && echo x > "$IN_HOME/extensions/sc3-plugins/plugins/Old.txt" && echo "MyOwnExt { }" > "$IN_HOME/extensions/MyOwnExt/MyOwnExt.sc"
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
    # M9: the installer of the script twins, as its author wrote it (pinned): the smoke script runs it against the real tools (windows/pack/smoke/verdandi_smoke.lua, VERDANDI_SMOKE_TWINS)
    TWINS_REPO="${TWINS_REPO:-danielrigler/twins}"
    TWINS_SHA="${TWINS_SHA:-5dc6206aaae83f3b2a167acdd185578f93079e9a}"
    mkdir -p "$IN_HOME/dust/data/verdandi_smoke"
    if curl -fsSL --retry 3 "https://raw.githubusercontent.com/$TWINS_REPO/$TWINS_SHA/lib/installer/installer.lua" -o "$IN_HOME/dust/data/verdandi_smoke/installer.lua"; then
        echo "twins installer.lua fetched ($TWINS_SHA): $(wc -l < "$IN_HOME/dust/data/verdandi_smoke/installer.lua") lines"
    else
        echo "NOT FETCHED: the twins installer (the twins checks will say so)"
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
    local H="$IN_HOME" S="$IN_HOME/logs/sclang.log" bad=0 f U="$IN_HOME/.local/share/SuperCollider/Extensions"
    grep -a -E "plug-in pack|duplicate" "$H/logs/launcher.log" 2> /dev/null | head -12
    # mi-UGens lives in the per-user folder (where scripts and mods look for it), sc3-plugins in extensions
    for f in "$U/mi-UGens/PACK-ID.txt" "$U/mi-UGens/PACK-TARGET.txt" "$U/mi-UGens/Classes/MiPlaits.sc" "$U/mi-UGens/UNITS.txt" "$H/extensions/sc3-plugins/PACK-ID.txt" "$H/extensions/sc3-plugins/UNITS.txt" "$H/extensions/sc3-plugins/classes/DistortionUGens/sc/DistortionPlugins.sc"; do
        [ -f "$f" ] && echo "found: ${f#"$H"/}" || { echo "NOT FOUND: ${f#"$H"/}"; bad=1; }
    done
    ls "$U"/mi-UGens/plugins/*.scx > /dev/null 2>&1 && echo "found: Windows plug-in files in the per-user mi-UGens" || { echo "NOT FOUND: .scx in the per-user mi-UGens"; bad=1; }
    [ ! -d "$H/extensions/mi-UGens" ] && echo "found: no second copy of mi-UGens in extensions" || { echo "NOT FOUND (must be absent): extensions/mi-UGens"; bad=1; }
    [ -f "$H/disabled/mi-UGens-moved/plugins/Old.txt" ] && echo "found: our old pack in extensions was moved to disabled/mi-UGens-moved (nothing deleted)" || { echo "NOT FOUND: disabled/mi-UGens-moved"; bad=1; }
    ls -d "$H"/disabled/mi-UGens-replaced* > /dev/null 2>&1 && echo "found: the Linux-style copy a mod unpacked was replaced and moved to disabled/mi-UGens-replaced" || { echo "NOT FOUND: disabled/mi-UGens-replaced"; bad=1; }
    [ -f "$H/disabled/sc3-plugins-replaced/plugins/Old.txt" ] && echo "found: the first release's sc3-plugins was replaced (old copy in disabled/sc3-plugins-replaced)" || { echo "NOT FOUND: disabled/sc3-plugins-replaced"; bad=1; }
    [ -f "$H/extensions/MyOwnExt/MyOwnExt.sc" ] && echo "found: the owner's own folder in extensions was not touched" || { echo "NOT FOUND: MyOwnExt untouched"; bad=1; }
    has "$S" "Class tree inited" "sclang initialised its class tree with the packs" || bad=1
    # (the pack check line of VerdandiPackCheck.sc is not an error: it is left out)
    if grep -a -v "^### plug-in packs" "$S" | grep -a -n -E "Class '?[A-Za-z0-9_]+'? not found|duplicate Class found|Library has not been compiled|### initClass of" | head -5 | grep -q .; then
        echo "NOT FOUND (must be absent): class not found / duplicate / failed compile / initClass failure in sclang.log:"; grep -a -v "^### plug-in packs" "$S" | grep -a -n -E "Class '?[A-Za-z0-9_]+'? not found|duplicate Class found|Library has not been compiled|### initClass of" | head -10; bad=1
    else
        echo "found: no 'Class not found', no 'duplicate Class', no failed compile, no initClass failure in sclang.log"
    fi
    echo "--- the pack check line of sclang:"; grep -a "plug-in packs" "$S" | head -3
    grep -a -q "plug-in packs" "$S" || { echo "NOT FOUND: the pack check line (VerdandiPackCheck.sc ran)"; bad=1; }
    has "$M0_OUT/m6-probe.txt" "PROBE repl-modcheck ok" "the emplaitress mod's own check (find MiPlaits.sc in the per-user folder) succeeds: it will not download or unpack a copy" || bad=1
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
# M7 round 4: sclang that cannot compile, on purpose: two folders of the OWNER'S (neither is a pack Verdandi ships) define the same class. the launcher must move nothing, say so in launcher.log and (through
# VERDANDI_LAUNCH_NOTE) in norns.log, and when the round ends say in plain words what failed (the first two paths) and what to do. sclang really fails here: that is the point
FAIL_HOME="$WORK/user home failing"
run_failing() {
    rm -rf "$FAIL_HOME"
    seed_home "$FAIL_HOME"
    mkdir -p "$FAIL_HOME/extensions/OwnA" "$FAIL_HOME/extensions/OwnB"
    echo "OwnClash : Object { }" > "$FAIL_HOME/extensions/OwnA/A.sc"
    echo "OwnClash : Object { }" > "$FAIL_HOME/extensions/OwnB/B.sc"
    if command -v timeout > /dev/null 2>&1; then
        timeout -k 10 150 "$APP/Verdandi$EXE" --headless --exit-after=60 --home="$(native "$FAIL_HOME")"
    else
        "$APP/Verdandi$EXE" --headless --exit-after=60 --home="$(native "$FAIL_HOME")"
    fi
    echo "launcher exit code $?"
    if command -v taskkill > /dev/null 2>&1; then taskkill //F //IM norns.exe //IM sclang.exe //IM scsynth.exe > /dev/null 2>&1 || true; fi
    cp -r "$FAIL_HOME/logs" "$M0_OUT/m7-failing-logs" 2> /dev/null || true
    return 0
}
chk_failing() {
    local L="$FAIL_HOME/logs/launcher.log" bad=0
    grep -a -E "duplicate|SuperCollider did not start" "$L" | head -5
    grep -a "NOTHING was moved" "$L" | grep -a "duplicate classes (1: OwnClash)" | grep -a -q OwnA && grep -a "NOTHING was moved" "$L" | grep -a -q OwnB && echo "found: two folders of the owner's: nothing was moved, said in launcher.log with the class and both folders" || { echo "NOT FOUND: the 'NOTHING was moved' line with OwnClash, OwnA and OwnB"; bad=1; }
    [ -f "$FAIL_HOME/extensions/OwnA/A.sc" ] && [ -f "$FAIL_HOME/extensions/OwnB/B.sc" ] && echo "found: both folders are still where they were" || { echo "NOT FOUND: OwnA and OwnB untouched"; bad=1; }
    grep -a -q "duplicate Class found: 'OwnClash'" "$FAIL_HOME/logs/sclang.log" 2> /dev/null && echo "found: sclang really failed on it (the test is real)" || { echo "NOT FOUND: sclang did not report the duplicate"; bad=1; }
    grep -a -q "SuperCollider did not start: two files define the same class (1 class name(s): OwnClash)" "$L" && echo "found: the round end explains the failure in plain words" || { echo "NOT FOUND: 'SuperCollider did not start: two files define the same class' in launcher.log"; bad=1; }
    grep -a -q "in two folders of yours" "$FAIL_HOME/logs/norns.log" 2> /dev/null && echo "found: norns.log has the note for the norns screen" || { echo "NOT FOUND: the launch note in norns.log"; bad=1; }
    return "$bad"
}
# M7 round 5: the folder of screenshots and GIFs (the Pictures known folder, letters outside ASCII): the real Windows API on the runner (windows/ci/win_paths_probe.c)
run_win_paths() {
    local exe="$WORK/win_paths_probe.exe" gcc_bin
    gcc_bin=$(command -v gcc 2> /dev/null || command -v x86_64-w64-mingw32-gcc 2> /dev/null)
    [ -n "$gcc_bin" ] || { echo "NOT FOUND: a C compiler for the probe on the runner"; return 1; }
    "$gcc_bin" -std=gnu11 -Wall "$(native "$HERE/win_paths_probe.c")" -o "$(native "$exe")" -lole32 -lshell32 || { echo "the probe did not compile"; return 1; }
    "$exe" | tee "$M0_OUT/win-paths-probe.txt"
    ! grep -q "WINPATHS FAIL" "$M0_OUT/win-paths-probe.txt" && grep -q "WINPATHS all passed" "$M0_OUT/win-paths-probe.txt"
}
# M8: extra sample folders: the junction backend of platform/common/extfolders.c on the real Windows (windows/ci/extfolders_probe.c): a path with a blank and an accent, the refusals, a real folder is never touched,
# only a link is removed, the files survive, removal with a file open, a missing target, a long path, a script-like reader through the junction
run_extfolders() {
    local exe="$WORK/extfolders_probe.exe" gcc_bin
    gcc_bin=$(command -v gcc 2> /dev/null || command -v x86_64-w64-mingw32-gcc 2> /dev/null)
    [ -n "$gcc_bin" ] || { echo "NOT FOUND: a C compiler for the probe on the runner"; return 1; }
    "$gcc_bin" -std=gnu11 -Wall -Wno-format-truncation -I "$(native "$HERE/../../matron/src/platform/common")" "$(native "$HERE/extfolders_probe.c")" "$(native "$HERE/../../matron/src/platform/common/extfolders.c")" -o "$(native "$exe")" || { echo "the probe did not compile"; return 1; }
    "$exe" | tee "$M0_OUT/extfolders-probe.txt"
    ! grep -q "EXTFOLDERS FAIL" "$M0_OUT/extfolders-probe.txt" && grep -q "EXTFOLDERS all passed" "$M0_OUT/extfolders-probe.txt"
}
# M8 fix: the folder picker's real code on the runner: the Explorer-style folder window is opened by picker_open, the probe waits for the window, closes it as a Cancel and checks the answer (windows/ci/picker_probe.cc).
# proves COM, the dialog object, its options and Show work; a person choosing a folder is still the owner's check
run_picker() {
    local exe="$WORK/picker_probe.exe" gpp
    gpp=$(command -v g++ 2> /dev/null || command -v x86_64-w64-mingw32-g++ 2> /dev/null)
    [ -n "$gpp" ] || { echo "NOT FOUND: a C++ compiler for the probe on the runner"; return 1; }
    "$gpp" -std=c++17 -Wall -I "$(native "$HERE/../../matron/src")" "$(native "$HERE/picker_probe.cc")" "$(native "$HERE/../../matron/src/platform/windows/folder_picker_win.cc")" -o "$(native "$exe")" -lole32 -lshell32 || { echo "the probe did not compile"; return 1; }
    timeout 90 "$exe" 2>&1 | tee "$M0_OUT/picker-probe.txt"
    ! grep -q "PICKER FAIL" "$M0_OUT/picker-probe.txt" && grep -q "PICKER all passed" "$M0_OUT/picker-probe.txt"
}
# M9 (docs/port/phase-m9.md): the PortedPlugins pack, twins' installer against the real tools, the shims, the markers
chk_twins() {
    local l="$IN_HOME/logs/norns.log" U="$IN_HOME/.local/share/SuperCollider/Extensions/PortedPlugins" bad=0 n
    grep -a -E "VERDANDI_SMOKE_TWINS|\[installer\]" "$l" 2> /dev/null | head -40
    [ -f "$IN_HOME/dust/data/verdandi_smoke/installer.lua" ] || { echo "NOT FOUND: the twins installer was not fetched"; return 1; }
    for n in AnalogChew AnalogLoss AnalogDegrade; do
        for f in "$U/Classes/$n.sc" "$U/plugins/${n}_scsynth.scx" "$U/plugins/${n}_scsynth.so"; do
            [ -f "$f" ] && echo "found: ${f#"$IN_HOME"/}" || { echo "NOT FOUND: ${f#"$IN_HOME"/}"; bad=1; }
        done
        [ ! -s "$U/plugins/${n}_scsynth.so" ] && echo "found: the marker ${n}_scsynth.so is empty (not a program)" || { echo "NOT FOUND: ${n}_scsynth.so should be empty"; bad=1; }
    done
    for f in PACK-ID.txt PACK-TARGET.txt SOURCE-OFFER.txt LICENSE-GPL-3.0.txt MARKERS-README.txt; do
        [ -f "$U/$f" ] && echo "found: PortedPlugins/$f" || { echo "NOT FOUND: PortedPlugins/$f"; bad=1; }
    done
    if find "$IN_HOME/disabled" -name '*_scsynth.so' 2> /dev/null | grep -q .; then echo "NOT FOUND (must be absent): a marker was moved to disabled by a heal"; bad=1; else echo "found: no marker was moved to disabled"; fi
    if grep -a -i -E "_scsynth\.so" "$IN_HOME/logs/launcher.log" "$IN_HOME/logs/sclang.log" "$PLUGIN_LOG" 2> /dev/null | grep -a -i -E "error|could not|cannot|wrong|moved" | grep -q .; then echo "NOT FOUND (must be absent): a log complains about a marker"; bad=1; else echo "found: no log complains about the markers (scsynth does not open them)"; fi
    has "$l" "VERDANDI_SMOKE_TWINS library-check satisfied=true missing=\\[\\]" "twins' library check passes: no 'Missing SuperCollider Libraries' screen (find -printf, class file and plug-in file of the three UGens)" || bad=1
    has "$l" "\\[installer\\] all libraries installed" "the installer itself says all libraries are installed" || bad=1
    has "$l" "VERDANDI_SMOKE_TWINS find-printf \\[.*twins.lua!\\]" "find -printf '%p!' gives its list on the bundled busybox" || bad=1
    has "$l" "VERDANDI_SMOKE_TWINS nice \\[niced\\]" "nice -n 19 <command> runs the command (a busybox applet through the shim)" || bad=1
    has "$l" "VERDANDI_SMOKE_TWINS sudo \\[sudoed\\]" "sudo <command> runs the command" || bad=1
    has "$l" "VERDANDI_SMOKE_TWINS timeout-nice \\[git version" "timeout -k 5 20 nice -n 19 git runs (the update check's command)" || bad=1
    has "$l" "VERDANDI_SMOKE_TWINS clone-status \\[0\\]" "a fresh clone has no local changes (line endings of the bundled git)" || bad=1
    has "$l" "VERDANDI_SMOKE_TWINS check-uptodate state=nil behind=0" "no prompt when the clone is up to date" || bad=1
    has "$l" "VERDANDI_SMOKE_TWINS check-behind state=update behind=1" "the update prompt appears when the author pushed one commit" || bad=1
    has "$l" "VERDANDI_SMOKE_TWINS check-dirty state=nil" "a tracked file with a local change silences the prompt (and nothing else does)" || bad=1
    has "$l" "VERDANDI_SMOKE_TWINS clean-again \\[0\\]" "after undoing the change the tree is clean again" || bad=1
    has "$l" "VERDANDI_SMOKE_TWINS pull state=restart behind_now=0" "K3: git pull --ff-only brought the commit; a changed .sc asks for a restart" || bad=1
    has "$l" "VERDANDI_SMOKE_TWINS after-pull-status \\[0\\] file \\[engine \\{ var two; \\}\\]" "the pull left the tree clean and the new engine file is there" || bad=1
    has "$l" "VERDANDI_SMOKE_TWINS restart returned_in=[0-9.]+s request_file=true" "the installer's restart command returns at once and leaves the restart request (it does not hang on 'Restarting...')" || bad=1
    has "$l" "VERDANDI_SMOKE_TWINS done" "the whole twins flow finished" || bad=1
    has "$M0_OUT/m6-probe.txt" "PROBE repl-ported ok" "the real server started a synth with AnalogChew, AnalogLoss and AnalogDegrade" || bad=1
    has "$M0_OUT/m6-probe.txt" "PROBE repl-twinsfind ok" "twins' own find command, typed into the norns console, finds the class file and the marker" || bad=1
    return "$bad"
}
# M10 (docs/port/phase-m10.md): the script twins with its REAL engine file (lib/engine_twins.sc, cloned at a pinned commit) on the real server, as the owner ran it: the launcher starts everything, the script is resumed,
# a short wav made here is given to both voices through the script's own parameters (engine.read), and the server is asked every few seconds if it lives. a crash is "Server 'localhost' exited with exit code ..." in
# sclang.log; WER LocalDumps writes a minidump of scsynth.exe, which windows/ci/dump_report.py reads (the module and offset of the instruction, the plug-in files that were loaded, the stack words that point into modules).
# the first scenario ("all") is the program as shipped. only when it dies are the others run (each takes out one of the three PortedPlugins UGens of the engine, in a copy of the file) to find which one it is
TW_RESULTS="$M0_OUT/twins-engine-summary.txt"
twins_scenario() { # name [sed expression applied to the engine file of this scenario's copy] [server rate] [wav: channels,rate,bits,seconds] [ext = the sample is the file with the long name under an [ext] link]
    local name="$1" patch="${2:-}" rate="${3:-}" wavspec="${4:-2,48000,16,3}" probewav="${5:-}" H="$WORK/user home twins $1" out="$M0_OUT/twins-$1" dumps
    TWINS_REPO="${TWINS_REPO:-danielrigler/twins}"; TWINS_SHA="${TWINS_SHA:-5dc6206aaae83f3b2a167acdd185578f93079e9a}"
    rm -rf "$H" "$out"; mkdir -p "$out/dumps"
    seed_home "$H"
    mkdir -p "$H/dust/audio/ci"
    if ! git clone -q "https://github.com/$TWINS_REPO" "$H/dust/code/twins" || ! git -C "$H/dust/code/twins" checkout -q "$TWINS_SHA"; then echo "NOT FETCHED: twins at $TWINS_SHA"; echo "$name: not fetched" >> "$TW_RESULTS"; return 1; fi
    if [ -n "$patch" ]; then
        cp "$H/dust/code/twins/lib/engine_twins.sc" "$out/engine_twins.sc.orig"
        sed -i -E "$patch" "$H/dust/code/twins/lib/engine_twins.sc"
        cmp -s "$out/engine_twins.sc.orig" "$H/dust/code/twins/lib/engine_twins.sc" && { echo "the patch did not change the engine file: $patch"; echo "$name: patch had no effect" >> "$TW_RESULTS"; return 1; }
    fi
    # a wav (default 3 seconds, stereo, 48 kHz, 16 bit): two sines and a little noise
    "$PYTHON" -c "
import sys, wave, struct, math, random
ch, sr, bits, secs = [int(x) for x in sys.argv[2].split(',')]
w = wave.open(sys.argv[1], 'wb'); w.setnchannels(ch); w.setsampwidth(bits // 8); w.setframerate(sr)
random.seed(1)
top = 2 ** (bits - 1) - 1
def smp(i, f): return int(top * 0.28 * math.sin(2 * math.pi * f * i / sr) + random.randint(-top // 40, top // 40))
out = bytearray()
for i in range(sr * secs):
    for c in range(ch):
        v = smp(i, 220 if c == 0 else 331)
        out += v.to_bytes(bits // 8, 'little', signed=True)
w.writeframes(bytes(out)); w.close()" "$(native "$H/dust/audio/ci/test.wav")" "$wavspec"
    [ -n "$rate" ] && printf 'rate=%s\nblock=128\n' "$rate" > "$H/audio.conf"
    cat > "$H/dust/data/system.state" <<'ST'
-- norns system state (seeded by the smoke test)
norns.state.clean_shutdown = true
norns.state.script = '/home/we/dust/code/twins/twins.lua'
norns.state.name = 'twins'
norns.state.shortname = 'twins'
norns.state.path = '/home/we/dust/code/twins/'
norns.state.data = '/home/we/dust/data/twins/'
ST
    mkdir -p "$H/dust/data/twins"
    # WER writes a minidump (type 1: with the stacks) of a crashed scsynth.exe here
    dumps="$(cygpath -w "$out/dumps" 2> /dev/null || echo "$out/dumps")"
    for k in scsynth.exe; do
        MSYS_NO_PATHCONV=1 reg add "HKLM\\SOFTWARE\\Microsoft\\Windows\\Windows Error Reporting\\LocalDumps\\$k" /v DumpFolder /t REG_EXPAND_SZ /d "$dumps" /f > /dev/null 2>&1 || echo "NOTE: LocalDumps could not be set (not an administrator?)"
        MSYS_NO_PATHCONV=1 reg add "HKLM\\SOFTWARE\\Microsoft\\Windows\\Windows Error Reporting\\LocalDumps\\$k" /v DumpType /t REG_DWORD /d 1 /f > /dev/null 2>&1
        MSYS_NO_PATHCONV=1 reg add "HKLM\\SOFTWARE\\Microsoft\\Windows\\Windows Error Reporting\\LocalDumps\\$k" /v DumpCount /t REG_DWORD /d 5 /f > /dev/null 2>&1
    done
    VERDANDI_PROBE=twins VERDANDI_PROBE_WAV="$probewav" "$PYTHON" "$(native "$HERE/maiden_probe.py")" "$(native "$H")" "$(native "$out/probe.txt")" > "$out/probe.log" 2>&1 &
    local probe_pid=$!
    if command -v timeout > /dev/null 2>&1; then
        VERDANDI_NO_SERVER_RESTART=1 timeout -k 10 330 "$APP/Verdandi$EXE" --headless --exit-after=250 --home="$(native "$H")"
    else
        VERDANDI_NO_SERVER_RESTART=1 "$APP/Verdandi$EXE" --headless --exit-after=250 --home="$(native "$H")"
    fi
    echo "scenario $name: launcher exit code $?"
    wait "$probe_pid" 2> /dev/null
    if command -v taskkill > /dev/null 2>&1; then taskkill //F //IM norns.exe //IM sclang.exe //IM scsynth.exe > /dev/null 2>&1 || true; fi
    cp -r "$H/logs" "$out/logs" 2> /dev/null || true
    local crashed=0 line
    line="$(grep -a -h "exited with exit code" "$H/logs/sclang.log" 2> /dev/null | head -2 | tr '\n' ' ')"
    [ -n "$line" ] && crashed=1
    grep -q "FAIL" "$out/probe.txt" 2> /dev/null && crashed=1
    ls "$out/dumps"/*.dmp > /dev/null 2>&1 && "$PYTHON" "$(native "$HERE/dump_report.py")" "$out/dumps"/*.dmp > "$out/dump-report.txt" 2>&1
    echo "--- scenario $name: probe results"; cat "$out/probe.txt" 2> /dev/null
    echo "--- scenario $name: processes at the end of the probe:"; cat "$out/probe.log" 2> /dev/null | tail -n 12
    echo "--- scenario $name: the last 60 lines of norns.log"; tail -n 60 "$H/logs/norns.log" 2> /dev/null | cut -c1-220
    echo "--- scenario $name: the last 30 lines of sclang.log"; tail -n 30 "$H/logs/sclang.log" 2> /dev/null | cut -c1-220
    echo "--- scenario $name: crash reports"; ls -la "$H/logs/crash" 2> /dev/null | head
    echo "--- scenario $name: sclang.log lines about the server"; grep -a -n -i "exited with exit code\|ERROR: \|exception in\|not installed\|FAILURE\|Class not found" "$H/logs/sclang.log" 2> /dev/null | head -12
    if [ -f "$out/dump-report.txt" ]; then echo "--- scenario $name: the minidump of scsynth.exe"; cat "$out/dump-report.txt"; else echo "--- scenario $name: no minidump"; fi
    echo "$name: crashed=$crashed ${line:-no 'exited' line}" >> "$TW_RESULTS"
    return 0
}
run_twins_engine() {
    [ "${EXPECT_ASIO:-}" = 1 ] && { echo "skipped in the ASIO job: the same program, measured in the other job"; return 0; }
    : > "$TW_RESULTS"
    twins_scenario all
    # what the owner's PC may have that the first run has not: other server rates and sample formats (44.1 and 96 kHz, 24 bit, a long sample), and the sample as a file with a long name under an [ext] link
    twins_scenario rate44 "" 44100 "2,44100,24,20"
    twins_scenario rate96 "" 96000 "1,96000,16,8"
    twins_scenario extlong "" "" "2,48000,16,3" ext
    if grep -q "^all: crashed=1" "$TW_RESULTS"; then
        # the server died: take out the three UGens one at a time (and all of them) to find the one
        twins_scenario nochew 's/AnalogChew\.ar\(orig, chew_depth, chew_freq, chew_variance\)/orig/'
        twins_scenario noloss 's/AnalogLoss\.ar\(sig, 0\.5, 1, 0\.5, 0\.5\)/sig/'
        twins_scenario nodegrade 's/AnalogDegrade\.ar\(loss, depth, amount, variance, envelope\)/loss/'
        twins_scenario noanalog 's/AnalogChew\.ar\(orig, chew_depth, chew_freq, chew_variance\)/orig/; s/AnalogLoss\.ar\(sig, 0\.5, 1, 0\.5, 0\.5\)/sig/; s/AnalogDegrade\.ar\(loss, depth, amount, variance, envelope\)/loss/'
    fi
    echo "=== summary"; cat "$TW_RESULTS"
    return 0
}
chk_twins_engine() {
    [ "${EXPECT_ASIO:-}" = 1 ] && { echo "skipped in the ASIO job: the same program, measured in the other job"; return 0; }
    cat "$TW_RESULTS" 2> /dev/null
    local bad=0 sc
    for sc in all rate44 rate96 extlong; do
        if grep -q "^$sc: crashed=0" "$TW_RESULTS" 2> /dev/null; then echo "found: the real twins engine ran with a sample loaded, the server lived (scenario '$sc')"; else echo "NOT FOUND: the real twins engine ran with the real server without a crash (scenario '$sc')"; bad=1; fi
    done
    return "$bad"
}
# M10: scsynth.exe is ended from outside three times (windows/ci/maiden_probe.py, VERDANDI_PROBE=kill): the launcher says so in launcher.log, starts everything again twice, then says it stops trying and leaves norns running
KILL_HOME="$WORK/user home kill"
run_server_kill() {
    [ "${EXPECT_ASIO:-}" = 1 ] && { echo "skipped in the ASIO job: the same program, measured in the other job"; return 0; }
    local out="$M0_OUT/server-kill"
    rm -rf "$KILL_HOME" "$out"; mkdir -p "$out"
    seed_home "$KILL_HOME"
    VERDANDI_PROBE=kill "$PYTHON" "$(native "$HERE/maiden_probe.py")" "$(native "$KILL_HOME")" "$(native "$out/probe.txt")" > "$out/probe.log" 2>&1 &
    local probe_pid=$!
    if command -v timeout > /dev/null 2>&1; then
        env -u VERDANDI_NO_SERVER_RESTART -u VERDANDI_SERVER_WATCH_LOG_ONLY timeout -k 10 800 "$APP/Verdandi$EXE" --headless --exit-after=640 --home="$(native "$KILL_HOME")"
    else
        env -u VERDANDI_NO_SERVER_RESTART -u VERDANDI_SERVER_WATCH_LOG_ONLY "$APP/Verdandi$EXE" --headless --exit-after=640 --home="$(native "$KILL_HOME")"
    fi
    echo "launcher exit code $?"
    wait "$probe_pid" 2> /dev/null
    if command -v taskkill > /dev/null 2>&1; then taskkill //F //IM norns.exe //IM sclang.exe //IM scsynth.exe > /dev/null 2>&1 || true; fi
    cp -r "$KILL_HOME/logs" "$out/logs" 2> /dev/null || true
    return 0
}
chk_server_kill() {
    [ "${EXPECT_ASIO:-}" = 1 ] && { echo "skipped in the ASIO job: the same program, measured in the other job"; return 0; }
    local out="$M0_OUT/server-kill" bad=0 want
    echo "--- the probe:"; cat "$out/probe.txt" 2> /dev/null
    echo "--- launcher.log (the lines about the server):"; grep -a -i "scsynth\|round\|restart" "$KILL_HOME/logs/launcher.log" 2> /dev/null | head -40
    for want in kill-1-up kill-1-done kill-1-restarted kill-1-logged kill-2-up kill-2-done kill-2-restarted kill-2-logged kill-3-up kill-3-done kill-3-gave-up kill-3-no-round-4 kill-3-norns-alive kill-3-message kill-notes kill-done; do
        has "$out/probe.txt" "PROBE $want ok" "$want" || bad=1
    done
    return "$bad"
}
# M10: a long file name under an [ext] link (the probe of the scenario 'all' made it): matron's audio.file_info and crone's Tape Reader open it; the log has no 'cannot open sndfile'
chk_longpath() {
    [ "${EXPECT_ASIO:-}" = 1 ] && { echo "skipped in the ASIO job: the same program, measured in the other job"; return 0; }
    local bad=0 t="$M0_OUT/twins-all"
    has "$t/probe.txt" "PROBE twins-ext-add ok" "a folder with a long name was linked as [ext]" || bad=1
    has "$t/probe.txt" "PROBE twins-longpath-info ok" "audio.file_info opens a file whose whole path is over 260 characters, under an [ext] link" || bad=1
    has "$t/probe.txt" "PROBE twins-longpath-tape ok" "the Tape Reader was asked to play it" || bad=1
    if grep -a -q "Tape Reader:: cannot open sndfile" "$t/logs/norns.log" 2> /dev/null; then echo "NOT FOUND (must be absent): 'Tape Reader:: cannot open sndfile' in norns.log"; grep -a "cannot open sndfile" "$t/logs/norns.log" | head -3; bad=1; else echo "found: the Tape Reader opened the long path (no 'cannot open sndfile' in norns.log)"; fi
    return "$bad"
}
# M11: every page of the menu in the real norns.exe (windows/ci/maiden_probe.py, probe repl-menu-pages): no error in init, redraw, enc, key, deinit
chk_menu_pages() {
    grep -a "repl-menu-pages\|VT_PAGE" "$M0_OUT/m6-probe.txt" 2> /dev/null | cut -c1-600
    has "$M0_OUT/m6-probe.txt" "PROBE repl-menu-pages ok" "every page of the menu ran its init, redraw, encoders, keys and deinit without an error in the real program"
}
# M11: a fast turning of the drawn encoder knobs, measured in the real window code (headless: SDL's dummy video driver, so a draw is cheaper than on a screen): the throttled way (the program as shipped) and the old
# way (VERDANDI_ENC_THROTTLE=0: one draw per turn). the line "enc display: ..." of norns.log says how long a turn waited in the queue and how long after the first turn the last draw was
run_enc_burst() {
    [ "${EXPECT_ASIO:-}" = 1 ] && { echo "skipped in the ASIO job: the same program, measured in the other job"; return 0; }
    local mode H out
    for mode in throttled oldway; do
        H="$WORK/user home burst $mode"; out="$M0_OUT/enc-burst-$mode"
        rm -rf "$H" "$out"; mkdir -p "$out"
        seed_home "$H"
        VERDANDI_PROBE=burst "$PYTHON" "$(native "$HERE/maiden_probe.py")" "$(native "$H")" "$(native "$out/probe.txt")" > "$out/probe.log" 2>&1 &
        local probe_pid=$!
        if [ "$mode" = oldway ]; then export VERDANDI_ENC_THROTTLE=0; else unset VERDANDI_ENC_THROTTLE; fi
        if command -v timeout > /dev/null 2>&1; then
            timeout -k 10 200 "$APP/Verdandi$EXE" --headless --exit-after=80 --home="$(native "$H")"
        else
            "$APP/Verdandi$EXE" --headless --exit-after=80 --home="$(native "$H")"
        fi
        unset VERDANDI_ENC_THROTTLE
        wait "$probe_pid" 2> /dev/null
        if command -v taskkill > /dev/null 2>&1; then taskkill //F //IM norns.exe //IM sclang.exe //IM scsynth.exe > /dev/null 2>&1 || true; fi
        cp -r "$H/logs" "$out/logs" 2> /dev/null || true
    done
    return 0
}
chk_enc_burst() {
    [ "${EXPECT_ASIO:-}" = 1 ] && { echo "skipped in the ASIO job: the same program, measured in the other job"; return 0; }
    local bad=0 mode line
    for mode in throttled oldway; do
        echo "--- $mode: $(cat "$M0_OUT/enc-burst-$mode/probe.txt" 2> /dev/null | tr '\n' ' ')"
        line="$(grep -a -h "enc display:" "$M0_OUT/enc-burst-$mode/logs/norns.log" 2> /dev/null | tail -1)"
        echo "    $line"
        [ -n "$line" ] || { echo "NOT FOUND: the line 'enc display:' in the $mode run"; bad=1; }
    done
    line="$(grep -a -h "enc display:" "$M0_OUT/enc-burst-throttled/logs/norns.log" 2> /dev/null | tail -1)"
    # the throttled run: far fewer draws than turns, no turn waited long in the queue, the last draw within a second of the first turn
    if [ -n "$line" ]; then
        local turns draws wait last
        turns=$(echo "$line" | sed -E 's/.*: ([0-9]+) turns.*/\1/'); draws=$(echo "$line" | sed -E 's/.* ([0-9]+) draws.*/\1/')
        wait=$(echo "$line" | sed -E 's/.*a turn waited ([0-9]+) ms.*/\1/'); last=$(echo "$line" | sed -E 's/.*the last draw ([0-9]+) ms after.*/\1/')
        [ "$turns" -ge 3000 ] && echo "found: $turns turns reached the window" || { echo "NOT FOUND: 3000 or more turns in the throttled run ($turns)"; bad=1; }
        [ "$draws" -lt $((turns / 4)) ] && echo "found: $draws draws for $turns turns" || { echo "NOT FOUND: fewer than a quarter as many draws as turns ($draws of $turns)"; bad=1; }
        [ "$wait" -le 1000 ] && echo "found: a turn waited $wait ms in the queue at the most" || { echo "NOT FOUND: no turn waits more than a second ($wait ms)"; bad=1; }
        [ "$last" -le 3000 ] && echo "found: the last draw came $last ms after the first turn" || { echo "NOT FOUND: the last draw within 3 s of the first turn ($last ms)"; bad=1; }
    fi
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
        VERDANDI_TEST_SCRIPT_COPY=1 VERDANDI_TEST_CYCLES="$CYCLES" timeout -k 10 "$limit" "$APP/Verdandi$EXE" --headless --home="$(native "$CYCLE_HOME")"
    else
        VERDANDI_TEST_SCRIPT_COPY=1 VERDANDI_TEST_CYCLES="$CYCLES" "$APP/Verdandi$EXE" --headless --home="$(native "$CYCLE_HOME")"
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
    # M7 round 4: before every restart a script copied the classes of mi-UGens into the per-user folder (VERDANDI_CYCLE_COPY); the failure showed on the NEXT start only. every copy was moved aside by the launcher, sclang never saw a duplicate
    echo "script copies made: $(cnt "VERDANDI_CYCLE_COPY .* ok=true" "$L/norns.log") of $((CYCLES - 1)); copies moved aside by the launcher: $(cnt "duplicate classes .* were defined in" "$L/launcher.log")"
    [ "$(cnt "VERDANDI_CYCLE_COPY .* ok=true" "$L/norns.log")" -ge $((CYCLES - 1)) ] || { echo "the simulated script copies did not all happen"; ok=1; }
    [ "$(cnt "duplicate classes .* were defined in" "$L/launcher.log")" -ge $((CYCLES - 1)) ] || { echo "the launcher did not move every copy aside"; ok=1; }
    if grep -a -q -E "duplicate Class found|Library has not been compiled" "$L/sclang.log" 2> /dev/null; then echo "sclang.log has a duplicate class or a failed compile:"; grep -a -n -E "duplicate Class found|Library has not been compiled" "$L/sclang.log" | head -5; ok=1; fi
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

export VERDANDI_SERVER_WATCH_LOG_ONLY=1 # the checks of the older milestones look at a start as it is (a stop of the server is only logged); only the server-kill run (M10) wants the automatic restart
m0_init
m0_run m1-unpack unpack || exit 0
set_app
m0_run m1-seed seed
m0_run m1-run run_program
collect > /dev/null 2>&1
m0_run m1-check-launcher chk_launcher
m0_run m1-check-lua chk_lua
# M10 diagnostics: what sclang.log says around a stop of its server (and its first lines), printed whatever happens
chk_sclang_context() {
    local l="$LOGS/sclang.log"
    echo "--- sclang.log: $(wc -l < "$l" 2> /dev/null) lines; the lines around 'exited with exit code':"
    grep -a -n -B14 -A4 "exited with exit code" "$l" 2> /dev/null | cut -c1-240 | head -50
    echo "--- the first 25 lines:"; head -n 25 "$l" 2> /dev/null | cut -c1-200
    echo "--- the last 12 lines:"; tail -n 12 "$l" 2> /dev/null | cut -c1-200
    return 0
}
m0_run m10-sclang-context chk_sclang_context
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
m0_run m9-check-twins chk_twins
m0_run m11-check-menu-pages chk_menu_pages
m0_run m10-run-twins-engine run_twins_engine
m0_run m10-check-twins-engine chk_twins_engine
m0_run m10-check-longpath chk_longpath
m0_run m11-run-enc-burst run_enc_burst
m0_run m11-check-enc-burst chk_enc_burst
m0_run m10-run-server-kill run_server_kill
m0_run m10-check-server-kill chk_server_kill
m0_run m7-run-plugin-load run_plugin_load
m0_run m7-check-plugin-load chk_plugin_load
m0_run m7-check-plugins-server chk_plugins_server
m0_run m7-check-maiden-stale chk_maiden_stale
m0_run m7-check-win-paths run_win_paths
m0_run m8-check-extfolders run_extfolders
m0_run m8-check-picker run_picker
m0_run m7-run-failing run_failing
m0_run m7-check-failing chk_failing
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
