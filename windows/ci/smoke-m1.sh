#!/usr/bin/env bash
# windows/ci/smoke-m1.sh (M1): start the built program headless and look at what it did. bash (Git Bash on the runner).
#   ZIP   Verdandi-windows-M1.zip (assemble-m1.sh)     WORK   a scratch folder (default: a temp folder)     SMOKE_SECONDS   how long the program runs (default 90)
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
APP="$APPPARENT/Verdandi"
HOMEDIR="$WORK/user home"
LOGS="$HOMEDIR/logs"

unpack() {
    rm -rf "$APPPARENT" "$HOMEDIR"
    mkdir -p "$APPPARENT"
    if command -v 7z > /dev/null 2>&1; then 7z x "$ZIP" "-o$APPPARENT" -y > /dev/null; else unzip -q -o "$ZIP" -d "$APPPARENT"; fi
    [ -f "$APP/Verdandi$EXE" ] || { echo "no Verdandi$EXE in $APP"; return 1; }
}

seed() {
    mkdir -p "$HOMEDIR/dust/code/verdandi_smoke" "$HOMEDIR/dust/data/verdandi_smoke"
    cp "$APP/smoke/verdandi_smoke.lua" "$HOMEDIR/dust/code/verdandi_smoke/verdandi_smoke.lua"
    # norns resumes the last script when it shut down cleanly (lua/core/state.lua): the seeded state says so. the script paths are the virtual /home/we ones
    cat > "$HOMEDIR/dust/data/system.state" <<'ST'
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
    if grep -n -E "is not recognized|pthread_cancel|menu key handler error|failed to read from stdin|unknown \(0\)" "$LOGS/norns.log" | head -10 | grep .; then return 1; fi
    echo "none of: not recognized, pthread_cancel, menu key handler error, failed to read from stdin, unknown (0)"
}
chk_sclang() {
    has "$LOGS/sclang.log" "Norns startup" "norns's Crone class started in sclang" \
        && has "$LOGS/sclang.log" "SC_NullAudioDriver" "scsynth ran on the null audio driver (no sound device)" \
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
m0_run m1-seed seed
m0_run m1-run run_program
collect > /dev/null 2>&1
m0_run m1-check-launcher chk_launcher
m0_run m1-check-lua chk_lua
m0_run m1-check-keyboard chk_keyboard
m0_run m1-check-noise chk_noise
m0_run m1-check-sclang chk_sclang
m0_run m1-check-script chk_script
m0_run m1-check-screen chk_png
m0_run m1-check-crash chk_crash
m0_run m1-check-diagnostics chk_diagnostics
exit 0
