#!/bin/bash
# linux/tests/run_all.sh: every test that needs no hardware and no macOS.
#   - the macOS-independent lua tests (macos/tests/*_test.lua)
#   - the C tests of the shared desktop layer (window_keys, device_skin, vgrid)
#   - the upstream waf unit tests (./waf test)
#   - a headless boot: Xvfb + jackd dummy + norns + sclang, loads a script (probe_boot.lua)
# usage: linux/tests/run_all.sh   (after linux/setup-deps.sh and linux/build.sh)
#
# KNOWN failures are listed by name and do not fail the run; they are the phase 2 work
# (docs/port/phase-1.md). a test that fails and is not known fails the run.

set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO"
P=matron/src/platform/macos
M=macos/tests
T="$(mktemp -d)"
# KEEP_LOGS=<dir>: copy every log of this run there before the temporary folder goes (to diagnose a failure)
trap '[ -n "${KEEP_LOGS:-}" ] && { mkdir -p "$KEEP_LOGS" && cp "$T"/*.log "$T"/*.rate "$KEEP_LOGS"/ 2> /dev/null; }; rm -rf "$T"' EXIT
. "$REPO/linux/waf-path.sh"
WAF="$(find_waf)"

FAILED=()
KNOWN=()
run() { # name, command...
    local name="$1"
    shift
    if "$@" > "$T/$name.log" 2>&1; then
        echo "PASS  $name"
    else
        echo "FAIL  $name (log: tail below)"
        tail -5 "$T/$name.log" | sed 's/^/        /'
        FAILED+=("$name")
    fi
}
known() { # name, command...: a failure is expected and recorded
    local name="$1"
    shift
    if "$@" > "$T/$name.log" 2>&1; then
        echo "PASS  $name (was a known failure: update docs/port/phase-1.md)"
    else
        echo "KNOWN $name"
        KNOWN+=("$name")
    fi
}

run "lua:devices midi status" lua5.3 linux/tests/devices_midi_test.lua
run "lua:input monitor per mode" lua5.3 linux/tests/input_monitor_test.lua
run "lua:device window notes" lua5.3 linux/tests/grid_note_test.lua
for t in menu_pages input_modes fileselect_finder output_fader; do
    run "lua:$t" lua5.3 "$M/${t}_test.lua"
done
run "lua:keyboard_hardware" env NORNS_HARDWARE_KEYS=1 lua5.3 "$M/keyboard_hardware_test.lua"
VH="$(mktemp -d)"
run "lua:virtual_home" env HOME="$VH" lua5.3 "$M/virtual_home_test.lua" lua/core/virtual_home.lua
# the real nb library (github.com/sixolet/nb: scripts such as cheat codes 2 include it): fetched if the network allows, else those checks are skipped, said out loud
NB_DIR=""
if timeout 60 git clone -q --depth 1 https://github.com/sixolet/nb.git "$T/nb" 2> /dev/null; then
    NB_DIR="$T/nb"
else
    echo "SKIP  the real nb library could not be fetched (no network?): its checks are not run"
fi
VH2="$(mktemp -d)"
run "lua:virtual_home chunk names (script and library folders from debug.getinfo)" env HOME="$VH2" NB_DIR="$NB_DIR" lua5.3 linux/tests/virtual_chunkname_test.lua lua/core/virtual_home.lua

# gnu11, not c11: M_PI and ptsname need the GNU feature macros, as in the waf build
CFLAGS="-std=gnu11 -D_GNU_SOURCE -I $P -I /usr/local/include"
cc $CFLAGS "$M/window_keys_test.c" "$P/window_keys.c" -o "$T/wkt" && run "c:window_keys" "$T/wkt"
cc $CFLAGS $(pkg-config --cflags cairo) "$M/device_skin_test.c" "$P/device_skin.c" "$P/vgrid_skin.c" \
    "$P/varc_skin.c" "$P/vkeys_skin.c" -o "$T/dst" $(pkg-config --libs cairo) -lm && run "c:device_skin" "$T/dst"
# the Linux window layout (arrangement A: no OUT fader, MUTE in the top row, bigger keys and encoders, the screen at 4 px with the Mac's margins, scaling with the window): the same device_skin.c built with
# -DNORNS_LINUX_DESKTOP, as matron is on Linux. the line above is the Mac layout (the file without the define), unchanged
cc $CFLAGS -DNORNS_LINUX_DESKTOP linux/tests/device_skin_linux_test.c "$P/device_skin.c" "$P/window_keys.c" -o "$T/dsl" \
    $(pkg-config --cflags --libs cairo) -lm && run "c:device_skin_linux (geometry, hit testing, rendered window, keyboard mapping unchanged)" "$T/dsl"
cc $CFLAGS -I matron/src/platform/linux $(pkg-config --cflags cairo) linux/tests/menu_skin_test.c \
    matron/src/platform/linux/menu_skin.c -o "$T/mst" $(pkg-config --libs cairo) -lm && run "c:menu_skin" "$T/mst"
# the screen window's picture rule and its state file (docs/port/detach-plan.md): pure C, no window
cc $CFLAGS -I matron/src/platform/linux linux/tests/screen_window_geom_test.c matron/src/platform/linux/screen_window_geom.c -lm -o "$T/swg" \
    && run "c:screen_window_geom (whole scales crisp, in between by the two-step rule, centred, never cut off)" "$T/swg"
cc $CFLAGS -I matron/src/platform/linux linux/tests/screen_window_conf_test.c matron/src/platform/linux/screen_window_conf.c -o "$T/swc" \
    && run "c:screen_window_conf (state file: defaults, damaged values with log lines, round trip, atomic write)" "$T/swc"
run "scan-fkeys:which scripts name F9, F11, F12, and read Ctrl+M (reads only)" linux/tests/scan_fkeys_test.sh
run "launcher:a second start asks the running Verdandi to raise its window; no answer or no window: one sentence; nothing of its data touched; a crash leaves no lock" linux/tests/second_start_test.sh
# needs libmonome with linux/patches/libmonome-pty-serial.patch (linux/setup-deps.sh)
cc $CFLAGS "$M/vgrid_test.c" "$P/vgrid_proto.c" "$P/vgrid_device.c" -L/usr/local/lib -lmonome -lpthread \
    -o "$T/vgt" && LD_LIBRARY_PATH=/usr/local/lib run "c:vgrid" "$T/vgt"
# libmonome's write to a port that is slow to take data: no message cut in the middle (linux/patches/libmonome-write-retry.patch)
cc $CFLAGS -I matron/src/platform/macos -I/usr/local/include linux/tests/monome_write_test.c "$P/vgrid_proto.c" -L/usr/local/lib -lmonome \
    -lpthread -o "$T/mwt" && LD_LIBRARY_PATH=/usr/local/lib run "c:monome_write (a stalled serial port, no half message)" "$T/mwt"
run "grid:LED data reaches the serial port (script, script change clears, prompt commands)" linux/tests/grid_led_test.sh
cc $CFLAGS "$M/dust_import_test.c" "$P/dust_import.c" -o "$T/dit" && run "c:dust_import" "$T/dit"
# the same as an ordinary user: root can read every file, so the failed-copy case only runs here
chmod 755 "$T" && setpriv --reuid=65534 --regid=65534 --clear-groups true 2> /dev/null &&
    run "c:dust_import (as nobody)" setpriv --reuid=65534 --regid=65534 --clear-groups "$T/dit"
echo "SKIP  c:gif (links ImageIO), objc: drop_test app_input_test"

run "waf:unit tests" "$WAF" test

# maiden (web editor): loopback binds, file API, script install, Origin/Host checks. needs linux/maiden-build.sh
# (built by setup-deps.sh / build.sh); not built (NORNS_NO_MAIDEN=1) is a SKIP, said out loud
if [ -x "${NORNS_MAIDEN_DIR:-$(dirname "$REPO")/maiden}/maiden" ]; then
    run "maiden:server, origin checks" linux/tests/maiden_test.sh "${NORNS_MAIDEN_DIR:-$(dirname "$REPO")/maiden}"
    run "maiden:launcher, norns REPL origin" linux/tests/maiden_launcher_test.sh "${NORNS_MAIDEN_DIR:-$(dirname "$REPO")/maiden}"
    run "maiden:install a script, plug-in check" linux/tests/maiden_install_test.sh "${NORNS_MAIDEN_DIR:-$(dirname "$REPO")/maiden}"
    run "maiden:button (opens maiden, or a note when not running)" linux/tests/maiden_button_test.sh "${NORNS_MAIDEN_DIR:-$(dirname "$REPO")/maiden}"
else
    echo "SKIP  maiden:server, origin checks (maiden is not built: linux/maiden-build.sh)"
fi
run "build:waf-path ignores an unknown or root SUDO_USER" linux/tests/waf_path_test.sh
run "udev:rule syntax and narrowness (monome devices only, uaccess only)" linux/tests/udev_test.sh
run "manual:file, table of contents, sources comments, names exist in the code" linux/tests/manual_test.sh
run "screen:a script's global refresh() is called about 60 times a second, stops with the script, scripts without it are unaffected" linux/tests/refresh_test.sh
run "window:buttons start the system xdg-open with the user's own HOME and XDG folders (not the norns home)" linux/tests/open_browser_test.sh
g++ -std=gnu++14 -D_GNU_SOURCE -DNORNS_LINUX_DESKTOP -I matron/src -I matron/src/device -I matron/src/platform/linux -I matron/src/platform/macos \
    $(pkg-config --cflags lua5.3 libevdev 2>/dev/null) -I/usr/include/libevdev-1.0 linux/tests/device_monitor_null_test.cc -o "$T/dmn" \
    && run "c:device_monitor (devices without node, product, vendor or model: no strdup(NULL), no crash)" "$T/dmn"
run "linux:crash report (signal, thread name, backtrace in the log and crash-report.txt; the default action and the core dump kept)" linux/tests/crash_report_test.sh
cc $CFLAGS -I "$P" linux/tests/ui_look_test.c "$P/ui_look.c" "$P/gif_writer.c" -o "$T/ulk" -lm 2> "$T/ulk.err" || cat "$T/ulk.err"
python3 docs/port/ui-previews/ui_tint.py dump > "$T/ui-dump.txt"
run "c:ui_look (grey correction, tint, brightness: equal to the Python reference at 89600 values; black stays black, white stays white; the gif palette)" "$T/ulk" "$T/ui-dump.txt"
run "lua:file dialog setting (off by default, ticked, unticked at once, saved, damaged value, result and cancel, macOS unchanged)" lua5.3 linux/tests/file_dialog_setting_test.lua
run "lua:box settings and looks (hex, box.conf, built-in and own looks, files, names, both styles take colours)" lua5.3 linux/tests/box_settings_test.lua
run "lua:SYSTEM > BOX page (rows, hex entry, STYLE, PRESET list and markers, SAVE, overwrite and delete questions, scrolling)" lua5.3 linux/tests/box_page_test.lua
run "box:right-click items, Ctrl+M and the menu size (source checks)" linux/tests/box_menu_test.sh
run "lua:ui settings and the UI page (hex parsing, text entry, save, load, damaged file, SYSTEM list)" env NORNS_HARDWARE_KEYS=1 lua5.3 linux/tests/ui_settings_test.lua
run "lua:ui page with the computer keyboard (one press = one step, release changes nothing, rows, hex entry; real keyboard module and menu bindings)" env NORNS_HARDWARE_KEYS=1 lua5.3 linux/tests/ui_keys_test.lua
D="$(mktemp -d)"
run "lua:mods (glob through the virtual home, the page, enable, restart, a failing mod)" env HOME="$D" NORNS_PLATFORM=linux lua5.3 linux/tests/mods_test.lua
run "tidy:flatten dry run (a nested home is reported and nothing is changed; --apply refuses without the typed line)" linux/tests/tidy_flatten_test.sh
run "sc:virtual home in sclang and scsynth (fake engine, control run and fixed run)" linux/tests/sc_virtual_home_test.sh
run "sc:dronecaster (real engine from a clone) finds its drones and makes signal headless" linux/tests/dronecaster_test.sh
run "sc:scan-sc-paths (scripts whose sc files name the virtual home)" linux/tests/scan_sc_paths_test.sh
run "sc:launcher's sclang_conf.yaml (both Linux folders, the switches, an older conf written again with .old kept)" linux/tests/sc_conf_test.sh
run "sc:SynthDef compatibility (mx_malone builds on 3.14, scoped by name, nothing leaks; 3.13.0 and 3.14.1)" linux/tests/sc_synthdef_compat_test.sh
run "sc:the real nb_mxsynths mod in a headless norns on 3.14.1 (mx_malone builds, all 11 voices exist, the mod's files unchanged)" linux/tests/nb_mxsynths_test.sh
run "box:C side (palette, pixel style, hidden row, fonts, sizes; the aluminium style byte for byte; the Mac build)" linux/tests/box_c_test.sh
run "shell:stderr of a command is not part of what a script reads (sidecar_shell, desktop vs device build)" linux/tests/sidecar_stderr_test.sh
run "shell:commands with the virtual home from scripts (os.capture, popen, execute, system_cmd, spaces, look-alikes, a download sequence, mx.samples)" linux/tests/script_shell_test.sh
run "shell:scan-shell-paths (scripts whose shell commands name a norns path)" linux/tests/scan_shell_paths_test.sh
run "package:recommends curl and unzip" linux/tests/package_recommends_test.sh
run "tidy:flatten apply and undo (refusals, backup, checks, rollback, interrupted run, nothing of dust lost)" linux/tests/tidy_flatten_apply_test.sh
run "tidy:disable and restore with a manifest, list, remove-older (and what it never touches), log rotation, caps, crash report pruning" linux/tests/tidy_test.sh
CUH="$(mktemp -d)"
run "lua:SYSTEM > CLEAN UP page (asks before any change, restore, the age row, nothing of yours touched)" env NORNS_HOME="$CUH" NORNS_TIDY="$REPO/linux/tidy.sh" lua5.3 linux/tests/cleanup_page_test.lua
run "package:the .deb version grows with every commit (dpkg --compare-versions)" linux/tests/package_version_test.sh
run "package:build output: status reads only, clean and clean cache, the newest 2 .deb kept" linux/tests/package_out_test.sh
run "branding:display name Verdandi Linux (window title, menu entry, deb description, manual, README), internal names unchanged" linux/tests/display_name_test.sh
run "window:MANUAL button (opens the page, or a note when it is missing)" linux/tests/manual_button_test.sh
run "boot:script and library folders from chunk names (norns loads the script)" env NB_DIR="$NB_DIR" linux/tests/chunkname_test.sh "$T/chunk"

PROBE_LOG="$T/probe.log"
NORNS_HOME="$(mktemp -d)"
ln -s "$REPO" "$NORNS_HOME/norns"
mkdir -p "$NORNS_HOME/dust/code/probe"
cat > "$NORNS_HOME/dust/code/probe/probe.lua" <<'LUA'
engine.name = "PolyPerc"
function init() print("PROBE script init ok") end
function key(n, z) print("PROBE key", n, z) end
function enc(n, d) print("PROBE enc", n, d) end
LUA
NORNS_HOME="$NORNS_HOME" "$REPO/linux/tests/norns_probe.sh" "$REPO/linux/tests/probe_boot.lua" "$PROBE_LOG" > /dev/null 2>&1
boot_ok() {
    local bad=0
    chk() { grep -q "$2" "$PROBE_LOG" || { echo "missing: $1"; bad=1; }; }
    chk "matron reached post-startup" "running post-startup"
    chk "engines listed by sclang (crone ready)" "PROBE engines.5"
    chk "script init" "PROBE script init ok"
    chk "script loaded with its engine" "PROBE loaded.probe.PolyPerc"
    chk "key event" "PROBE key.2.1"
    chk "encoder event" "PROBE enc.1"
    return $bad
}
run "boot:headless (xvfb, jackd dummy, crone, sclang, script)" boot_ok

# MIDI clock and notes through JACK MIDI: a test client plays a 120 BPM "DAW" into Verdandi:midi_in
# (start, a note, song position 16 beats, stop, continue, start again); every transport event prints the beat.
if cc -std=gnu11 "$REPO/linux/tests/jack_midi_clock_test.c" -o "$T/jack_midi_clock_test" $(pkg-config --cflags --libs jack) -lm 2> /dev/null; then
    JH="$(mktemp -d)"
    ln -s "$REPO" "$JH/norns"
    JLOG="$T/jackmidi.log"
    JMT="$T/jack_midi_clock_test" NORNS_HOME="$JH" "$REPO/linux/tests/norns_probe.sh" "$REPO/linux/tests/probe_jackmidi.lua" "$JLOG" > /dev/null 2>&1
    jackmidi_ok() {
        local bad=0
        chk() { grep -q "$2" "$JLOG" || { echo "missing: $1"; bad=1; }; }
        chk "the JACK MIDI device is a norns MIDI device" "PROBE jack midi found.true"
        chk "clock source midi" "PROBE source.midi"
        chk "note on through JACK MIDI" "PROBE jack note.note_on.60.100"
        chk "note off through JACK MIDI" "PROBE jack note.note_off.60.0"
        # the transport events in order: start (beat near 0), continue (beat past the song position), start again (near 0)
        local starts stop
        starts="$(grep "PROBE transport start" "$JLOG" | awk '{print $4}' | tr '\n' ' ')"
        stop="$(grep "PROBE transport stop" "$JLOG" | head -1)"
        set -- $starts
        [ "$#" = 3 ] || { echo "missing: three start events (start, continue, start), got: $starts"; bad=1; }
        awk -v a="${1:-99}" 'BEGIN { exit !(a < 1.5) }' || { echo "start 1 should be near beat 0: ${1:-none}"; bad=1; }
        awk -v a="${2:-0}" 'BEGIN { exit !(a > 15.5) }' || { echo "continue must not reset the beat (after SPP 16): ${2:-none}"; bad=1; }
        awk -v a="${3:-99}" 'BEGIN { exit !(a < 1.5) }' || { echo "start 2 should be near beat 0: ${3:-none}"; bad=1; }
        [ -n "$stop" ] || { echo "missing: a stop event"; bad=1; }
        awk -v b="$(echo "$stop" | awk '{print $4}')" -v t="$(echo "$stop" | awk '{print $5}')" \
            'BEGIN { exit !(b > 15.5 && t > 119 && t < 121) }' || { echo "stop: beat after SPP > 15.5 and tempo 120 +-1 (frame-accurate times), got: $stop"; bad=1; }
        # no transport line may show an infinite or undefined beat or tempo (ticks with equal arrival times)
        if grep "PROBE transport" "$JLOG" | grep -qiE "inf|nan"; then echo "a transport event with an infinite or undefined beat/tempo"; bad=1; fi
        return $bad
    }
    run "clock:midi clock, start, SPP, stop, continue and notes through JACK MIDI" jackmidi_ok
else
    echo "SKIP  clock:jack midi (no jack headers)"
fi

# SYSTEM > AUDIO per audio server mode (own jackd, PipeWire, a server we do not own, the macOS default)
for mode in jackd pipewire jack default; do
    run "lua:audio page ($mode)" lua5.3 linux/tests/audio_page_test.lua "$([ $mode = default ] && echo "" || echo $mode)"
done
# the ALSA card list tool: builds, runs, every line is four TAB separated fields (a container has no cards)
audio_tool_ok() {
    cc -O2 -Wall linux/audio_devices.c -o "$T/audio_devices" $(pkg-config --cflags --libs alsa) || return 1
    "$T/audio_devices" | awk -F'\t' 'NF != 4 { bad = 1 } END { exit bad }'
}
run "c:audio_devices (ALSA card list)" audio_tool_ok

# SYSTEM > AUDIO apply on our own jackd: norns restarts (the sidecar runs the restart action without sudo/systemd)
# and norns.sh restarts jackd with the new rate and period from audio.conf
RH="$(mktemp -d)"
ln -s "$REPO" "$RH/norns"
NORNS_HOME="$RH" "$REPO/linux/tests/norns_probe.sh" "$REPO/linux/tests/probe_audio_restart.lua" "$T/audio-restart.log" > /dev/null 2>&1
audio_restart_ok() {
    local bad=0
    [ "$(cat "$RH/probe.marks.rate_before" 2> /dev/null)" = 48000 ] || { echo "rate before: not 48000"; bad=1; }
    [ "$(cat "$RH/probe.marks.rate_after" 2> /dev/null)" = 44100 ] || { echo "rate after the restart: not 44100 ($(cat "$RH/probe.marks.rate_after" 2> /dev/null))"; bad=1; }
    [ "$(cat "$RH/probe.marks.buf_after" 2> /dev/null)" = 256 ] || { echo "buffer after the restart: not 256"; bad=1; }
    [ "$(cat "$RH/probe.marks.crone" 2> /dev/null || echo 0)" -gt 0 ] || { echo "crone is not back"; bad=1; }
    grep -q "restarting audio" "$T/audio-restart.log" || { echo "norns.sh did not restart audio"; bad=1; }
    return $bad
}
run "audio:apply on our own jackd restarts it with the new settings" audio_restart_ok

# crone picks the sound card on a desktop: audio ports of one physical client (a physical MIDI port beside
# them is not taken), by name prefix if given; no physical ports: norns boots unconnected with a warning
run "audio:launcher decisions (stub pw-cli, pw-jack, wpctl)" "$REPO/linux/tests/launcher_test.sh"
connected() { # file port peer: is peer listed under port in jack_lsp -c output
    awk -v port="$2" -v peer="$3" '/^[^ \t]/ { cur = $0; next } { sub(/^[ \t]+/, ""); if (cur == port && $0 == peer) found = 1 } END { exit !found }' "$1"
}
if command -v jackd > /dev/null; then
    ALOG="$T/audio-two.log"
    "$REPO/linux/tests/audio_ports_test.sh" two-cards "$ALOG" > /dev/null 2>&1
    audio_two_ok() {
        local bad=0
        grep -q "PROBE audio in.Fake Card A" "$ALOG" || { echo "missing: input from the first card"; bad=1; }
        grep -q "PROBE audio out.Fake Card B" "$ALOG" || { echo "missing: output to the card named by NORNS_OUT_PORTS"; bad=1; }
        grep -q "PROBE audio warning.$" "$ALOG" || { echo "a warning where none is due"; bad=1; }
        connected "$ALOG.conn" "Fake Card A:capture_FL" "crone:input_1" || { echo "input 1 not from Fake Card A:capture_FL"; bad=1; }
        connected "$ALOG.conn" "Fake Card A:capture_FR" "crone:input_2" || { echo "input 2 not from Fake Card A:capture_FR"; bad=1; }
        connected "$ALOG.conn" "crone:output_1" "Fake Card B:playback_FL" || { echo "output 1 not to Fake Card B:playback_FL"; bad=1; }
        connected "$ALOG.conn" "crone:output_2" "Fake Card B:playback_FR" || { echo "output 2 not to Fake Card B:playback_FR"; bad=1; }
        connected "$ALOG.conn" "crone:output_1" "Fake Card A:playback_FL" && { echo "output also on the other card"; bad=1; }
        awk '/^[^ \t]/ { midi = ($0 ~ /midi_/); next } midi { found = 1 } END { exit !found }' "$ALOG.conn" && { echo "a MIDI port got connected"; bad=1; }
        return $bad
    }
    run "audio:crone picks one card by prefix, ignores physical MIDI ports" audio_two_ok
    NLOG="$T/audio-none.log"
    "$REPO/linux/tests/audio_ports_test.sh" none "$NLOG" > /dev/null 2>&1
    audio_none_ok() {
        local bad=0
        grep -q "PROBE audio done" "$NLOG" || { echo "norns did not boot without sound card ports"; bad=1; }
        grep -q "PROBE audio warning.no sound card input ports" "$NLOG" || { echo "missing: the input warning"; bad=1; }
        grep -q "no sound card output ports" "$NLOG" || { echo "missing: the output warning"; bad=1; }
        grep -q "cannot start audio" "$NLOG" && { echo "crone still refuses to start"; bad=1; }
        return $bad
    }
    run "audio:no physical ports: boots unconnected with a warning" audio_none_ok
else
    echo "SKIP  audio: no jackd"
fi

# metros are threads: with a lot of static TLS (a desktop with GPU drivers: simulated by LD_PRELOAD) a 16 KiB stack
# cannot be created and the metro never ticked; a script metro must tick and nothing may print "pthread_create"
if cc -shared -fPIC -o "$T/tls_pressure.so" linux/tests/tls_pressure.c 2> /dev/null; then
    MH="$(mktemp -d)"
    ln -s "$REPO" "$MH/norns"
    MLOG="$T/metro.log"
    LD_PRELOAD="$T/tls_pressure.so" NORNS_HOME="$MH" "$REPO/linux/tests/norns_probe.sh" "$REPO/linux/tests/probe_metro.lua" "$MLOG" > /dev/null 2>&1
    metro_ok() {
        local bad=0
        grep -aq "PROBE metro ticks.20" "$MLOG" || { echo "the script metro did not tick 20 times: $(grep -a 'PROBE metro ticks' "$MLOG")"; bad=1; }
        grep -aq "pthread_create" "$MLOG" && { echo "a metro thread could not be created ($(grep -ac pthread_create "$MLOG") messages)"; bad=1; }
        grep -aq "PROBE metro done" "$MLOG" || { echo "probe did not finish"; bad=1; }
        return $bad
    }
    run "metro:a script metro ticks under TLS pressure (24 KB static TLS)" metro_ok
fi

# MIC / SYS / APP / OFF / sink monitor by port flags and names (fake card, fake application streams "Vivaldi",
# "Vivaldi-73", "mpv", a late "Late App"): what feeds crone:input_1/2 in each state
peers() { # file port: what jack_lsp -c lists under port, one per line
    awk -v port="$2" '/^[^ \t]/ { cur = $0; next } cur == port { sub(/^[ \t]+/, ""); print }' "$1"
}
if command -v jackd > /dev/null; then
    ILOG="$T/input.log"
    "$REPO/linux/tests/input_test.sh" "$ILOG" > /dev/null 2>&1
    input_ok() {
        local bad=0 st
        want() { # state port expected-peer: present
            peers "$ILOG.$1" "$2" | grep -qx "$3" || { echo "$1: $2 is not fed by $3"; bad=1; }
        }
        not() { # state port peer: absent
            peers "$ILOG.$1" "$2" | grep -qx "$3" && { echo "$1: $2 is fed by $3, it must not be"; bad=1; }
        }
        only() { # state port count: how many peers
            [ "$(peers "$ILOG.$1" "$2" | wc -l)" = "$3" ] || { echo "$1: $2 has $(peers "$ILOG.$1" "$2" | wc -l) peers, want $3"; bad=1; }
        }
        grep -q "." "$ILOG.start" || { echo "no dump of the start state"; bad=1; }
        # (the start state is crone's own default: the card)
        want start crone:input_1 "Built-in Audio Analog Stereo:capture_FL"
        only off crone:input_1 0
        only off crone:input_2 0
        want mic crone:input_1 "Built-in Audio Analog Stereo:capture_FL"
        want mic crone:input_2 "Built-in Audio Analog Stereo:capture_FR"
        only mic crone:input_1 1
        for st in system system_late; do
            want $st crone:input_1 "Vivaldi:output_FL"
            want $st crone:input_2 "Vivaldi:output_FR"
            want $st crone:input_1 "Vivaldi-73:output_FL"
            want $st crone:input_1 "mpv:output_FL"
            not $st crone:input_1 "Built-in Audio Analog Stereo:capture_FL"
            not $st crone:input_1 "Built-in Audio Analog Stereo:monitor_FL"
            # Reaper's microphone capture stream is not an application
            not $st crone:input_1 "PipeWire ALSA [reaper]/ALSA Capture [reaper]:monitor_FL"
            not $st crone:input_2 "PipeWire ALSA [reaper]/ALSA Capture [reaper]:monitor_FR"
        done
        not app crone:input_1 "PipeWire ALSA [reaper]/ALSA Capture [reaper]:monitor_FL"
        want system_late crone:input_1 "Late App:output_FL"
        not system crone:input_1 "Late App:output_FL"
        want app crone:input_1 "Vivaldi:output_FL"
        want app crone:input_2 "Vivaldi-73:output_FR"
        not app crone:input_1 "mpv:output_FL"
        not app crone:input_1 "Late App:output_FL"
        want monitor crone:input_1 "Built-in Audio Analog Stereo:monitor_FL"
        want monitor crone:input_2 "Built-in Audio Analog Stereo:monitor_FR"
        only monitor crone:input_1 1
        want mic_again crone:input_1 "Built-in Audio Analog Stereo:capture_FL"
        only mic_again crone:input_1 1
        grep -q "PROBE apps.*Vivaldi" "$ILOG" || { echo "app list lacks Vivaldi"; bad=1; }
        grep -q "PROBE apps.*Vivaldi-73" "$ILOG" && { echo "app list shows the stream suffix"; bad=1; }
        grep -q "PROBE apps.*crone" "$ILOG" && { echo "app list shows norns itself"; bad=1; }
        grep -q "PROBE apps.*\(Capture\|reaper\)" "$ILOG" && { echo "app list shows a capture stream"; bad=1; }
        grep -q "PROBE input done" "$ILOG" || { echo "probe did not finish"; bad=1; }
        return $bad
    }
    run "input:MIC, SYS (all apps but norns), APP, sink monitor, OFF by port flags and names" input_ok
fi

# the internal clock at 120 BPM must run at 2 beats per second while the input is SYS in a graph with several clients.
# (the PipeWire flavor with WirePlumber is the bug of docs/port/KNOWN-ISSUES.md item 6, fixed in jack_client.cpp)
clock_rate_ok() { # log: RATE within 5% of 2.0
    awk '/^RATE/ { exit !($2 > 1.9 && $2 < 2.1) }' "$1.rate" || { echo "internal clock: $(cat "$1.rate" 2> /dev/null), want about 2.000 beats/s"; return 1; }
}
if command -v jackd > /dev/null; then
    CLOG="$T/clockrate-jackd.log"
    "$REPO/linux/tests/clock_rate_test.sh" jackd "$CLOG" > /dev/null 2>&1
    run "clock:internal clock 2 beats per second with SYS input in a busy jackd graph" clock_rate_ok "$CLOG"
fi
if command -v pipewire > /dev/null && command -v wireplumber > /dev/null && command -v pw-jack > /dev/null &&
    command -v dbus-run-session > /dev/null; then
    CLOGP="$T/clockrate-pipewire.log"
    "$REPO/linux/tests/clock_rate_test.sh" pipewire "$CLOGP" > /dev/null 2>&1
    run "clock:internal clock 2 beats per second with SYS input under PipeWire + WirePlumber" clock_rate_ok "$CLOGP"
else
    echo "SKIP  clock: PipeWire flavor (needs pipewire, wireplumber, pw-jack, dbus-run-session)"
fi

# another process on the grid's serial port (serialosc-device): the check, from process lists given as data, and against fake
# processes with serialosc's command lines (no root, no real serialosc)
serialosc_unit_ok() {
    g++ -std=c++14 -I third-party/doctest -I matron/src linux/tests/serialosc_conflict_test.cpp -o "$T/serialosc_conflict_test" || return 1
    "$T/serialosc_conflict_test"
}
run "serialosc:conflict logic (process lists as data)" serialosc_unit_ok
if command -v jackd > /dev/null; then
    SLOG="$T/serialosc.log"
    "$REPO/linux/tests/serialosc_test.sh" "$SLOG" > /dev/null 2>&1
    serialosc_ok() {
        local bad=0
        grep -aq "PROBE check without a device process.nil\|PROBE check without a device process$" "$SLOG" || { echo "serialoscd and the detector alone were reported"; bad=1; }
        grep -aq "PROBE note 1.nil" "$SLOG" || { echo "a note without a conflict"; bad=1; }
        grep -aq "PROBE text 2.*serialosc has this grid" "$SLOG" || { echo "the conflict was not found: $(grep -a 'PROBE text 2' "$SLOG")"; bad=1; }
        grep -aq "PROBE note 2.*serialosc has this grid" "$SLOG" || { echo "no note on the device window: $(grep -a 'PROBE note 2' "$SLOG")"; bad=1; }
        [ "$(grep -ac "serialosc: .*sudo systemctl stop serialosc.service" "$SLOG")" = 1 ] || { echo "the log line must appear exactly once, found $(grep -ac "sudo systemctl stop serialosc.service" "$SLOG")"; bad=1; }
        grep -aq "sudo systemctl start serialosc.service" "$SLOG" || { echo "the log line lacks the start command"; bad=1; }
        grep -aq "PROBE text 3.nil" "$SLOG" || { echo "the conflict is still reported after the process ended"; bad=1; }
        grep -aq "PROBE note 3.nil" "$SLOG" || { echo "the note stayed after the conflict was gone"; bad=1; }
        return $bad
    }
    run "serialosc:fake serialosc-device on the grid: one log line, a note, gone when it goes" serialosc_ok
    SLOG2="$T/serialosc-off.log"
    "$REPO/linux/tests/serialosc_test.sh" "$SLOG2" disabled > /dev/null 2>&1
    serialosc_off_ok() {
        grep -aq "PROBE note 2.nil" "$SLOG2" && ! grep -aq "sudo systemctl stop serialosc.service" "$SLOG2" || { echo "reported although NORNS_SERIALOSC_CHECK=0"; return 1; }
    }
    run "serialosc:NORNS_SERIALOSC_CHECK=0 turns the check off" serialosc_off_ok
fi

# SuperCollider plug-ins built for another machine than this one (a script's installer fetched a Raspberry Pi bundle: scsynth stops at the first
# bad file and SuperCollider does not start): the ELF header logic on fake headers, the scanner on a fake extension folder, and the note
# on the device window. report only: nothing is moved
plugin_unit_ok() {
    g++ -std=c++14 -I third-party/doctest -I matron/src linux/tests/plugin_arch_test.cpp -o "$T/plugin_arch_test" || return 1
    "$T/plugin_arch_test"
}
run "plugins:ELF header logic (fake headers as data)" plugin_unit_ok
plugin_check_ok() {
    local out
    out="$("$REPO/linux/tests/plugin_check_test.sh")" || { echo "$out" | grep FAIL; return 1; }
}
run "plugins:scanner on a fake extension folder (nothing is moved)" plugin_check_ok
if command -v jackd > /dev/null; then
    run "launcher:logs, crash and cache folders in the home, the last runs of every log kept, no loose logs or hidden cache" linux/tests/launcher_logs_test.sh
    PLOG="$T/plugin-note.log"
    "$REPO/linux/tests/plugin_note_test.sh" "$PLOG" > /dev/null 2>&1
    plugin_note_ok() {
        local bad=0
        [ "$(grep -ac "^norns.sh: SuperCollider plug-in in .*/fake/ignore: Fake_scsynth.so (32-bit ARM); this machine is" "$PLOG")" = 1 ] || { echo "the log line must appear exactly once"; bad=1; }
        grep -aq "PROBE plugin note 1.PLUGINS: wrong-architecture plug-in, see SYSTEM > CLEAN UP" "$PLOG" || { echo "no note on the device window"; bad=1; }
        grep -aq "PROBE plugin note 2.nil" "$PLOG" || { echo "the note stayed after the file was moved away"; bad=1; }
        return $bad
    }
    run "plugins:norns.sh reports before sclang starts, note on the device window, gone when moved" plugin_note_ok
    PLOG2="$T/plugin-note-off.log"
    "$REPO/linux/tests/plugin_note_test.sh" "$PLOG2" disabled > /dev/null 2>&1
    plugin_off_ok() {
        grep -aq "PROBE plugin note 1.nil" "$PLOG2" && ! grep -aq "SuperCollider plug-in" "$PLOG2" || { echo "reported although NORNS_PLUGIN_CHECK=0"; return 1; }
    }
    run "plugins:NORNS_PLUGIN_CHECK=0 turns the check off" plugin_off_ok
fi

# "sudo systemctl restart norns-*" from a script (a script's installer, os.execute): the shims in linux/shims turn it into a restart request,
# at once, without sudo or a password; other sudo commands get -n; the other systemctl commands go on unchanged
run "shims:sudo and systemctl for norns-* units (fake real programs)" "$REPO/linux/tests/shim_test.sh"
if command -v jackd > /dev/null; then
    HLOG="$T/shim-restart.log"
    "$REPO/linux/tests/shim_restart_test.sh" "$HLOG" > /dev/null 2>&1
    shim_restart_ok() {
        local bad=0
        grep -aq "PROBE sidecar which.*linux/shims/sudo .*linux/shims/systemctl" "$HLOG" || { echo "the sidecar does not see the shims on its PATH"; bad=1; }
        grep -aq "PROBE execute returned.true.0\.[0-9] s" "$HLOG" || { echo "os.execute did not return at once: $(grep -a 'PROBE execute' "$HLOG")"; bad=1; }
        [ "$(grep -ac "^norns: there is no systemd for norns on this build" "$HLOG")" = 1 ] || { echo "the shim's line must appear exactly once"; bad=1; }
        grep -aq "norns: a script asked for a restart" "$HLOG" || { echo "lua did not take the request"; bad=1; }
        grep -aq "norns.sh: restarting norns and sclang" "$HLOG" || { echo "norns.sh did not restart norns"; bad=1; }
        [ "$(cat "$HLOG.crone" 2> /dev/null || echo 0)" -gt 0 ] || { echo "norns is not back after the restart"; bad=1; }
        return $bad
    }
    run "shims:a script's sudo systemctl restart norns-* returns at once and norns restarts itself" shim_restart_ok
fi

# the screen's text placement (docs/port/KNOWN-ISSUES.md item 9): the real matron/src/hardware/screen.cc compiled into a test. the desktop build snaps the
# start of every text to a whole pixel as the device's cairo does (odd-width centered text no longer squished or blurred); the device build is untouched
screen_text_ok() { # variant: desktop | device
    local h inc libs d
    h="$(mktemp -d)"
    ln -s "$REPO" "$h/norns"
    inc="-I matron/src -I matron/src/hardware -I third-party/doctest $(pkg-config --cflags cairo freetype2 lua5.3)"
    libs="$(pkg-config --libs cairo freetype2 lua5.3) -lm"
    [ "$1" = desktop ] && d="-DNORNS_DESKTOP" || d="-DSCREEN_TEXT_DEVICE"
    g++ -std=c++14 $inc $d matron/src/hardware/screen.cc linux/tests/screen_text_test.cc -o "$T/screen_text_$1" $libs || return 1
    HOME="$h" "$T/screen_text_$1"
}
run "screen:text placement, desktop build (whole-pixel start, odd widths crisp)" screen_text_ok desktop
run "screen:text placement, device build (unchanged)" screen_text_ok device

# the optional MIDI auto-connect (midi_in_from= in audio.conf, or NORNS_MIDI_IN_FROM): a port matching a prefix is linked to
# Verdandi:midi_in, a link cut behind norns' back is made again, a client that appears later is linked, a port that does
# not match is not
if command -v jackd > /dev/null; then
    for sc in conf env; do
        GLOG="$T/midilink-$sc.log"
        MIDI_SCENARIO=$sc "$REPO/linux/tests/midi_autoconnect_test.sh" "$GLOG" > /dev/null 2>&1
        midilink_ok() {
            local bad=0
            has() { peers "$GLOG.$1" Verdandi:midi_in | grep -qx "$2"; }
            has start "Fake DAW:out" || { echo "start: Fake DAW:out is not linked"; bad=1; }
            has start "Other:out" && { echo "start: Other:out is linked, it does not match"; bad=1; }
            # (conf: only the 2 s timer can repair, so the cut is visible; env: a registration wakes the thread at once)
            [ $sc = conf ] && has cut "Fake DAW:out" && { echo "the test did not cut the link"; bad=1; }
            has repaired "Fake DAW:out" || { echo "the cut link was not made again within 4 s"; bad=1; }
            has late "Late DAW:out" || { echo "a client that appeared later was not linked"; bad=1; }
            has late "Other:out" && { echo "late: Other:out is linked"; bad=1; }
            grep -aq "PROBE midi_in_status.true.1" "$GLOG" || { echo "status: not 'true, 1 linked' at the start"; bad=1; }
            grep -aq "PROBE midi_in_status late.true.2" "$GLOG" || { echo "status: not 'true, 2 linked' at the end"; bad=1; }
            grep -aq "midi: connected Fake DAW:out" "$GLOG" || { echo "no log line for the first link"; bad=1; }
            grep -aq "midi: reconnected Fake DAW:out" "$GLOG" || { echo "no log line for the repaired link"; bad=1; }
            return $bad
        }
        run "midi:auto-connect to Verdandi:midi_in, repaired when cut ($sc)" midilink_ok
    done
fi

# the window on Xvfb: device skin, oled, mouse, keyboard, virtual grid and arc (needs xdotool, imagemagick)
if command -v xdotool > /dev/null && command -v convert > /dev/null; then
    WH="$(mktemp -d)"
    ln -s "$REPO" "$WH/norns"
    mkdir -p "$WH/dust/code/probe"
    cp "$REPO/linux/tests/scripts/window_probe.lua" "$WH/dust/code/probe/"
    WLOG="$T/window.log"
    NORNS_HOME="$WH" "$REPO/linux/tests/norns_probe.sh" "$REPO/linux/tests/probe_window.lua" "$WLOG" > /dev/null 2>&1
    wl() { grep -q "$1" "$WLOG"; }
    window_ok() {
        local bad=0
        chk() { grep -q "$2" "$WLOG" || { echo "missing: $1"; bad=1; }; }
        chk "script started" "PROBE window init"
        chk "probe ran to the end" "PROBE window done"
        chk "mouse: K2 down" "PROBE key.2.1"
        chk "mouse: K2 up" "PROBE key.2.0"
        chk "mouse wheel: E2" "PROBE enc.2"
        chk "keyboard: 3 = K3 down" "PROBE key.3.1"
        chk "keyboard: 3 = K3 up" "PROBE key.3.0"
        chk "keyboard: w = E1" "PROBE enc.1"
        chk "grid and arc connected" "PROBE devices.virtual grid m0000001.monome arc virtual m0000002"
        chk "click on the grid window: down" "PROBE gridkey.2.2.1"
        chk "click on the grid window: up" "PROBE gridkey.2.2.0"
        chk "arc wheel" "PROBE arcdelta.1.2"
        chk "arc key down" "PROBE arckey.1.1"
        chk "arc key up" "PROBE arckey.1.0"
        chk "keys window is a norns MIDI device (after the JACK MIDI input)" "PROBE midi device.Verdandi JACK in.Verdandi keys"
        chk "click on a piano key: note on" "PROBE midi.note_on.52.111.1"
        chk "click on a piano key: note off" "PROBE midi.note_off.52.0.1"
        chk "typed d: note on" "PROBE midi.note_on.52.100.1"
        chk "keys window closed: the device is gone" "PROBE midi closed.false"
        chk "keys window opened again: the device is back" "PROBE midi reopened.true"
        [ "$(grep -c "PROBE midi.note_on.52.100.1" "$WLOG")" = 2 ] || { echo "missing: a note after reopening"; bad=1; }
        return $bad
    }
    run "window:mouse, keyboard, virtual grid and arc" window_ok
    # the oled shows the script's rectangle (about 8% of it is white), the grid shows the lit key
    oled_mean() { convert "$WH/window-device.png" -crop 440x200+230+420 -colorspace Gray -format "%[fx:mean]" info:; }
    window_pixels() { awk -v m="$(oled_mean)" 'BEGIN { exit !(m > 0.03 && m < 0.3) }'; }
    run "window:oled pixels" window_pixels
    cp "$WH/window-device.png" "$WH/window-devices.png" "${SHOT_DIR:-/dev/null}" 2> /dev/null

    # the in-window menu and the file dialogs, once with a stub zenity answering, once against a mock of the
    # desktop portal (a service on a private session bus: the real portals need a desktop, see
    # docs/port/HARDWARE-CHECKLIST.md)
    menu_scenario() { # picker (zenity|portal)
        local picker="$1"
        MH="$(mktemp -d)"
        ln -s "$REPO" "$MH/norns"
        mkdir -p "$MH/dust/code/probe" "$MH/stub"
        # not under /tmp: files there are volatile and get copied, not linked (dust_import_volatile)
        MI="$(mktemp -d -p /var/tmp)"
        cp "$REPO/linux/tests/scripts/window_probe.lua" "$MH/dust/code/probe/"
        echo "RIFF" > "$MI/picked.wav"
        MLOG="$T/menu-$picker.log"
        if [ "$picker" = zenity ]; then
            printf '#!/bin/sh\nprintf "%%s\\n" "$@" >> "%s/zenity.args"\necho "%s/picked.wav"\n' "$MH" "$MI" > "$MH/stub/zenity"
            chmod +x "$MH/stub/zenity"
            PATH="$MH/stub:$PATH" NORNS_PICKER=zenity NORNS_HOME="$MH" "$REPO/linux/tests/norns_probe.sh" \
                "$REPO/linux/tests/probe_menu.lua" "$MLOG" > /dev/null 2>&1
        else
            # a private session bus with the mock on it; the probe (and norns) run inside
            dbus-run-session -- bash -c '
                '"$PY"' "$0/linux/tests/mock_portal.py" "$1/portal.log" "$2/picked.wav" &
                MOCK=$!
                sleep 1
                NORNS_PICKER=portal NORNS_HOME="$1" "$0/linux/tests/norns_probe.sh" "$0/linux/tests/probe_menu.lua" "$3" > /dev/null 2>&1
                kill $MOCK' "$REPO" "$MH" "$MI" "$MLOG" > /dev/null 2>&1
        fi
        ml() { grep -q "$1" "$MLOG"; }
        menu_ok() {
            local bad=0
            chk() { eval "$2" > /dev/null 2>&1 || { echo "missing: $1"; bad=1; }; }
            chk "menu opened and closed" 'ml "PROBE menu done"'
            chk "screenshot png in dust" 'ls "$MH"/dust/Verdandi*.png'
            chk "gif in dust" 'ls "$MH"/dust/Verdandi*.gif'
            chk "Import files: audio linked" '[ -L "$MH/dust/audio/mac/picked.wav" ]'
            chk "lua file dialog answered" 'ml "PROBE chosen.$MH/dust/audio/mac/picked.wav"'
            if [ "$picker" = zenity ]; then
                chk "zenity asked for files" 'grep -q -- "--file-selection" "$MH/zenity.args" && grep -q -- "--multiple" "$MH/zenity.args"'
            else
                chk "portal got OpenFile for several files" 'grep -q "\"multiple\": true" "$MH/portal.log"'
                chk "portal got OpenFile for one file" 'grep -q "\"multiple\": false" "$MH/portal.log"'
                chk "portal got a start folder" 'grep -q "\"current_folder\": \"/" "$MH/portal.log"'
            fi
            chk "Ctrl+Q ended norns" 'grep -q "norns gone" "$MH/probe.marks"'
            return $bad
        }
        if [ "$picker" = zenity ]; then
            run "window:menu, screenshot, gif, import, file dialog (zenity stub), quit" menu_ok
        else
            run "window:file dialog through the portal (mock portal on a private bus)" menu_ok
        fi
        if [ "$picker" = zenity ]; then
            menu_pixels() { # the open menu is dark where the device is light
                convert "$MH/menu-open.png" -crop 100x60+400+500 -colorspace Gray -format "%[fx:mean]" info: | awk '{ exit !($1 < 0.2) }'
            }
            run "window:menu drawn" menu_pixels
        fi
        rm -rf "$MI"
    }
    menu_scenario zenity
    PY=""
    for cand in python3 python3.12; do
        "$cand" -I -c "import gi" 2> /dev/null && PY="$cand" && break
    done
    if [ -n "$PY" ] && command -v dbus-run-session > /dev/null; then
        menu_scenario portal
    else
        echo "SKIP  portal mock (python3 gi and dbus-run-session not installed)"
    fi
    # "Open the file dialog when a script loads a file": off by default (norns's own browser only), ticked in the window's menu (the dialog opens),
    # unticked (no dialog), saved in ui.conf, and after a restart the menu shows the tick and the dialog opens. a stub zenity counts the dialogs
    dialog_scenario() {
        DH="$(mktemp -d)"
        ln -s "$REPO" "$DH/norns"
        mkdir -p "$DH/dust/code/probe" "$DH/stub"
        DI="$(mktemp -d -p /var/tmp)"
        cp "$REPO/linux/tests/scripts/window_probe.lua" "$DH/dust/code/probe/"
        echo "RIFF" > "$DI/picked.wav"
        printf '#!/bin/sh\nprintf "%%s\\n" "$@" >> "%s/zenity.args"\necho "%s/picked.wav"\n' "$DH" "$DI" > "$DH/stub/zenity"
        chmod +x "$DH/stub/zenity"
        DLOG1="$T/dialog1.log"
        DLOG2="$T/dialog2.log"
        PATH="$DH/stub:$PATH" NORNS_PICKER=zenity NORNS_HOME="$DH" "$REPO/linux/tests/norns_probe.sh" "$REPO/linux/tests/probe_file_dialog.lua" "$DLOG1" > /dev/null 2>&1
        cp "$DH/ui.conf" "$T/dialog-ui.conf" 2> /dev/null
        PATH="$DH/stub:$PATH" NORNS_PICKER=zenity NORNS_HOME="$DH" "$REPO/linux/tests/norns_probe.sh" "$REPO/linux/tests/probe_file_dialog_restart.lua" "$DLOG2" > /dev/null 2>&1
        mark() { sed -n "s/^$1=//p" "$DH/probe.marks" 2> /dev/null | tail -1; }
        # the menu row of the new item (x 300..600, y 338..364) in the three menu pictures
        row() { convert "$DH/$1" -crop 300x26+300+338 +repage -colorspace Gray -depth 8 gray:- | md5sum | cut -d' ' -f1; }
        rest() { convert "$DH/$1" -fill black -draw "rectangle 300,338 600,364" -colorspace Gray -depth 8 gray:- | md5sum | cut -d' ' -f1; }
        dialog_ok() {
            local bad=0
            chk() { eval "$2" > /dev/null 2>&1 || { echo "missing: $1 (marks: $(tr '\n' ' ' < "$DH/probe.marks" 2> /dev/null))"; bad=1; }; }
            chk "the probe ran" 'grep -q "PROBE file dialog done" "$DLOG1" && grep -q "PROBE file dialog restart done" "$DLOG2"'
            chk "default: norns's own browser is up" 'grep -q "PROBE browser up.true" "$DLOG1"'
            chk "default: no system dialog opened" '[ "$(mark default_dialogs)" = 0 ]'
            chk "ticking in the menu saves file_dialog=1" '[ "$(mark saved_on)" = yes ]'
            chk "ticked: one dialog opened" '[ "$(mark ticked_dialogs)" = 1 ]'
            chk "ticked: the file it chose reaches the script" 'grep -q "PROBE fs result.*audio/mac/picked.wav" "$DLOG1"'
            chk "ticked: the browser is closed after the choice" 'grep -q "PROBE browser after dialog.false" "$DLOG1"'
            chk "unticking in the menu saves file_dialog=0" '[ "$(mark saved_off)" = yes ]'
            chk "unticked: no further dialog, without a restart" '[ "$(mark unticked_dialogs)" = 1 ]'
            chk "ui.conf has file_dialog=1 at the end" 'grep -q "^file_dialog=1" "$T/dialog-ui.conf"'
            chk "the menu shows the tick: the item's row differs between off and on" '[ "$(row menu-off.png)" != "$(row menu-on.png)" ]'
            chk "...and nothing else in the picture differs" '[ "$(rest menu-off.png)" = "$(rest menu-on.png)" ]'
            chk "after a restart the menu shows the tick without a click" '[ "$(row menu-restart.png)" = "$(row menu-on.png)" ]'
            chk "after a restart the dialog opens (the setting was loaded)" '[ "$(mark restart_dialogs)" = 2 ]'
            return $bad
        }
        run "window:file dialog only when ticked in the menu (off by default, saved, tick after a restart)" dialog_ok
        rm -rf "$DI"
    }
    dialog_scenario
    # the box styles in the real window (docs/port/box-style-plan.md): the pixel style from box.conf, "Show the page buttons" in the menu (saved, the row gone and not clickable, the page keys
    # still work), Ctrl+M mutes with the row hidden (the MUTE chip shows, the output level goes to -inf and back), the colours tint the aluminium style, and after a restart the look is still there
    box_scenario() {
        BH="$(mktemp -d)"
        ln -s "$REPO" "$BH/norns"
        mkdir -p "$BH/dust/code/probe"
        cp "$REPO/linux/tests/scripts/window_probe.lua" "$BH/dust/code/probe/"
        printf 'style=pixel\npreset=DARK\nbox=2C2E33\nkeys=444853\nencoders=5D6270\nbuttons=3A3D45\nfont=E4E6EA\nshow_buttons=1\n' > "$BH/box.conf"
        BLOG1="$T/box1.log"; BLOG2="$T/box2.log"
        NORNS_HOME="$BH" "$REPO/linux/tests/norns_probe.sh" "$REPO/linux/tests/probe_box.lua" "$BLOG1" > /dev/null 2>&1
        cp "$BH/box.conf" "$T/box-after.conf" 2> /dev/null
        NORNS_HOME="$BH" "$REPO/linux/tests/norns_probe.sh" "$REPO/linux/tests/probe_box_restart.lua" "$BLOG2" > /dev/null 2>&1
        mark() { sed -n "s/^$1=//p" "$BH/probe.marks" 2> /dev/null | tail -1; }
        # the window is centred on Xvfb's 1280 x 800 screen: a layout point (u, v) is the screen pixel (160 + u, 85 + v)
        px() { convert "$BH/$1" -format "%[hex:u.p{$2,$3}]" info:; }
        box_ok() {
            local bad=0
            chk() { eval "$2" > /dev/null 2>&1 || { echo "missing: $1"; bad=1; }; }
            chk "the probe ran" 'grep -q "PROBE box done" "$BLOG1" && grep -q "PROBE box restart done" "$BLOG2"'
            chk "pixel style from box.conf: the box face is the BOX colour" '[ "$(px pix-shown.png 676 300)" = 2C2E33 ]'
            chk "pixel style: a button face is the BUTTONS colour (MIX), the shown row" '[ "$(px pix-shown.png 202 125)" = 3A3D45 ]'
            chk "pixel style: the window is not the aluminium one (the surround is the darker shade of the box)" '[ "$(px pix-shown.png 150 90)" != "" ]'
            chk "the menu item saves show_buttons=0" '[ "$(mark saved_hidden)" = yes ]'
            chk "hidden row: no button pixels where MIX and MUTE were" '[ "$(px pix-hidden.png 202 125)" = 2C2E33 ] && [ "$(px pix-hidden.png 1020 125)" = 2C2E33 ]'
            chk "hidden row: a click where MIX was opens nothing" 'grep -q "PROBE click on the hidden MIX, menu mode.false" "$BLOG1"'
            chk "hidden row: F1 still opens a page" 'grep -q "PROBE F1 with the row hidden, menu mode.true" "$BLOG1"'
            chk "F5 leaves the menu again" 'grep -q "PROBE F5 back, menu mode.false" "$BLOG1"'
            chk "Ctrl+M mutes with the row hidden (the output level is -inf)" 'grep -q "PROBE output level muted.-inf" "$BLOG1"'
            chk "the MUTE chip is drawn while muted although the row is hidden" '[ "$(px pix-muted.png 1020 125)" = E4E6EA ] && [ "$(px pix-muted.png 202 125)" = 2C2E33 ]'
            chk "Ctrl+M again unmutes (the level is back) and the chip goes" 'grep -q "PROBE output level unmuted.0.0" "$BLOG1" && [ "$(px pix-unmuted.png 1020 125)" = 2C2E33 ]'
            chk "the colours tint the aluminium style: a blue box" '[ "$(px alu-blue.png 676 300)" = 678FB9 ]'
            chk "box.conf: aluminium, 3B6EA8, the look is DARK~" 'grep -q "PROBE box.conf.aluminium.3B6EA8.DARK.DARK~" "$BLOG1"'
            chk "box.conf has the style, the colour and the hidden row" 'grep -q "^style=aluminium" "$T/box-after.conf" && grep -q "^box=3B6EA8" "$T/box-after.conf" && grep -q "^show_buttons=0" "$T/box-after.conf"'
            chk "after a restart: the style, the colour and the label are remembered" 'grep -q "PROBE restart.aluminium.3B6EA8.DARK.false" "$BLOG2"'
            chk "after a restart: the blue box is drawn and the row is still hidden" '[ "$(px restart.png 676 300)" = 678FB9 ]'
            return $bad
        }
        run "window:box styles (pixel from box.conf, hide the row from the menu, Ctrl+M with the row hidden, tinted aluminium, remembered after a restart)" box_ok
        rm -rf "$BH"
    }
    box_scenario
    # the detachable screen window (docs/port/detach-plan.md), under Xvfb with no window manager: F9, the menu item and the placeholder, the picture crisp at
    # whole scales and inside a block when in between, the keyboard from the screen window, the shortcuts, F11, F10, close, the saved state, a damaged state file
    detach_scenario() {
        XH="$(mktemp -d)"
        ln -s "$REPO" "$XH/norns"
        mkdir -p "$XH/dust/code/probe" "$XH/stub"
        cp "$REPO/linux/tests/scripts/window_probe.lua" "$XH/dust/code/probe/"
        printf 'brightness=0.8\ncolour=yellow\ncontrast=0.5\n' > "$XH/ui.conf"
        XI="$(mktemp -d -p /var/tmp)"
        echo "RIFF" > "$XI/picked.wav"
        printf '#!/bin/sh\nprintf "%%s\\n" "$@" >> "%s/zenity.args"\necho "%s/picked.wav"\n' "$XH" "$XI" > "$XH/stub/zenity"
        chmod +x "$XH/stub/zenity"
        D1="$T/detach1.log"; D2="$T/detach2.log"; D3="$T/detach3.log"
        probe_run() { PATH="$XH/stub:$PATH" NORNS_PICKER=zenity NORNS_HOME="$XH" "$REPO/linux/tests/norns_probe.sh" "$REPO/linux/tests/$1" "$2" > /dev/null 2>&1; }
        probe_run probe_detach.lua "$D1"
        cp "$XH/probe.marks" "$XH/marks1" 2> /dev/null
        cp "$XH/screen-window.conf" "$XH/conf1" 2> /dev/null
        rm -f "$XH/probe.marks"
        probe_run probe_detach_restart.lua "$D2"
        cp "$XH/probe.marks" "$XH/marks2" 2> /dev/null
        rm -f "$XH/probe.marks"
        printf 'detached=1\nw=abc\nh=oops\n' > "$XH/screen-window.conf"
        probe_run probe_detach_damaged.lua "$D3"
        cp "$XH/probe.marks" "$XH/marks3" 2> /dev/null
        m1() { sed -n "s/^$1=//p" "$XH/marks1" 2> /dev/null | tail -1; }
        m2() { sed -n "s/^$1=//p" "$XH/marks2" 2> /dev/null | tail -1; }
        m3() { sed -n "s/^$1=//p" "$XH/marks3" 2> /dev/null | tail -1; }
        sm() { convert "$1" -filter point -resize 128x64! "$2"; } # the middle of every screen pixel's block
        same() { [ "$(compare -metric AE "$1" "$2" null: 2>&1)" = 0 ]; }
        hexpx() { convert "$1" -format "%[hex:u.p{$2,$3}]" info:; }
        near() { # hex colour, r g b, tolerance
            local h="$1" r g b
            r=$((16#${h:0:2})); g=$((16#${h:2:2})); b=$((16#${h:4:2}))
            [ $((r > $2 ? r - $2 : $2 - r)) -le "$5" ] && [ $((g > $3 ? g - $3 : $3 - g)) -le "$5" ] && [ $((b > $4 ? b - $4 : $4 - b)) -le "$5" ]
        }
        detach_ok() {
            local bad=0 f="$XH"
            chk() { eval "$2" > /dev/null 2>&1 || { echo "missing: $1"; bad=1; }; }
            chk "the probe ran to the end" 'grep -q "PROBE detach done" "$D1"'
            chk "docked at start: no screen window" '[ "$(m1 windows_start)" = 0 ]'
            chk "F9 in the box: one screen window" '[ "$(m1 windows_detached)" = 1 ]'
            chk "the screen window opens at 695 x 367 (5 x, with its black margin) by default" '[[ "$(m1 screen_default)" == 695x367+* ]]'
            # the picture: the same screen pixels as the docked screenshot (look included: yellow)
            sm "$f/shot-docked.png" "$f/s-docked.png"; convert "$f/screen-default.png" -crop 640x320+27+23 +repage "$f/p-default.png" 2> /dev/null; sm "$f/p-default.png" "$f/s-default.png"
            chk "the docked screenshot exists (512 x 256)" '[ "$(identify -format %wx%h "$f/shot-docked.png")" = 512x256 ]'
            chk "the screen window shows the same 128 x 64 pixels as the screenshot, 5 x" 'same "$f/s-docked.png" "$f/s-default.png"'
            chk "the picture sits in a black margin: 27 px at the sides and 23 above and below at 5 x (4.30 and 7.29 percent of the picture)" '[ "$(hexpx "$f/screen-default.png" 26 100)" = 000000 ] && [ "$(hexpx "$f/screen-default.png" 20 100)" = 000000 ] && [ "$(hexpx "$f/screen-default.png" 27 100)" = 000000 ] && [ "$(hexpx "$f/screen-default.png" 150 22)" = 000000 ] && [ "$(hexpx "$f/screen-default.png" 150 23)" = 000000 ]'
            chk "the tint is on in both (yellow: the white rectangle has no blue)" 'h="$(hexpx "$f/s-docked.png" 10 10)"; [ $((16#${h:4:2})) -lt 40 ] && [ $((16#${h:0:2})) -gt 150 ]'
            # the box while detached: the placeholder where the screen was, everything else drawn
            chk "docked box: the script's picture is on the screen" 'near "$(hexpx "$f/box-docked.png" 134 375)" 255 208 0 140'
            chk "detached box: a dark placeholder where the screen was" 'near "$(hexpx "$f/box-detached.png" 134 375)" 22 23 26 14'
            chk "no SCREEN button on the box: the place above the bezel is bare aluminium, docked and detached" 'near "$(hexpx "$f/box-docked.png" 573 293)" 214 216 220 30 && near "$(hexpx "$f/box-detached.png" 573 293)" 214 216 220 30'
            chk "detached box: the buttons and knobs are still there (a light box around)" 'near "$(hexpx "$f/box-detached.png" 800 300)" 204 205 209 40'
            # keyboard and mouse
            chk "2 in the screen window is K2 (down and up)" 'grep -q "PROBE key.2.1" "$D1" && grep -q "PROBE key.2.0" "$D1"'
            chk "no other key or encoder came from the screen window (a click and the wheel are not controls)" '[ "$(grep -c "PROBE key" "$D1")" = 2 ] && [ "$(grep -c "PROBE enc" "$D1")" = 0 ]'
            chk "F6 in the screen window opens the grid" '[ "$(m1 grid_open)" = 1 ]'
            chk "a cell press reaches the script while the screen is detached" '[ "$(grep -c "PROBE gridkey.2.2.1" "$D1")" -ge 1 ]'
            chk "...and again while the screen window is hidden" '[ "$(grep -c "PROBE gridkey.2.2.1" "$D1")" -ge 2 ]'
            chk "the virtual keys window plays a note while the screen window is hidden" 'grep -q "PROBE midi.note_on" "$D1"'
            chk "F6 again closes the grid" '[ "$(m1 grid_closed)" = 0 ]'
            # shortcuts
            chk "Ctrl+Shift+S in the screen window gives the same picture as docked" 'same "$f/shot-docked.png" "$f/shot-detached.png"'
            chk "a GIF recorded while detached is the same as one recorded docked (size, first frame; a still script is one frame)" '[ -s "$f/gif-docked.gif" ] && [ -s "$f/gif-detached.gif" ] && [ "$(identify "$f/gif-docked.gif" | head -1 | cut -d" " -f3)" = "$(identify "$f/gif-detached.gif" | head -1 | cut -d" " -f3)" ] && convert "$f/gif-docked.gif[0]" "$f/gif-d0.png" && convert "$f/gif-detached.gif[0]" "$f/gif-x0.png" && same "$f/gif-d0.png" "$f/gif-x0.png"'
            chk "Ctrl+O in the screen window opens the import dialog" 'grep -q -- "--multiple" "$f/zenity.args"'
            # sizes
            convert "$f/screen-700.png" -crop 644x322+28+39 +repage "$f/p700.png" 2> /dev/null
            chk "in between (700 x 400): inside every block the pixel is the screen's level" 'sm "$f/p700.png" "$f/s-700.png"; same "$f/s-docked.png" "$f/s-700.png"'
            chk "in between: the picture is 644 x 322 in a 700 x 400 window, black all round" '[ "$(hexpx "$f/screen-700.png" 10 5)" = 000000 ] && [ "$(hexpx "$f/screen-700.png" 10 394)" = 000000 ] && [ "$(hexpx "$f/screen-700.png" 28 100)" = 000000 ] && [ "$(hexpx "$f/screen-700.png" 28 150)" = 000000 ]'
            convert "$f/screen-1024.png" -crop 1024x512+44+37 +repage "$f/p1024.png" 2> /dev/null
            sm "$f/p1024.png" "$f/s-1024.png"; convert "$f/s-1024.png" -filter point -resize 1024x512! "$f/b-1024.png"
            chk "8 x (a 1112 x 587 window: the picture 1024 x 512 and its margin): the same pixels" 'same "$f/s-docked.png" "$f/s-1024.png"'
            chk "8 x: every 8 x 8 block is one flat colour (nearest neighbour, nothing blurred)" 'same "$f/p1024.png" "$f/b-1024.png"'
            chk "8 x: the margin is 44 px at the sides (4.30 percent of 1024) and 37 above and below (7.29 percent of 512)" '[ "$(hexpx "$f/screen-1024.png" 75 100)" = 000000 ] && [ "$(hexpx "$f/screen-1024.png" 76 100)" != 000000 ] && [ "$(hexpx "$f/screen-1024.png" 100 68)" = 000000 ] && [ "$(hexpx "$f/screen-1024.png" 100 69)" != 000000 ]'
            # a window as big as the display (what fullscreen draws), and the saved fullscreen state
            convert "$f/screen-big.png" -crop 1152x576+49+42 +repage "$f/pbig.png" 2> /dev/null
            sm "$f/pbig.png" "$f/s-big.png"; convert "$f/s-big.png" -filter point -resize 1152x576! "$f/b-big.png"
            chk "a 1251 x 660 window is 9 x, flat blocks, centred in its margin" 'same "$f/s-docked.png" "$f/s-big.png" && same "$f/pbig.png" "$f/b-big.png" && [ "$(hexpx "$f/screen-big.png" 5 5)" = 000000 ]'
            chk "F11 saves fullscreen=1 and F11 again fullscreen=0, back at the windowed size" '[[ "$(m1 conf_fs_on)" == *fullscreen=1* && "$(m1 conf_fs_off)" == *fullscreen=0* && "$(m1 screen_back)" == 695x367+* ]]'
            # the menu from the screen window
            chk "F10 in the screen window opens the box's menu (dark menu over the box)" 'v="$(convert "$f/box-menu.png" -crop 100x60+256+431 +repage -colorspace Gray -format "%[fx:mean]" info:)"; awk -v v="$v" "BEGIN { exit !(v < 0.2) }"'
            # placeholder, button, close
            chk "a click on the placeholder brings the screen back" '[ "$(m1 windows_after_placeholder)" = 0 ]'
            chk "F9 from the box detaches it again" '[ "$(m1 windows_after_f9)" = 1 ]'
            chk "the menu item 'Screen in its own window' detaches it, F9 from the box brings it back" '[ "$(m1 windows_after_menu)" = 1 ] && [ "$(m1 windows_after_menu_off)" = 0 ]'
            chk "the close button of the screen window re-docks it, norns keeps running" '[ "$(m1 windows_after_close)" = 0 ] && [ "$(m1 alive_after_close)" = yes ]'
            chk "the box's close button quits norns with the screen window open" '[ "$(m1 alive_after_box_close)" = no ]'
            chk "the state was saved at quit: detached, 1024 x 512, framed off (Shift+F11), a place" 'c="$(m1 conf_after_quit)"; [[ "$c" == *detached=1* && "$c" == *w=1024* && "$c" == *h=512* && "$c" == *x=* && "$c" == *y=* && "$c" == *border=0* ]]'
            # restart with that state
            chk "restart: the screen window is there at once" '[ "$(m2 restart_windows)" = 1 ]'
            chk "restart: at the saved size" '[[ "$(m2 restart_geom)" == 1024x512+* ]]'
            chk "restart: the box shows the placeholder" 'near "$(hexpx "$f/restart-box.png" 134 375)" 22 23 26 14'
            chk "restart: F9 brings it back and the state says docked" '[ "$(m2 restart_docked)" = 0 ] && [[ "$(m2 restart_conf)" == *detached=0* ]]'
            # a damaged file
            chk "damaged file: the defaults for the bad values (695 x 367) and detached is read" '[ "$(m3 damaged_windows)" = 1 ] && [[ "$(m3 damaged_geom)" == 695x367+* ]]'
            chk "damaged file: a log line for each bad value" 'grep -q "screen-window.conf: w=.abc" "$D3" && grep -q "screen-window.conf: h=.oops" "$D3"'
            return $bad
        }
        run "window:detached screen (F9, button, placeholder, crisp scales, keys, shortcuts, F11, F10, close, saved state)" detach_ok
        rm -rf "$XI"
    }
    detach_scenario
    # a second start of the launcher while Verdandi runs (docs: the Linux manual): no second norns, no dialog, the window (and the screen window) brought to the front; a start
    # after a crash is not blocked. no window manager here: "to the front" is the stacking order (a magenta window covers the display) and the keyboard focus
    second_start_scenario() {
        SH="$(mktemp -d)"
        ln -s "$REPO" "$SH/norns"
        mkdir -p "$SH/dust/code/probe" "$SH/stub"
        cp "$REPO/linux/tests/scripts/window_probe.lua" "$SH/dust/code/probe/"
        printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/zenity.log"\n' "$SH" > "$SH/stub/zenity"
        chmod +x "$SH/stub/zenity"
        S1="$T/second1.log"; S2="$T/second2.log"
        NORNS_HOME="$SH" "$REPO/linux/tests/norns_probe.sh" "$REPO/linux/tests/probe_second_start.lua" "$S1" > /dev/null 2>&1
        cp "$SH/probe.marks" "$SH/marks1" 2> /dev/null
        rm -f "$SH/probe.marks"
        pkill -9 -x norns 2> /dev/null; pkill -x jackd 2> /dev/null; sleep 1
        # what a crashed norns leaves: a request nobody answered, an old answer
        echo stale > "$SH/.norns-raise"; echo ok > "$SH/.norns-raise.done"
        NORNS_HOME="$SH" "$REPO/linux/tests/norns_probe.sh" "$REPO/linux/tests/probe_second_start_fresh.lua" "$S2" > /dev/null 2>&1
        cp "$SH/probe.marks" "$SH/marks2" 2> /dev/null
        k1() { sed -n "s/^$1=//p" "$SH/marks1" 2> /dev/null | tail -1; }
        k2() { sed -n "s/^$1=//p" "$SH/marks2" 2> /dev/null | tail -1; }
        hexpx() { convert "$1" -format "%[hex:u.p{$2,$3}]" info:; }
        second_ok() {
            local bad=0 f="$SH"
            chk() { eval "$2" > /dev/null 2>&1 || { echo "missing: $1"; bad=1; }; }
            chk "the probe ran to the end" 'grep -q "PROBE second start done" "$S1"'
            chk "(sanity) another window is in front of the box before the second start" '[ "$(hexpx "$f/before-docked.png" 800 400)" = FF00FF ]'
            chk "the second start exits 0 and says the window was brought to the front" '[ "$(k1 docked_rc)" = 0 ] && grep -q "brought to the front" "$f/second-docked.out"'
            chk "no second norns was started" '[ "$(k1 docked_norns)" = 1 ] && [ "$(k1 detached_norns)" = 1 ]'
            chk "no dialog was shown" '[ "$(k1 docked_dialogs)" = 0 ] && [ "$(k1 detached_dialogs)" = 0 ]'
            chk "the box is in front of the other window afterwards (the stacking order changed)" '[ "$(hexpx "$f/after-docked.png" 800 400)" != FF00FF ]'
            chk "the box has the keyboard focus (the other window had it before)" '[ -n "$(k1 main_id)" ] && [ "$(k1 focus_before_docked)" != "$(k1 main_id)" ] && [ "$(k1 focus_after_docked)" = "$(k1 main_id)" ]'
            chk "the launcher left no control file behind" '[ -z "$(k1 files_after_docked)" ]'
            chk "(sanity) with the screen detached, another window covers both before" '[ "$(hexpx "$f/before-detached.png" 50 30)" = FF00FF ] && [ "$(hexpx "$f/before-detached.png" 800 400)" = FF00FF ]'
            chk "detached: the second start worked too" '[ "$(k1 detached_rc)" = 0 ]'
            chk "detached: both the box and the screen window are in front of the other window" '[ "$(hexpx "$f/after-detached.png" 800 400)" != FF00FF ] && [ "$(hexpx "$f/after-detached.png" 50 30)" != FF00FF ]'
            chk "after a crash (kill -9, control files left) a new start boots normally" 'grep -q "PROBE fresh start done" "$S2" && grep -q "PROBE window init" "$S2"'
            chk "...its matron cleared the old request and answer" '[ -z "$(k2 files_after_start)" ]'
            chk "...and a second start still raises it" '[ "$(k2 fresh_second_rc)" = 0 ] && [ "$(k2 fresh_second_norns)" = 1 ]'
            return $bad
        }
        run "window:second start brings Verdandi to the front (no second copy, no dialog, screen window too, start after a crash)" second_ok
    }
    second_start_scenario
    # the screen's look: yellow, brightness 0.4, contrast 0.5 from ui.conf; window, screenshot and gif show the same colours (docs/port/ui-settings-plan.md)
    ui_look_scenario() {
        UH="$(mktemp -d)"
        ln -s "$REPO" "$UH/norns"
        mkdir -p "$UH/dust/code/probe"
        cp "$REPO/linux/tests/scripts/ui_look_probe.lua" "$UH/dust/code/probe/"
        printf 'brightness=0.4\ncolour=yellow\ncontrast=0.5\n' > "$UH/ui.conf"
        NORNS_HOME="$UH" "$REPO/linux/tests/norns_probe.sh" "$REPO/linux/tests/probe_ui_look.lua" "$T/ui-look.log" > /dev/null 2>&1
        # the window is at 144,69 on the screen; the screen (512 x 256) at 74,335 in it (4 px per screen pixel)
        px() { convert "$UH/ui-window.png" -format "%[hex:u.p{$(($1 + 144 + 74)),$(($2 + 69 + 335))}]" info: 2> /dev/null; }
        want() { python3 -I -c "import sys; sys.path.insert(0, '$REPO/docs/port/ui-previews'); import ui_tint as u; print('%02X%02X%02X' % u.mapped($1 * 17, u.parse_hex('FFD000'), 0.4, 0.5))"; }
        ui_look_ok() {
            local bad=0
            chk() { eval "$2" > /dev/null 2>&1 || { echo "missing: $1"; bad=1; }; }
            chk "the probe ran" 'grep -q "PROBE ui_look done" "$T/ui-look.log"'
            chk "window: level 15 is yellow at 0.4 ($(want 15))" '[ "$(px 42 42)" = "$(want 15)" ]'
            chk "window: level 4 ($(want 4))" '[ "$(px 242 42)" = "$(want 4)" ]'
            chk "window: level 1 ($(want 1))" '[ "$(px 402 42)" = "$(want 1)" ]'
            chk "window: black stays black" '[ "$(px 500 42)" = "000000" ]'
            shot="$(ls "$UH"/dust/Verdandi*.png 2> /dev/null | head -1)"
            chk "a screenshot was saved" '[ -n "$shot" ]'
            # the screenshot is the window's screen, pixel for pixel
            convert "$UH/ui-window.png" -crop 512x256+$((144 + 74))+$((69 + 335)) +repage "$UH/win-screen.png"
            chk "the screenshot equals the window's screen pixel for pixel" '[ "$(compare -metric AE "$shot" "$UH/win-screen.png" null: 2>&1)" = 0 ]'
            gif="$(ls "$UH"/dust/Verdandi*.gif 2> /dev/null | head -1)"
            chk "a gif was saved" '[ -n "$gif" ]'
            gs="$(identify -format "%w" "$gif[0]" 2> /dev/null)"
            gscale=$((gs / 128))
            gpx() { convert "$gif[0]" -format "%[hex:u.p{$(($1 * gscale + gscale / 2)),$(($2 * gscale + gscale / 2))}]" info: 2> /dev/null; }
            chk "gif: level 15 as in the window" '[ "$(gpx 10 10)" = "$(want 15)" ]'
            chk "gif: level 4 as in the window" '[ "$(gpx 60 10)" = "$(want 4)" ]'
            chk "gif: level 1 as in the window" '[ "$(gpx 100 10)" = "$(want 1)" ]'
            chk "gif: black stays black" '[ "$(gpx 120 60)" = "000000" ]'
            return $bad
        }
        run "window:the look from ui.conf (yellow, 0.4, contrast 0.5): window, screenshot and gif agree" ui_look_ok
        cp "$UH/ui-window.png" "${SHOT_DIR:-/dev/null}" 2> /dev/null
    }
    ui_look_scenario
    # mods: a mod found in dust/code/*/lib/mod.lua, enabled in dust/data/system.mods, is loaded at start and listed on SYSTEM > MODS; a mod with an error is reported
    mods_scenario() {
        MD="$(mktemp -d)"
        ln -s "$REPO" "$MD/norns"
        mkdir -p "$MD/dust/code/fakemod/lib" "$MD/dust/code/badmod/lib" "$MD/dust/code/notamod/lib" "$MD/dust/data"
        printf 'local mod = require "core/mods"\nprint("FAKEMOD loaded as " .. tostring(mod.this_name))\nmod.hook.register("system_post_startup", "fakemod", function() print("FAKEMOD post_startup hook ran") end)\n' > "$MD/dust/code/fakemod/lib/mod.lua"
        printf 'error("boom in the mod")\n' > "$MD/dust/code/badmod/lib/mod.lua"
        echo "x = 1" > "$MD/dust/code/notamod/lib/other.lua"
        MODS_FILE="$MD/dust/data/system.mods" lua5.3 -e 'package.path = "lua/lib/?.lua;" .. package.path; require("tabutil").save({"fakemod", "badmod"}, os.getenv("MODS_FILE"))'
        NORNS_HOME="$MD" "$REPO/linux/tests/norns_probe.sh" "$REPO/linux/tests/probe_mods.lua" "$T/mods.log" > /dev/null 2>&1
        mods_ok() {
            local bad=0
            chk() { eval "$2" > /dev/null 2>&1 || { echo "missing: $1"; bad=1; }; }
            chk "the probe ran" 'grep -q "PROBE mods done" "$T/mods.log"'
            chk "one line per mod found" 'grep -q "mod found: fakemod" "$T/mods.log" && grep -q "mod found: badmod" "$T/mods.log"'
            chk "a folder without lib/mod.lua is not a mod" '! grep -q "mod found: notamod" "$T/mods.log"'
            chk "fakemod loaded at start" 'grep -q "FAKEMOD loaded as fakemod" "$T/mods.log" && grep -q "PROBE mods loaded fakemod.true" "$T/mods.log"'
            chk "its post_startup hook ran" 'grep -q "FAKEMOD post_startup hook ran" "$T/mods.log"'
            chk "the failing mod is reported with its error, norns went on" 'grep -q "mod failed: badmod" "$T/mods.log" && grep -q "boom in the mod" "$T/mods.log" && grep -q "PROBE mods loaded fakemod.true.badmod.false" "$T/mods.log"'
            chk "SYSTEM > MODS lists both" 'grep -q "PROBE mods page.badmod,fakemod" "$T/mods.log"'
            return $bad
        }
        run "window:mods (found by their lib mod.lua, enabled ones loaded at start, a failing one reported, SYSTEM > MODS lists them)" mods_ok
    }
    mods_scenario
else
    echo "SKIP  window (xdotool and imagemagick not installed)"
fi

# the package in a clean Ubuntu 24.04 root (heavy: debootstrap, apt, a headless boot as a normal user). needs root, debootstrap,
# network and a built .deb (linux/package.sh all). NORNS_PACKAGE_TEST=0 skips, =1 makes a missing .deb a failure
pkg_name="package:clean root install, boot as a normal user, metadata, privacy scan"
if [ "${NORNS_PACKAGE_TEST:-auto}" = 0 ]; then
    echo "SKIP  $pkg_name (NORNS_PACKAGE_TEST=0)"
else
    "$REPO/linux/tests/package_test.sh" > "$T/package.log" 2>&1
    rc=$?
    if [ $rc -eq 0 ]; then echo "PASS  $pkg_name"; grep '^PASS' "$T/package.log" | sed 's/^/        /'
    elif [ $rc -eq 77 ] && [ "${NORNS_PACKAGE_TEST:-auto}" != 1 ]; then echo "$(grep '^SKIP' "$T/package.log" | sed 's/^SKIP package_test:/SKIP  package:clean root test -/')"
    else echo "FAIL  $pkg_name"; grep -E '^(FAIL|SKIP|   )' "$T/package.log" | head -20 | sed 's/^/        /'; FAILED+=("package")
    fi
fi
# opt-in (about 10 minutes): the whole build in a fresh root, started like "sudo linux/package.sh clean-root" by an account that does not
# exist in that root, then the install test on the result. NORNS_CLEAN_ROOT_TEST=1
if [ "${NORNS_CLEAN_ROOT_TEST:-0}" = 1 ]; then
    run "package:clean-root build end to end (as another account), then install test" bash -c '
        id hostbuilder >/dev/null 2>&1 || useradd -m hostbuilder
        SUDO_USER=hostbuilder linux/package.sh clean-root && linux/tests/package_test.sh build/package/clean-root/verdandi_*.deb'
else
    echo "SKIP  package:clean-root build end to end (opt-in, about 10 minutes: NORNS_CLEAN_ROOT_TEST=1)"
fi
echo
echo "known failures: ${#KNOWN[@]}  unexpected failures: ${#FAILED[@]}"
[ ${#FAILED[@]} -eq 0 ]
