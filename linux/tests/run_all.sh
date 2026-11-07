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
run "scan-fkeys:which scripts name F9, F11, F12, and read Ctrl+M or Ctrl+Shift+M (reads only)" linux/tests/scan_fkeys_test.sh
run "launcher:a second start asks the running Verdandi to raise its window; no answer or no window: one sentence; nothing of its data touched; a crash leaves no lock" linux/tests/second_start_test.sh
# needs libmonome with linux/patches/libmonome-pty-serial.patch (linux/setup-deps.sh)
cc $CFLAGS "$M/vgrid_test.c" "$P/vgrid_proto.c" "$P/vgrid_device.c" -L/usr/local/lib -lmonome -lpthread \
    -o "$T/vgt" && LD_LIBRARY_PATH=/usr/local/lib run "c:vgrid" "$T/vgt"
# libmonome's write to a port that is slow to take data: no message cut in the middle (linux/patches/libmonome-write-retry.patch)
cc $CFLAGS -I matron/src/platform/macos -I/usr/local/include linux/tests/monome_write_test.c "$P/vgrid_proto.c" -L/usr/local/lib -lmonome \
    -lpthread -o "$T/mwt" && LD_LIBRARY_PATH=/usr/local/lib run "c:monome_write (a stalled serial port, no half message)" "$T/mwt"
run "grid:LED data reaches the serial port (script, script change clears, prompt commands)" linux/tests/grid_led_test.sh
run "grid:LEDs go off when norns ends (Ctrl+Q, window close, SIGTERM, SIGHUP, a crash; bounded; the crash report names functions)" linux/tests/grid_exit_test.sh
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
# the virtual MIDI card (snd-virmidi) is the bridge a DAW reads: norns must never list or open it as a controller (KNOWN-ISSUES 40). the rules (names, defaults, midi_ignore, the
# alsa_midi_out_to target), the sources scan, and the monitor itself with a fake udev and ALSA (in the replug test below: skipped, said once, released when it was open)
midi_ignore_ok() {
    g++ -std=c++14 -I third-party/doctest -I matron/src linux/tests/midi_ignore_test.cpp -o "$T/midi_ignore_test" || return 1
    "$T/midi_ignore_test"
}
run "midi:ignore rules (the virtual MIDI card by id, driver and name, midi_ignore, the alsa_midi_out_to target; real controllers never matched)" midi_ignore_ok
run "midi:sources scan (the raw port is opened in one place, ALSA cards only behind the ignore rule, the sequencer is output only, no Lua reads the cards)" linux/tests/midi_sources_test.sh
run "midi:VIRMIDI page load with a fake pkexec (running, then loaded by itself; cancelled, no agent, modprobe failed, timeout, no pkexec)" linux/tests/virmidi_pkexec_test.sh
# a USB MIDI device that is unplugged, powered off and comes back (the BeatStep Pro of the owner's laptop, KNOWN-ISSUES 36): the real device monitor, list and read threads with a fake udev and a fake ALSA, lua/core/midi.lua as norns
# runs it: the same node again, a new node, no udev remove, a remove that comes late, a card that is not ready, a busy port, repeated adds, and random plug / unplug sequences (the settled state is checked: list, Lua, vports, handles)
g++ -std=gnu++14 -D_GNU_SOURCE -DNORNS_LINUX_DESKTOP -I matron/src -I matron/src/device -I matron/src/platform/linux -I matron/src/platform/macos \
    $(pkg-config --cflags lua5.3 libevdev alsa 2>/dev/null) -I/usr/include/libevdev-1.0 linux/tests/midi_replug_test.cc matron/src/device/device_list.cc matron/src/device/device.cc matron/src/device/device_midi.cc \
    -Wl,--wrap=access -o "$T/midi_replug_test" $(pkg-config --libs lua5.3 libevdev) -lpthread -ldl 2> "$T/midi_replug_build.log" \
    && run "c:midi unplug and replug (device monitor, list, read threads with a fake udev and ALSA; no remove, late remove, not ready, busy, duplicates, the virtual MIDI card skipped and released; 30 random sequences)" "$T/midi_replug_test" 30 1 \
    || { echo "FAIL  c:midi unplug and replug does not build"; tail -5 "$T/midi_replug_build.log"; FAILED+=("midi replug build"); }
run "linux:crash report (signal, thread name, backtrace in the log and crash-report.txt; the default action and the core dump kept)" linux/tests/crash_report_test.sh
cc $CFLAGS -I "$P" linux/tests/ui_look_test.c "$P/ui_look.c" "$P/gif_writer.c" -o "$T/ulk" -lm 2> "$T/ulk.err" || cat "$T/ulk.err"
python3 docs/port/ui-previews/ui_tint.py dump > "$T/ui-dump.txt"
run "c:ui_look (grey correction, tint, brightness: equal to the Python reference at 89600 values; black stays black, white stays white; the gif palette)" "$T/ulk" "$T/ui-dump.txt"
run "lua:file dialog setting (off by default, ticked, unticked at once, saved, damaged value, result and cancel, macOS unchanged)" lua5.3 linux/tests/file_dialog_setting_test.lua
run "lua:box settings and looks (hex, box.conf, built-in and own looks, files, names, both styles take colours)" lua5.3 linux/tests/box_settings_test.lua
run "lua:text entry (6-digit hex limit and hint, clean redraw, every way of closing hands the page back, double enter, long names; device path unchanged)" env NORNS_PLATFORM=1 lua5.3 linux/tests/textentry_test.lua
run "lua:THEME and SCREEN pages under random keys, the colour picker and the clipboard (every state change is drawn, handlers stay the page's own, selection in range, modal flags, ESC always leaves; handler errors logged)" env NORNS_PLATFORM=linux NORNS_HARDWARE_KEYS=1 lua5.3 linux/tests/menu_stress_test.lua 120 500
run "lua:network page without the iw tool (short message, no error)" env NORNS_PLATFORM=linux lua5.3 linux/tests/wifi_iw_test.lua
run "lua:colour conversion and steps (hex <-> hue, saturation, brightness: round trips for every grey, a million spread and 100k random codes, black and white, the middle #408080, steps, clamping)" lua5.3 linux/tests/colour_test.lua
run "lua:clipboard (copy, the window's answer, valid and refused texts: empty, long, binary, 3 digits, with and without #)" lua5.3 linux/tests/clipboard_test.lua
run "c:clipboard classifier and the real SDL clipboard round trip (valid, empty, 65 characters, binary, 50 MB never walked through)" linux/tests/clip_test.sh
run "lua:renames (SCREEN and THEME in the list, the manual and RUN-ON-LAPTOP.md; ids, aliases and files unchanged; the device list as before)" env NORNS_PLATFORM=linux lua5.3 linux/tests/rename_test.lua
run "lua:SYSTEM > BOX page (rows, hex entry, STYLE, PRESET list and markers, SAVE, overwrite and delete questions, scrolling)" lua5.3 linux/tests/box_page_test.lua
run "box:right-click items, Ctrl+M and the menu size (source checks)" linux/tests/box_menu_test.sh
run "lua:clock params on the desktop (the bare clock_midi_out option of norns up to 2.7.3 next to the toggles clock_midi_out_1..16, kept in sync; the device unchanged)" bash -c "cd '$REPO' && NORNS_PLATFORM=linux lua5.3 linux/tests/clock_midi_out_test.lua && lua5.3 linux/tests/clock_midi_out_test.lua"
run "lua:an error in a script's grid key handler (logged with the traceback, shown on the window, the other handler runs, norns goes on; the device unchanged)" bash -c "cd '$REPO' && NORNS_PLATFORM=linux lua5.3 linux/tests/grid_key_guard_test.lua && lua5.3 linux/tests/grid_key_guard_test.lua"
run "c:midi frame (a script's bytes cut into whole MIDI messages for the JACK output)" bash -c "cc -std=gnu11 -Wall -I '$REPO/matron/src/platform/linux' '$REPO/linux/tests/midi_frame_test.c' -o '$T/midi_frame_test' && '$T/midi_frame_test'"
run "lua:ui settings and the UI page (hex parsing, text entry, save, load, damaged file, SYSTEM list)" env NORNS_PLATFORM=linux NORNS_HARDWARE_KEYS=1 lua5.3 linux/tests/ui_settings_test.lua
run "lua:screen presets" env NORNS_PLATFORM=linux NORNS_HARDWARE_KEYS=1 lua5.3 linux/tests/ui_screen_test.lua
run "lua:ui page with the computer keyboard (one press = one step, release changes nothing, rows, hex entry; real keyboard module and menu bindings)" env NORNS_PLATFORM=linux NORNS_HARDWARE_KEYS=1 lua5.3 linux/tests/ui_keys_test.lua
run "lua:MIDI MAP value functions (absolute steps, baseline, jump 40, pause 1.5 s, the three relative formats value by value, sensitivity and carry, the format suggestion, keys by CC and note, device name matching: mio and its ports, Push 2, iii grid)" lua5.3 linux/tests/midimap_value_test.lua
run "lua:MIDI MAP settings and presets (midimap.conf defaults, round trip, every damaged value, unknown keys kept, preset files, built-in PUSH 2 marked unverified, atomic save)" env NORNS_PLATFORM=linux lua5.3 linux/tests/midimap_settings_test.lua
run "lua:MIDI MAP layer and learn (through the real midi.lua and pmap: device and channel filters, ANY skips the iii grid and the keys window, the params MAP wins a clash, scripts get every message, held keys released, every way out of a learn)" env NORNS_PLATFORM=linux lua5.3 linux/tests/midimap_layer_test.lua
# the width of every row of our own pages at long values, measured with the real font metrics of the norns screen (the menu font, liquid.ttf at 8: cairo,
# linux/tests/font_widths_dump.c), docs/port/KNOWN-ISSUES.md 38. scripts' own drawing is not checked or changed
gcc -o "$T/font_widths_dump" linux/tests/font_widths_dump.c $(pkg-config --cflags --libs cairo freetype2) 2> "$T/fwd.err" || cat "$T/fwd.err"
"$T/font_widths_dump" "$REPO/resources/liquid.ttf" 8 > "$T/font_widths_liquid.txt"
run "lua:page widths (CLEAN UP, DEVICES, SCREEN, THEME, AUDIO, MODS, SYSTEM, RESET, RESTART, TAPE, PICKER: no row wider than the screen or over another at long names, real font metrics)" env FONT_WIDTHS="$T/font_widths_liquid.txt" NORNS_PLATFORM=linux lua5.3 linux/tests/page_width_test.lua
run "lua:MIDI MAP page (rows and wording, views, preset row, device list with the mio, visible learn state, every handler redraws, SYSTEM list below THEME, every row at long values fits the screen)" env FONT_WIDTHS="$T/font_widths_liquid.txt" NORNS_PLATFORM=linux lua5.3 linux/tests/midimap_page_test.lua
run "lua:menu number formats and handler errors (sizes with fractions, an error in a key or encoder handler is logged, shown and the page redrawn on the desktop, left alone on the device)" env NORNS_PLATFORM=linux lua5.3 linux/tests/menu_format_test.lua
run "lua:arc keys through the real keyboard module (16 ticks, Shift 4, repeat, release nothing, inactive in menu or text entry or with a script reading keys, other keys untouched)" env NORNS_PLATFORM=linux NORNS_HARDWARE_KEYS=1 lua5.3 linux/tests/arc_keys_test.lua
SKM=matron/src/platform/macos; LNM=matron/src/platform/linux
cc -std=gnu11 -Wall -Wextra -DNORNS_LINUX_DESKTOP -DHAVE_VARIANT -I $SKM -I $LNM $(pkg-config --cflags cairo freetype2) linux/tests/midimap_hit_test.c $SKM/device_skin.c $LNM/box_style.c $LNM/toast_fit.c $LNM/box_palette.c -o "$T/mmhit" $(pkg-config --libs cairo freetype2) -lm 2> "$T/mmhit.err" || cat "$T/mmhit.err"
run "c:MIDI MAP hit test (K1-K3 and E1-E3 are hit alike in every style and pixel look, row shown or hidden, muted or not, three sizes)" "$T/mmhit"
cc -std=gnu11 -Wall -Wextra -I matron/src/platform/linux linux/tests/extras_layout_test.c matron/src/platform/linux/extras_layout.c -lm -o "$T/xlt" 2> "$T/xlt.err" || cat "$T/xlt.err"
run "c:extras layout (the grid, arc and keys windows go round the norns window, which is never moved or resized; on screen, clear of it and of each other, three screens, no room, an offset display)" "$T/xlt"
cc -std=gnu11 -Wall -Wextra -I matron/src/platform/linux $(pkg-config --cflags sdl2) linux/tests/arc_keys_c_test.c matron/src/platform/linux/arc_keys.c -o "$T/akc" 2> "$T/akc.err" || cat "$T/akc.err"
run "lua:grid and arc removal without a port (a fifth grid, a callback that raises: the device always goes; the owner's grid.lua:205 error)" env NORNS_PLATFORM=linux lua5.3 linux/tests/grid_remove_test.lua
run "lua:script clear and load (two quick loads: the second reaches its engine; a failing step does not stop the clear; mod cleanup hooks once; the 15 s watchdog)" env NORNS_PLATFORM=linux lua5.3 linux/tests/script_clear_test.lua
cc -std=gnu11 -Wall -Wextra -g -O0 -I matron/src/platform/linux linux/tests/crash_symbols_test.c matron/src/platform/linux/crash_symbols.c -o "$T/cst" 2> "$T/cst.err" || cat "$T/cst.err"
cp "$T/cst" "$T/cst_stripped" 2> /dev/null && strip "$T/cst_stripped" 2> /dev/null
cc -std=gnu11 -Wall -Wextra -I matron/src/platform/linux linux/tests/toast_fit_test.c matron/src/platform/linux/toast_fit.c -o "$T/tft" -lm 2> "$T/tft.err" || cat "$T/tft.err"
run "c:toast lines (words whole, long words cut, at most three lines, an ellipsis, UTF-8, proportional fonts, a space smaller than a character)" "$T/tft"
cc -std=gnu11 -Wall -Wextra -DNORNS_LINUX_DESKTOP -I $SKM -I $LNM $(pkg-config --cflags cairo freetype2) linux/tests/toast_width_test.c $SKM/device_skin.c $LNM/box_style.c $LNM/box_palette.c $LNM/toast_fit.c $LNM/screen_toast.c -o "$T/twt" $(pkg-config --libs cairo freetype2) -lm 2> "$T/twt.err" || cat "$T/twt.err"
run "c:no toast leaves its border (31 messages, five styles, both pixel fonts, the screen window at five sizes)" env NORNS_TEST_TTF="$REPO/resources/norns.ttf" "$T/twt"
run "c:crash symbols (our static functions found by address in the program's own file, a stripped copy gives no names and no crash)" bash -c "\"$T/cst\" && \"$T/cst_stripped\" stripped"
run "c:arc keys of the arc window (eight keys and no others, 16 ticks, Shift 4, ramp only if asked, a key up is nothing)" "$T/akc"
cc -std=gnu11 -Wall -Wextra -DNORNS_LINUX_DESKTOP -I $SKM -I $LNM $(pkg-config --cflags cairo freetype2) linux/tests/window_actions_test.c $LNM/window_actions.c -o "$T/wat" 2> "$T/wat.err" || cat "$T/wat.err"
run "c:window actions (the 14 names are lua's, in order; each is a control of the window, fullscreen or screenshot; unknown, empty, wrong-case names find nothing; the messages)" "$T/wat" lua/core/midimap_settings.lua
D="$(mktemp -d)"
run "lua:mods (glob through the virtual home, the page, enable, restart, a failing mod)" env HOME="$D" NORNS_PLATFORM=linux lua5.3 linux/tests/mods_test.lua
run "tidy:flatten dry run (a nested home is reported and nothing is changed; --apply refuses without the typed line)" linux/tests/tidy_flatten_test.sh
run "sc:virtual home in sclang and scsynth (fake engine, control run and fixed run)" linux/tests/sc_virtual_home_test.sh
run "sc:dronecaster (real engine from a clone) finds its drones and makes signal headless" linux/tests/dronecaster_test.sh
run "sc:scan-sc-paths (scripts whose sc files name the virtual home)" linux/tests/scan_sc_paths_test.sh
run "sc:launcher's sclang_conf.yaml (both Linux folders, the switches, an older conf written again with .old kept)" linux/tests/sc_conf_test.sh
run "sc:SynthDef compatibility (mx_malone builds on 3.14, scoped by name, nothing leaks; 3.13.0 and 3.14.1)" linux/tests/sc_synthdef_compat_test.sh
run "sc:the real nb_mxsynths mod in a headless norns on 3.14.1 (mx_malone builds, all 11 voices exist, the mod's files unchanged)" linux/tests/nb_mxsynths_test.sh
run "box:frame time while resizing (dragged drawing under budget; final image equals a cold direct draw; aluminium, tinted, pixel)" linux/tests/box_frame_test.sh
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

# the virtual MIDI device sends through JACK MIDI (the port Verdandi:midi_out): a listening client gets every message a script sends to it (notes, cc, program change, pitch bend, pressure,
# sysex, start / continue / stop, song position, 24 clock ticks 20 ms apart, in order) and nothing else; a note sent while nobody listens is dropped, a client that is not connected gets nothing,
# norns does not mind; the device list says "virtual" (the old name is gone)
if cc -std=gnu11 "$REPO/linux/tests/jack_midi_out_test.c" -o "$T/jack_midi_out_test" $(pkg-config --cflags --libs jack) 2> /dev/null; then
    JH2="$(mktemp -d)"
    ln -s "$REPO" "$JH2/norns"
    OLOG="$T/jackmidiout.log"
    CAP="$T/jack_midi_out_test" NORNS_HOME="$JH2" "$REPO/linux/tests/norns_probe.sh" "$REPO/linux/tests/probe_jackmidi_out.lua" "$OLOG" > /dev/null 2>&1
    jackmidiout_ok() {
        local bad=0 cap="$JH2/probe.marks.cap"
        chk() { grep -aq "$2" "$OLOG" || { echo "missing: $1"; bad=1; }; }
        chk "the virtual device is vport 1" "PROBE virtual vport.1"
        chk "the device list says virtual" "PROBE device.virtual"
        grep -aq "PROBE device.Verdandi JACK in" "$OLOG" && { echo "the old device name Verdandi JACK in is still in the list"; bad=1; }
        chk "the probe finished (norns did not mind the sends without a listener)" "PROBE jackmidi out done"
        grep -aq "jack_midi_out_test: connected" "$cap" || { echo "Verdandi:midi_out does not exist or could not be linked"; bad=1; }
        local want got nclock
        want="$(awk -F'\t' '$1 == "PROBE sent" { print $2 }' "$OLOG" | tr -d '\r')"
        got="$(grep -a '^EV ' "$cap" | awk '{ s = ""; for (i = 3; i <= NF; i++) s = s (i > 3 ? " " : "") $i; if (s != "f8") print s }')"
        [ "$(echo "$want" | wc -l)" -ge 12 ] || { echo "the probe sent fewer messages than it should ($(echo "$want" | wc -l))"; bad=1; }
        [ "$want" = "$got" ] || { echo "what arrived is not what was sent, in order. sent: $(echo $want | tr '\n' '|') arrived: $(echo $got | tr '\n' '|')"; bad=1; }
        nclock="$(grep -ac '^EV [0-9.]* f8$' "$cap")"
        [ "$nclock" = 24 ] || { echo "24 clock ticks expected, got $nclock"; bad=1; }
        # the clock ticks keep their spacing (20 ms): the mean within 2 ms, every gap within 8 ms of it
        grep -a '^EV [0-9.]* f8$' "$cap" | awk '{ t[NR] = $2 } END { n = 0; for (i = 2; i <= NR; i++) { g[n++] = t[i] - t[i-1]; s += g[n-1] } m = s / n; ok = (m > 18 && m < 22); for (i = 0; i < n; i++) if (g[i] < m - 8 || g[i] > m + 8) ok = 0; printf "clock gap mean %.2f ms\n", m > "/dev/stderr"; exit !ok }' 2> "$T/jackmidiout.gaps" || { echo "the clock ticks lost their spacing: $(cat "$T/jackmidiout.gaps")"; bad=1; }
        # nothing is sent at the end: nothing arrived after the last message of the burst plus a margin, and no extra event at all
        [ "$(grep -ac '^EV ' "$cap")" = "$(( $(echo "$want" | wc -l) + 24 ))" ] || { echo "the number of events is not the number sent (an extra or a missing message): $(grep -ac '^EV ' "$cap")"; bad=1; }
        grep -aq "jack_midi_out_test: done" "$cap" || { echo "the capture client did not finish"; bad=1; }
        grep -aq "listening, not connected" "$JH2/probe.marks.nolink" && grep -aq "done 0 events" "$JH2/probe.marks.nolink" || { echo "a client that is not connected must get nothing"; bad=1; }
        return $bad
    }
    run "midi:the virtual MIDI device sends through JACK MIDI (Verdandi:midi_out: notes, cc, program change, pitch bend, pressure, sysex, transport, clock spacing; silence when nothing is sent)" jackmidiout_ok
else
    echo "SKIP  midi:jack midi out (no jack headers)"
fi

# Cheat Codes 2 in the real norns (needs a clone of the script with its nb submodule: CC2_DIR, or the network): a pattern recording ends without "invalid paramset index: clock_midi_out",
# the script's own reads and sets of the bare clock_midi_out work, an error in a grid key handler is on the window. skipped when the script cannot be had
CCLOG="$T/cc2clock.log"
"$REPO/linux/tests/cc2_clock_test.sh" "$CCLOG" > /dev/null 2>&1
if [ $? -eq 2 ]; then
    echo "SKIP  script:Cheat Codes 2 ends a pattern recording (no clone: set CC2_DIR or allow github.com)"
else
    cc2_ok() {
        local bad=0
        chk() { grep -aq "$2" "$CCLOG" || { echo "missing: $1"; bad=1; }; }
        chk "the script loaded" "PROBE cc2 loaded.true.true"
        chk "the recording ended without an error (the handler of the grid pattern key)" "PROBE handler.true"
        grep -aq "invalid paramset index" "$CCLOG" && { echo "invalid paramset index in the log"; bad=1; }
        chk "the redraw of the grid works afterwards" "PROBE redraw after.true"
        chk "the script's read of the bare id" "PROBE bare reads.3"
        chk "the script's set of the bare id switched the slot off" "PROBE slot 2 after.0.1"
        chk "a grid key error is not fatal" "PROBE grid key.true"
        chk "and is on the window" "PROBE note.ERROR grid key.*boom in a grid key"
        return $bad
    }
    run "script:Cheat Codes 2 ends a pattern recording (clock_midi_out compatible), a grid key error shows" cc2_ok
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
dedupe_unit_ok() {
    g++ -std=c++14 -I third-party/doctest -I matron/src linux/tests/device_dedupe_test.cpp -o "$T/device_dedupe_test" || return 1
    "$T/device_dedupe_test"
}
run "devices:only a udev add is a new device, a node already listed is not added again (the same grid twice)" dedupe_unit_ok
run "lua:SYSTEM > DEVICES with serialosc (a SERIALOSC entry while the note is on, the guide in short lines, a question before it stops anything, a refusal shows the command)" env NORNS_PLATFORM=linux lua5.3 linux/tests/devices_serialosc_test.lua
mkdir -p "$T/stubsc"
printf '#!/bin/sh\necho "$@" >> "$STUB_LOG"\n[ "$STUB_RC" = 0 ] && exit 0 || exit 1\n' > "$T/stubsc/systemctl"
chmod +x "$T/stubsc/systemctl"
run "lua:stopping serialosc without a terminal (systemctl --no-ask-password stop, a stub: success and refusal)" bash -c "STUB_RC=0 STUB_LOG=$T/stub1.log PATH=$T/stubsc:\$PATH NORNS_PLATFORM=linux lua5.3 linux/tests/serialosc_stop_test.lua yes && STUB_RC=1 STUB_LOG=$T/stub2.log PATH=$T/stubsc:\$PATH NORNS_PLATFORM=linux lua5.3 linux/tests/serialosc_stop_test.lua no"
if command -v jackd > /dev/null; then
    SLOG="$T/serialosc.log"
    "$REPO/linux/tests/serialosc_test.sh" "$SLOG" > /dev/null 2>&1
    serialosc_ok() {
        local bad=0
        grep -aq "PROBE check without a device process.GRID: serialosc has this grid" "$SLOG" || { echo "serialoscd and the detector with a grid that norns has open were not reported"; bad=1; }
        grep -aq "PROBE note 1.nil" "$SLOG" || { echo "a note without a grid and without serialosc"; bad=1; }
        grep -aq "PROBE text 2.*serialosc has this grid" "$SLOG" || { echo "the conflict was not found: $(grep -a 'PROBE text 2' "$SLOG")"; bad=1; }
        grep -aq "PROBE note 2.*serialosc has this grid" "$SLOG" || { echo "no note on the device window: $(grep -a 'PROBE note 2' "$SLOG")"; bad=1; }
        [ "$(grep -ac "serialosc: .*sudo systemctl stop serialosc.service" "$SLOG")" = 1 ] || { echo "the log line must appear exactly once, found $(grep -ac "serialosc: .*sudo systemctl stop serialosc.service" "$SLOG")"; bad=1; }
        grep -aq "sudo systemctl start serialosc.service" "$SLOG" || { echo "the log line lacks the start command"; bad=1; }
        grep -aq "PROBE note 3.GRID: serialosc has this grid" "$SLOG" || { echo "the note went when only serialosc-device ended (serialoscd still runs)"; bad=1; }
        grep -aq "PROBE text 4.nil" "$SLOG" || { echo "the note is still reported after serialosc ended"; bad=1; }
        grep -aq "PROBE note 4.nil" "$SLOG" || { echo "the note stayed after serialosc was gone"; bad=1; }
        return $bad
    }
    run "serialosc:fake serialosc-device on the grid: one log line, a note, gone when it goes" serialosc_ok
    SLOG2="$T/serialosc-off.log"
    "$REPO/linux/tests/serialosc_test.sh" "$SLOG2" disabled > /dev/null 2>&1
    serialosc_off_ok() {
        grep -aq "PROBE note 2.nil" "$SLOG2" && ! grep -aq "sudo systemctl stop serialosc.service" "$SLOG2" || { echo "reported although NORNS_SERIALOSC_CHECK=0"; return 1; }
    }
    run "serialosc:NORNS_SERIALOSC_CHECK=0 turns the check off" serialosc_off_ok
    SLOG3="$T/serialosc-unopened.log"
    "$REPO/linux/tests/serialosc_test.sh" "$SLOG3" unopened > /dev/null 2>&1
    serialosc_unopened_ok() {
        local bad=0
        grep -aq "PROBE note 0.nil" "$SLOG3" || { echo "a note before serialosc ran"; bad=1; }
        grep -aq "PROBE note serialosc without a grid.nil" "$SLOG3" || { echo "a note for serialosc without any grid"; bad=1; }
        grep -aq "PROBE note 1.GRID: serialosc has this grid" "$SLOG3" || { echo "no note for serialosc-device processes that norns never opened: $(grep -a 'PROBE note 1' "$SLOG3")"; bad=1; }
        grep -aq "Stop it: sudo systemctl stop serialosc.service" "$SLOG3" || { echo "the note has no guide"; bad=1; }
        grep -aq "PROBE note 2.nil" "$SLOG3" || { echo "the note stayed after the serialosc-device processes ended (serialoscd and the detector still run, no grid is plugged in): $(grep -a -A1 'PROBE note 2' "$SLOG3")"; bad=1; }
        grep -aq "PROBE note 3.GRID: serialosc has this grid" "$SLOG3" || { echo "no note from the active unit and a plugged-in grid: $(grep -a 'PROBE note 3' "$SLOG3")"; bad=1; }
        grep -aq "PROBE note 4.nil" "$SLOG3" || { echo "the note stayed after the unit stopped"; bad=1; }
        [ "$(grep -ac "serialosc: .*sudo systemctl stop serialosc.service" "$SLOG3")" -le 2 ] || { echo "more than one log line per episode"; bad=1; }
        return $bad
    }
    run "serialosc:serialosc holds grids that norns never opened: the note shows, from the processes and from the unit, and goes by itself" serialosc_unopened_ok
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
# mi-UGens (docs/port/mi-ugens.md): the seed script, the stamp, the detection the catalog scripts use, the class check on real sclang logs, the info
run "mi-UGens:seed, stamp, update, left-alone cases, catalog detection" linux/tests/mi_seed_test.sh
run "mi-UGens:info from the stamp (CLEAN UP and manual)" env NORNS_PLATFORM=linux lua5.3 linux/tests/mi_info_test.lua
run "mi-UGens:missing-class and duplicate-class check on real sclang logs" env NORNS_PLATFORM=linux lua5.3 linux/tests/sc_class_check_test.lua
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

if command -v jackd > /dev/null; then
    CLOG="$T/class-note.log"
    "$REPO/linux/tests/class_note_test.sh" "$CLOG" > /dev/null 2>&1
    class_note_ok() {
        local bad=0
        grep -aq "PROBE class note 0.nil" "$CLOG" || { echo "a note before any finding"; bad=1; }
        grep -aq "PROBE class note 1.SUPERCOLLIDER: class problem, see SYSTEM > CLEAN UP" "$CLOG" || { echo "no note on the device window"; bad=1; }
        [ "$(grep -ac "^SuperCollider found classes twice (MiBeads" "$CLOG")" = 1 ] || { echo "the log line must appear exactly once"; bad=1; }
        grep -aq "PROBE class note 2.nil" "$CLOG" || { echo "the note stayed after a clean log"; bad=1; }
        return $bad
    }
    run "mi-UGens:class check note on the device window appears for a duplicate class and clears with a clean log" class_note_ok
fi
# self-healing for a foreign Raspberry Pi mi-UGens pack (docs/port/mi-ugens.md, KNOWN-ISSUES 37): the scanner on fake extension folders, the launcher step
# (moved aside only with the own pack intact, manifest, note, restore, idempotent, off), the note and the CLEAN UP line for a download while norns runs
mi_foreign_ok() {
    g++ -std=c++14 -I third-party/doctest -I matron/src -I matron/src/platform/linux linux/tests/mi_foreign_test.cpp matron/src/platform/linux/mi_foreign_note.cc -o "$T/mi_foreign_test" || return 1
    "$T/mi_foreign_test"
}
run "mi-UGens:foreign Raspberry Pi pack scanner (folder or files, Mi classes, the dust code folder, x86-64 copy, baseline for a download while norns runs)" mi_foreign_ok
run "mi-UGens:heal at start (own pack intact: moved aside with a manifest line and a note; missing or changed: nothing; x86-64 copy; off; restore; idempotent)" linux/tests/mi_heal_test.sh
if command -v jackd > /dev/null; then
    MHPACK="${NORNS_MI_TEST_PACK:-$REPO/build/package/cache/mi-ugens-pack/mi-UGens}"
    if [ -f "$MHPACK/.verdandi-stamp" ] && [ -x "$REPO/build/linux/mi_heal" ]; then
        MHLOG="$T/mi-heal-boot.log"
        "$REPO/linux/tests/mi_heal_boot_test.sh" "$MHLOG" > /dev/null 2>&1
        mi_heal_boot_ok() {
            local bad=0 l
            for l in "PROBE start note.A script downloaded Raspberry Pi mi-UGens. Moved aside; Verdandi's own copy is in use." "PROBE start note file gone.true" "PROBE start moved.true" \
                "PROBE start runtime note.nil" "PROBE runtime note.A script downloaded Raspberry Pi mi-UGens. SYSTEM > CLEAN UP moves them aside, then restart norns." \
                "PROBE runtime still there.true" "PROBE cleanup row.true" "PROBE not moved before the confirmation.true" "PROBE moved after the confirmation.true" \
                "PROBE runtime note after.nil" "PROBE sclang errors: 0"; do
                grep -aq "$l" "$MHLOG" || { echo "missing: $l"; bad=1; }
            done
            [ "$(grep -ac "^norns.sh: mi-UGens: moved 1 foreign" "$MHLOG")" = 1 ] || { echo "the launcher line must appear exactly once"; bad=1; }
            [ "$(grep -ac "^mi-UGens: A script downloaded Raspberry Pi mi-UGens. Moved aside" "$MHLOG")" = 1 ] || { echo "the note is logged once"; bad=1; }
            return $bad
        }
        run "mi-UGens:headless boot with a Raspberry Pi download next to the own pack: moved before sclang, note once, a later download noticed and moved after the CLEAN UP confirmation" mi_heal_boot_ok
    else
        echo "SKIP  mi-UGens:heal boot (needs build/package/cache/mi-ugens-pack from 'linux/package.sh mi' and build/linux/mi_heal from linux/build.sh)"
    fi
fi
# a headless boot with the Emplaitress mod enabled and the shipped pack: seeded, found, no download. needs the built pack (linux/package.sh mi) and a clone of
# the mod (NORNS_EMPLAITRESS=<dir>); skipped otherwise. the second boot turns the seeding off and must see the download (the check that this can fail)
if command -v jackd > /dev/null; then
    MPACK="${NORNS_MI_TEST_PACK:-$REPO/build/package/cache/mi-ugens-pack/mi-UGens}"
    if [ -f "$MPACK/.verdandi-stamp" ] && [ -f "${NORNS_EMPLAITRESS:-/nonexistent}/lib/mod.lua" ]; then
        MLOG="$T/mi-boot.log"; MLOG2="$T/mi-boot-off.log"
        "$REPO/linux/tests/mi_boot_test.sh" "$MLOG" > /dev/null 2>&1
        "$REPO/linux/tests/mi_boot_test.sh" "$MLOG2" off > /dev/null 2>&1
        mi_boot_ok() {
            local bad=0
            grep -aq "^norns.sh: mi-UGens: seeded " "$MLOG" || { echo "the pack was not seeded"; bad=1; }
            grep -aq "emplaitress found mi ugens" "$MLOG" || { echo "the Emplaitress mod did not find the pack"; bad=1; }
            grep -aq "installing mi-UGens" "$MLOG" && { echo "the mod tried to install the pack"; bad=1; }
            grep -aq "^PROBE downloads: none" "$MLOG" || { echo "something was downloaded: $(grep -a 'PROBE downloads' "$MLOG")"; bad=1; }
            grep -aq "^PROBE sclang: 0$" "$MLOG" || { echo "sclang.log has a class or ELF error"; bad=1; }
            grep -aq "installing mi-UGens" "$MLOG2" && ! grep -aq "^PROBE downloads: none" "$MLOG2" || { echo "with the seeding off the mod must try to download (the harness cannot see downloads)"; bad=1; }
            return $bad
        }
        run "mi-UGens:Emplaitress enabled in a headless boot finds the shipped pack, no download happens" mi_boot_ok
    else
        echo "SKIP  mi-UGens:Emplaitress headless boot (needs build/package/cache/mi-ugens-pack from 'linux/package.sh mi' and NORNS_EMPLAITRESS=<clone of the mod>)"
    fi
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
        # (conf: the cut is only visible until the 2 s timer repairs it; on a loaded machine the snapshot can come after the repair: the scenario is run again, at most twice, when the cut was not seen)
        if [ $sc = conf ]; then
            for _retry in 1 2; do
                peers "$GLOG.cut" Verdandi:midi_in | grep -qx "Fake DAW:out" || break
                MIDI_SCENARIO=$sc "$REPO/linux/tests/midi_autoconnect_test.sh" "$GLOG" > /dev/null 2>&1
            done
        fi
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

# the virtual MIDI device as an ALSA sequencer port (client "Verdandi", port "Verdandi out"): the sequencer output logic with a fake sequencer (always), the real client without a kernel sequencer (says no, no crash) and,
# where /dev/snd/seq exists (a laptop: not the CI containers), an aseqdump-style receiver that gets what a script sends, in order, and nothing when nothing is sent (KNOWN-ISSUES: the feature needs the owner's check)
run "c:alsa sequencer output (bytes to events, order, bounded, drops counted and said every 10 s, a full or failing sequencer, the worker)" bash -c "cd '$REPO' && g++ -std=c++14 -I third-party/doctest -I third-party/readerwriterqueue -I matron/src/platform/linux linux/tests/aseq_pump_test.cpp -o '$T/aseq_pump_test' -lasound -lpthread && '$T/aseq_pump_test'"
run "c:alsa sequencer auto-connect (alsa_midi_out_to: prefixes, never itself or controllers, a port that appears later, a cut link, -EBUSY, errors said once; fake sequencer)" bash -c "cd '$REPO' && g++ -std=c++14 -I third-party/doctest -I crone/src -I matron/src/platform/linux linux/tests/aseq_link_test.cpp -o '$T/aseq_link_test' && '$T/aseq_link_test'"
run "lua:virmidi (the setting, snd-virmidi loaded or not, the notes, the Reaper entry, the load without a terminal: pkexec, never sudo, the command to type)" lua5.3 linux/tests/virmidi_test.lua
run "lua:SYSTEM > DEVICES > VIRMIDI (the entry only while the setting is on, the guide, the question, loading, failed, loaded, the Reaper entry, keep after a reboot)" env NORNS_PLATFORM=linux lua5.3 linux/tests/devices_virmidi_test.lua
run "package:virmidi examples (opt-in files only, nothing written to etc, nothing loaded by the package, named in the manual)" linux/tests/virmidi_files_test.sh
run "c:alsa sequencer client (off by NORNS_ALSA_MIDI=0, without a kernel sequencer, with one)" bash -c "cd '$REPO' && g++ -std=c++14 -I third-party/doctest -I third-party/readerwriterqueue -I crone/src -I matron/src -I matron/src/platform/linux linux/tests/aseq_out_test.cpp matron/src/platform/linux/aseq_out.cc -o '$T/aseq_out_test' -lasound -lpthread && '$T/aseq_out_test'"
if [ -e /dev/snd/seq ] && cc -std=gnu11 "$REPO/linux/tests/aseq_dump_test.c" -o "$T/aseq_dump_test" -lasound 2> /dev/null; then
    JH3="$(mktemp -d)"
    ln -s "$REPO" "$JH3/norns"
    ALOG="$T/aseqout.log"
    ASEQ="$T/aseq_dump_test" NORNS_HOME="$JH3" "$REPO/linux/tests/norns_probe.sh" "$REPO/linux/tests/probe_aseq_out.lua" "$ALOG" > /dev/null 2>&1
    aseqout_ok() {
        local bad=0 cap="$JH3/probe.marks.cap"
        grep -aq "PROBE jackmidi out done" "$ALOG" || { echo "the probe did not finish (norns did not mind the sends)"; bad=1; }
        grep -aq "aseq_dump_test: subscribed" "$cap" || { echo "the client Verdandi with the port Verdandi out was not found or could not be subscribed"; bad=1; }
        local want got nclock
        want="$(awk -F'\t' '$1 == "PROBE sent" { print $2 }' "$ALOG" | tr -d '\r')"
        got="$(grep -a '^EV ' "$cap" | awk '{ s = ""; for (i = 3; i <= NF; i++) s = s (i > 3 ? " " : "") $i; if (s != "f8") print s }')"
        [ "$want" = "$got" ] || { echo "what arrived is not what was sent, in order. sent: $(echo $want | tr '\n' '|') arrived: $(echo $got | tr '\n' '|')"; bad=1; }
        nclock="$(grep -ac '^EV [0-9.]* f8$' "$cap")"
        [ "$nclock" = 24 ] || { echo "24 clock ticks expected, got $nclock"; bad=1; }
        [ "$(grep -ac '^EV ' "$cap")" = "$(( $(echo "$want" | wc -l) + 24 ))" ] || { echo "the number of events is not the number sent"; bad=1; }
        grep -aq "listening, not subscribed" "$JH3/probe.marks.nolink" && grep -aq "done 0 events" "$JH3/probe.marks.nolink" || { echo "a listener that is not subscribed must get nothing"; bad=1; }
        return $bad
    }
    run "midi:the virtual MIDI device sends to the ALSA sequencer port Verdandi out (notes, cc, clock, start/stop, sysex in order, silence when nothing is sent)" aseqout_ok
else
    echo "SKIP  midi:alsa sequencer output end to end (no /dev/snd/seq here: the owner's check is in HARDWARE-CHECKLIST.md)"
fi

# the JACK MIDI output under stress, on PipeWire's JACK layer (pw-jack, a private PipeWire without a sound card) and on jackd: dense notes, 2000-tick clock bursts, sysex of 100 to 20000 bytes, garbage, four senders,
# a client that connects, listens, disconnects and closes all the time. before the fix this was a SIGSEGV in PipeWire's libjack (the crash report of the installed package, KNOWN-ISSUES 35)
if command -v pw-jack > /dev/null && command -v pipewire > /dev/null && command -v jackd > /dev/null &&
    c++ -g -std=c++14 -I "$REPO/matron/src" -I "$REPO/matron/src/platform/linux" -I "$REPO/matron/src/device" -I "$REPO/third-party/readerwriterqueue" $(pkg-config --cflags libevdev libudev alsa lua5.3) \
        "$REPO/linux/tests/jack_midi_out_stress.cc" -o "$T/jack_midi_out_stress" $(pkg-config --cflags --libs jack lua5.3) -lpthread 2> "$T/stress-build.log"; then
    PWRT="$(mktemp -d)"
    chmod 700 "$PWRT"
    XDG_RUNTIME_DIR="$PWRT" pipewire > "$T/stress-pipewire.log" 2>&1 &
    PW_PID=$!
    sleep 2
    run "midi:the JACK MIDI output under stress on PipeWire's JACK layer (bursts, long sysex, a client connecting and disconnecting; no crash, no hang)" env XDG_RUNTIME_DIR="$PWRT" timeout 120 pw-jack "$T/jack_midi_out_stress" 8
    kill "$PW_PID" 2> /dev/null
    wait "$PW_PID" 2> /dev/null
    rm -rf "$PWRT"
    pkill -x jackd 2> /dev/null
    jackd -r -d dummy -r 48000 -p 1024 -C 0 -P 0 < /dev/null > "$T/stress-jackd.log" 2>&1 &
    JK_PID=$!
    for _ in $(seq 50); do jack_lsp > /dev/null 2>&1 && break; sleep 0.2; done
    run "midi:the JACK MIDI output under stress on jackd" timeout 120 "$T/jack_midi_out_stress" 8
    kill "$JK_PID" 2> /dev/null
    wait "$JK_PID" 2> /dev/null
else
    echo "SKIP  midi:jack midi out stress (no pipewire, pw-jack or jackd, or it does not build)"
fi

# the optional output auto-connect (midi_out_to= in audio.conf, or NORNS_MIDI_OUT_TO): Verdandi:midi_out is linked to the MIDI inputs that match a prefix, a link cut behind norns' back is made again,
# a client that appears later is linked, an input that does not match is not
if command -v jackd > /dev/null && [ -x "$T/jack_midi_out_test" ]; then
    for sc in conf env; do
        OGLOG="$T/midioutlink-$sc.log"
        MIDI_SCENARIO=$sc CAP="$T/jack_midi_out_test" "$REPO/linux/tests/midi_out_link_test.sh" "$OGLOG" > /dev/null 2>&1
        if [ $sc = conf ]; then
            for _retry in 1 2; do
                peers "$OGLOG.cut" Verdandi:midi_out | grep -qx "Fake Synth:in" || break
                MIDI_SCENARIO=$sc CAP="$T/jack_midi_out_test" "$REPO/linux/tests/midi_out_link_test.sh" "$OGLOG" > /dev/null 2>&1
            done
        fi
        midioutlink_ok() {
            local bad=0
            has() { peers "$OGLOG.$1" Verdandi:midi_out | grep -qx "$2"; }
            has start "Fake Synth:in" || { echo "start: Fake Synth:in is not linked"; bad=1; }
            has start "Other Synth:in" && { echo "start: Other Synth:in is linked, it does not match"; bad=1; }
            [ $sc = conf ] && has cut "Fake Synth:in" && { echo "the test did not cut the link"; bad=1; }
            has repaired "Fake Synth:in" || { echo "the cut link was not made again within 4 s"; bad=1; }
            has late "Late Synth:in" || { echo "a client that appeared later was not linked"; bad=1; }
            has late "Other Synth:in" && { echo "late: Other Synth:in is linked"; bad=1; }
            grep -aq "midi: connected Verdandi:midi_out to Fake Synth:in" "$OGLOG" || { echo "no log line for the first link"; bad=1; }
            return $bad
        }
        run "midi:auto-connect from Verdandi:midi_out, repaired when cut ($sc)" midioutlink_ok
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
        chk "click on the grid window: down" "PROBE gridkey.[0-9]*.[0-9]*.1" # which cell is hit at a fixed pixel depends on the size of the grid window, which now fits the screen round the norns window instead of the old centred layout
        chk "click on the grid window: up" "PROBE gridkey.[0-9]*.[0-9]*.0"
        chk "arc wheel" "PROBE arcdelta.1.2"
        chk "arc key down" "PROBE arckey.1.1"
        chk "arc key up" "PROBE arckey.1.0"
        chk "keys window is a norns MIDI device (after the JACK MIDI input)" "PROBE midi device.virtual.Verdandi keys"
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
        # the menu row of the new item (x 300..600, y 225..251) in the three menu pictures
        row() { convert "$DH/$1" -crop 300x26+300+199 +repage -colorspace Gray -depth 8 gray:- | md5sum | cut -d' ' -f1; }
        rest() { convert "$DH/$1" -fill black -draw "rectangle 300,199 600,225" -colorspace Gray -depth 8 gray:- | md5sum | cut -d' ' -f1; }
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
    # the colour picker in the real window (docs/port/colour-picker-plan.md): K3 on a colour row opens it, the box changes live while it is open and no file is written, K2 gives the colour back, K3 keeps it once
    picker_scenario() {
        PH="$(mktemp -d)"
        ln -s "$REPO" "$PH/norns"
        mkdir -p "$PH/dust/code/probe"
        cp "$REPO/linux/tests/scripts/window_probe.lua" "$PH/dust/code/probe/"
        printf 'style=pixel\npreset=DARK\nbox=2C2E33\nkeys=444853\nencoders=5D6270\nbuttons=3A3D45\nfont=E4E6EA\nshow_buttons=1\n' > "$PH/box.conf"
        PLOG="$T/picker.log"
        NORNS_HOME="$PH" "$REPO/linux/tests/norns_probe.sh" "$REPO/linux/tests/probe_picker.lua" "$PLOG" > /dev/null 2>&1
        pmark() { sed -n "s/^$1=//p" "$PH/probe.marks" 2> /dev/null | tail -1; }
        ppx() { convert "$PH/$1" -format "%[hex:u.p{$2,$3}]" info:; }
        picker_ok() {
            local bad=0
            chk() { eval "$2" > /dev/null 2>&1 || { echo "missing: $1"; bad=1; }; }
            local live kept
            live="$(sed -n 's/^PROBE picker live[[:space:]]//p' "$PLOG" | tail -1)"
            kept="$(sed -n 's/^PROBE picker keep[[:space:]]//p' "$PLOG" | tail -1)"
            chk "the probe ran" 'grep -q "PROBE picker kept" "$PLOG"'
            chk "K3 on the KEYS row opens the picker" 'grep -q "PROBE picker open.true.PICKER" "$PLOG"'
            chk "the key (K1, layout 100 188) is the KEYS colour before" '[ "$(ppx pk-before.png 260 273)" = 444853 ]'
            chk "opening the picker changes nothing: the key is still 444853 and no file was written" '[ "$(ppx pk-open.png 260 273)" = 444853 ] && [ "$(pmark conf_same_open)" = yes ]'
            chk "live: the key is drawn with the picked colour ($live) while the picker is open" '[ -n "$live" ] && [ "$(ppx pk-live.png 260 273)" = "$live" ] && [ "$live" != 444853 ]'
            chk "live: box.conf is not written" '[ "$(pmark conf_same_live)" = yes ]'
            chk "K2: the picker is closed, the page is back, the stored colour is the old one" 'grep -q "PROBE picker cancelled.false.BOX.444853" "$PLOG"'
            chk "K2: the key shows the old colour again and no file was written" '[ "$(ppx pk-cancel.png 260 273)" = 444853 ] && [ "$(pmark conf_same_cancel)" = yes ]'
            chk "K3: the page is back and the colour is stored" 'grep -q "PROBE picker kept.BOX.$kept" "$PLOG" && [ -n "$kept" ]'
            chk "K3: the key shows it and box.conf has it" '[ "$(ppx pk-kept.png 260 273)" = "$kept" ] && grep -q "^keys=$kept" "$PH/box.conf"'
            return $bad
        }
        run "window:colour picker (opens from a colour row, the box changes live without a file, K2 gives it back, K3 keeps it once)" picker_ok
        mkdir -p "${SHOT_DIR:-/dev/null}" 2> /dev/null
        cp "$PH/pk-live.png" "${SHOT_DIR:-/dev/null}/picker-live.png" 2> /dev/null
        cp "$PH/pk-live.png" "$T/picker-live-full.png" 2> /dev/null
        rm -rf "$PH"
    }
    picker_scenario
    # MIDI MAP in the real window (docs/port/midi-map-plan.md): a pick is armed from the page, a click on E2 picks it (and does not turn it), a controller playing into Verdandi:midi_in through JACK MIDI is learned,
    # then it drives E2 for the script, which also receives every message, and a CC key presses K2
    midimap_scenario() {
        if ! cc -std=gnu11 "$REPO/linux/tests/midimap_send.c" -o "$T/midimap_send" $(pkg-config --cflags --libs jack) 2> /dev/null; then
            echo "SKIP  window:MIDI MAP (the JACK sender did not build)"
            return
        fi
        MH="$(mktemp -d)"
        ln -s "$REPO" "$MH/norns"
        mkdir -p "$MH/dust/code/probe"
        cp "$REPO/linux/tests/scripts/window_probe.lua" "$MH/dust/code/probe/"
        printf 'style=pixel\npreset=DARK\nbox=2C2E33\nkeys=444853\nencoders=5D6270\nbuttons=3A3D45\nfont=E4E6EA\nshow_buttons=1\n' > "$MH/box.conf"
        MLOG="$T/midimap.log"
        MMS="$T/midimap_send" NORNS_HOME="$MH" "$REPO/linux/tests/norns_probe.sh" "$REPO/linux/tests/probe_midimap.lua" "$MLOG" > /dev/null 2>&1
        mmpx() { convert "$MH/$1" -format "%[hex:u.p{$2,$3}]" info:; }
        midimap_ok() {
            local bad=0
            chk() { eval "$2" > /dev/null 2>&1 || { echo "missing: $1"; bad=1; }; }
            chk "the probe ran" 'grep -q "PROBE midimap done" "$MLOG"'
            chk "K3 on LEARN arms a pick" 'grep -q "PROBE learn state.pick" "$MLOG"'
            chk "a click on E2 in the window picks it (LISTEN, target e2) and does not turn it" 'grep -q "PROBE picked.listen.e2" "$MLOG" && ! grep -q "PROBE enc.2" <(sed -n "1,/PROBE picked/p" "$MLOG")'
            chk "the controller playing through JACK MIDI is learned: CC 71, two's complement, ANY device" 'grep -q "PROBE learned.idle.cc.71.rel2c.ANY" "$MLOG"'
            chk "the script received every message while it was learned and mapped" '[ "$(grep -c "PROBE script.cc.71" "$MLOG")" -ge 9 ] && grep -q "PROBE script.cc.9.5" "$MLOG"'
            chk "a mapped CC turns E2 for the script (E2 up)" 'grep -q "PROBE enc.2.1" "$MLOG"'
            chk "an unmapped CC (9) did nothing to the encoders" '! grep -q "PROBE enc.[13]" "$MLOG"'
            chk "a CC key presses and releases K2 for the script" 'grep -q "PROBE key.2.1" "$MLOG" && grep -q "PROBE key.2.0" "$MLOG"'
            chk "midimap.conf has the mapping" 'grep -q "^e2.num=71" "$MH/midimap.after" && grep -q "^e2.mode=rel2c" "$MH/midimap.after" && grep -q "^k2.num=85" "$MH/midimap.after"'
            chk "the pick is visible: the banner (white) and the window toast differ from the idle page" '[ "$(mmpx mm-listen.png 710 425)" = FFFFFF ] && [ "$(mmpx mm-idle.png 710 425)" != FFFFFF ]'
            return $bad
        }
        run "window:MIDI MAP (pick armed from the page, a click on E2 picks it, learned from JACK MIDI, drives E2 and K2 for the script that also sees every message)" midimap_ok
        mkdir -p "${SHOT_DIR:-/dev/null}" 2> /dev/null
        cp "$MH/mm-listen.png" "${SHOT_DIR:-/dev/null}/midimap-learn.png" 2> /dev/null
        cp "$MH/mm-listen.png" "$T/midimap-learn-full.png" 2> /dev/null
        rm -rf "$MH"
    }
    midimap_scenario
    # the MIDI actions in the real window (docs/port/midi-actions-plan.md): pads of a controller through JACK MIDI do what the buttons do (the mouse and the MIDI path give the same result: the TAPE page, MUTE, the keys
    # window; also with the row of buttons hidden), the screenshot is a file, fullscreen needs the detached screen, detach docks and undocks, the master switch OFF stops the actions but not E2 and K2, Ctrl+Shift+M works from the
    # norns window and the screen window, the menu item (17th, F10 and Return) ticks and unticks and is saved, and after a restart the menu and the actions follow the saved switch
    actions_scenario() {
        if [ ! -x "$T/midimap_send" ] && ! cc -std=gnu11 "$REPO/linux/tests/midimap_send.c" -o "$T/midimap_send" $(pkg-config --cflags --libs jack) 2> /dev/null; then
            echo "SKIP  window:MIDI actions (the JACK sender did not build)"
            return
        fi
        AH="$(mktemp -d)"
        ln -s "$REPO" "$AH/norns"
        mkdir -p "$AH/dust/code/probe"
        cp "$REPO/linux/tests/scripts/window_probe.lua" "$AH/dust/code/probe/"
        printf 'style=pixel\npreset=DARK\nbox=2C2E33\nkeys=444853\nencoders=5D6270\nbuttons=3A3D45\nfont=E4E6EA\nshow_buttons=1\n' > "$AH/box.conf"
        ALOG="$T/actions1.log"
        ALOG2="$T/actions2.log"
        MMS="$T/midimap_send" DC="$REPO/linux/tests/detach_check.sh" NORNS_HOME="$AH" "$REPO/linux/tests/norns_probe.sh" "$REPO/linux/tests/probe_actions.lua" "$ALOG" > /dev/null 2>&1
        cp "$AH/midimap.conf" "$T/actions-midimap.conf" 2> /dev/null
        for _ in $(seq 1 60); do pgrep -x norns > /dev/null || break; sleep 1; done # the first norns must be gone, or the second start only raises its window
        MMS="$T/midimap_send" DC="$REPO/linux/tests/detach_check.sh" NORNS_HOME="$AH" "$REPO/linux/tests/norns_probe.sh" "$REPO/linux/tests/probe_actions_restart.lua" "$ALOG2" > /dev/null 2>&1
        amark() { sed -n "s/^$1=//p" "$AH/probe.marks" 2> /dev/null | tail -1; }
        alg() { grep -a -- "PROBE $2" "$1" | tail -1 | sed "s/.*PROBE $2[[:space:]]*//; s/[[:space:]][[:space:]]*/ /g"; }
        apic() { convert "$AH/$1" -colorspace Gray -depth 8 gray:- | md5sum | cut -d' ' -f1; }
        # the tick of the menu item: where the ON and OFF pictures differ (a small region), in the picture of the restart moved by how far the window moved (it does not start where it was)
        tickreg() { compare -metric AE "$AH/menu-on.png" "$AH/menu-off.png" -compose src "$AH/tick-diff.png" > /dev/null 2>&1; convert "$AH/tick-diff.png" -format "%@" info: 2> /dev/null; }
        pcrop() { # file dx dy
            local g w h x y; g="$(tickreg)"; w="${g%%x*}"; h="${g#*x}"; h="${h%%+*}"; x="${g#*+}"; x="${x%%+*}"; y="${g##*+}"
            convert "$AH/$1" -crop "${w}x${h}+$((x + $2))+$((y + $3))" +repage -colorspace Gray -depth 8 gray:- | md5sum | cut -d' ' -f1
        }
        wpos() { local g; g="$(amark "$1")"; g="${g#*+}"; echo "${g%%+*} ${g##*+}"; } # win geometry mark -> X Y
        restart_dx() { local a b; a="$(wpos win1)"; b="$(wpos win2)"; echo $(( ${b% *} - ${a% *} )) $(( ${b#* } - ${a#* } )); }
        actions_ok() {
            local bad=0
            chk() { eval "$2" > /dev/null 2>&1 || { echo "missing: $1 (marks: $(tr '\n' ' ' < "$AH/probe.marks" 2> /dev/null | cut -c1-600))"; bad=1; }; }
            chk "the probes ran" 'grep -aq "PROBE actions done" "$ALOG" && grep -aq "PROBE actions restart done" "$ALOG2"'
            chk "the actions were set and the switch started ON" '[ "$(alg "$ALOG" start)" = "true 8" ]'
            chk "TAPE: the MIDI note and the mouse give the same state (the menu open on the TAPE page)" '[ -n "$(alg "$ALOG" "mouse tape")" ] && [ "$(alg "$ALOG" "mouse tape")" = "$(alg "$ALOG" "midi tape")" ] && alg "$ALOG" "midi tape" | grep -q "true.TAPE"'
            chk "MUTE: the MIDI note and the mouse give the same level, muted then unmuted" '[ "$(alg "$ALOG" "mouse mute1")" = "$(alg "$ALOG" "midi mute1")" ] && [ "$(alg "$ALOG" "mouse mute2")" = "$(alg "$ALOG" "midi mute2")" ] && [ "$(alg "$ALOG" "mouse mute1")" != "$(alg "$ALOG" "mouse mute2")" ]'
            chk "the keys window: the mouse and the MIDI note open it (1) and close it (0) alike" '[ "$(amark km1)" = 1 ] && [ "$(amark km2)" = 0 ] && [ "$(amark kd1)" = 1 ] && [ "$(amark kd2)" = 0 ]'
            chk "the row of buttons hidden: MUTE by MIDI still works, with the same levels" '[ "$(alg "$ALOG" "hidden mute1")" = "$(alg "$ALOG" "mouse mute1")" ] && [ "$(alg "$ALOG" "hidden mute2")" = "$(alg "$ALOG" "mouse mute2")" ]'
            chk "the screenshot action makes one file" '[ "$(amark shots_after)" = "$(( $(amark shots_before) + 1 ))" ]'
            chk "fullscreen with the screen docked: no screen window appears and norns lives" '[ "$(amark docked_screens)" = 0 ] && [ "$(amark docked_alive)" = yes ]'
            chk "the switch OFF: no mapped action fires (not MUTE, not TAPE) ..." '[ "$(alg "$ALOG" "off mute" | cut -d" " -f1)" = "$(alg "$ALOG" "mouse mute2")" ] && alg "$ALOG" "off mute" | grep -q "false\."'
            chk "... while E2 and K2 mappings keep working" 'grep -aq "PROBE enc.2.1" "$ALOG" && grep -aq "PROBE key.2.1" "$ALOG" && grep -aq "PROBE key.2.0" "$ALOG"'
            chk "Ctrl+Shift+M in the norns window turns it on and saves actions=1" '[ "$(alg "$ALOG" "shortcut norns")" = true ] && [ "$(amark conf_shortcut_on)" = yes ]'
            chk "then the pad mutes and unmutes again" '[ "$(alg "$ALOG" "on mute")" = "$(alg "$ALOG" "mouse mute1")" ] && [ "$(alg "$ALOG" "on unmute")" = "$(alg "$ALOG" "mouse mute2")" ]'
            chk "detach by MIDI opens the screen window (1)" '[ "$(amark detached_screens)" = 1 ]'
            chk "fullscreen by MIDI: the saved state says fullscreen=1, again fullscreen=0" '[[ "$(amark conf_fs_on)" == *fullscreen=1* && "$(amark conf_fs_off)" == *fullscreen=0* ]]'
            chk "Ctrl+Shift+M in the screen window turns it off and on" '[ "$(alg "$ALOG" "shortcut screen off")" = false ] && [ "$(alg "$ALOG" "shortcut screen on")" = true ]'
            chk "detach by MIDI again docks the screen (0)" '[ "$(amark redocked_screens)" = 0 ]'
            chk "the menu item: Return unticks it, the switch is off and midimap.conf says actions=0" '[ "$(alg "$ALOG" "menu off")" = false ] && [ "$(amark conf_menu_off)" = yes ] && grep -q "^actions=0" "$T/actions-midimap.conf"'
            chk "the tick is seen: the menu picture differs between ON and OFF" '[ "$(apic menu-on.png)" != "$(apic menu-off.png)" ]'
            chk "after a restart the switch is off and the actions are still set" '[ "$(alg "$ALOG2" "restart state")" = "false 38" ]'
            chk "after a restart the menu shows the tick OFF without a click (the item's tick region looks as in the OFF picture, not as in the ON picture)" 'read dx dy <<< "$(restart_dx)"; [ "$(pcrop menu-restart.png $dx $dy)" = "$(pcrop menu-off.png 0 0)" ] && [ "$(pcrop menu-restart.png $dx $dy)" != "$(pcrop menu-on.png 0 0)" ]'
            chk "after a restart the pad does nothing while OFF (restart: $(alg "$ALOG2" "restart pad off"), unmuted level: $(alg "$ALOG" "mouse mute2"); log: $(grep -a "PROBE restart" "$ALOG2" | tr '\n\t' '  ' | cut -c1-300))" '[ "$(alg "$ALOG2" "restart pad off")" = "$(alg "$ALOG" "mouse mute2")" ]'
            chk "the menu item turns it on again and the pad mutes" '[ "$(alg "$ALOG2" "restart menu on")" = true ] && [ "$(alg "$ALOG2" "restart pad on")" = "$(alg "$ALOG" "mouse mute1")" ]'
            chk "the capture of the ACTIONS list exists" '[ -s "$AH/actions-list.png" ]'
            return $bad
        }
        run "window:MIDI actions (pads do what the buttons do: same effect as the mouse, hidden row, screenshot, fullscreen, detach, master switch by page, shortcut and menu tick, saved and restored)" actions_ok
        mkdir -p "${SHOT_DIR:-/dev/null}" 2> /dev/null
        cp "$AH/actions-list.png" "${SHOT_DIR:-/dev/null}/actions-list-real.png" 2> /dev/null
        cp "$AH/actions-list.png" "$T/actions-list-full.png" 2> /dev/null
        rm -rf "$AH"
    }
    actions_scenario
    # quick script changes with the virtual grid and arc open and a mapped controller playing (docs/port/KNOWN-ISSUES.md 29): the last script starts every time, no error in the clear or the removal of devices
    rapid_scenario() {
        if [ ! -x "$T/midimap_send" ]; then
            echo "SKIP  window:quick script changes (the JACK sender did not build)"
            return
        fi
        RH="$(mktemp -d)"
        ln -s "$REPO" "$RH/norns"
        mkdir -p "$RH/dust/code/probe"
        cp "$REPO/linux/tests/scripts/rapid_a.lua" "$REPO/linux/tests/scripts/rapid_b.lua" "$REPO/linux/tests/scripts/window_probe.lua" "$RH/dust/code/probe/"
        RLOG="$T/rapid.log"
        MMS="$T/midimap_send" NORNS_HOME="$RH" "$REPO/linux/tests/norns_probe.sh" "$REPO/linux/tests/probe_rapid_load.lua" "$RLOG" > /dev/null 2>&1
        rapid_ok() {
            local bad=0
            chk() { eval "$2" > /dev/null 2>&1 || { echo "missing: $1"; bad=1; }; }
            chk "the probe ran" 'grep -aq "PROBE rapid done" "$RLOG"'
            chk "after five quick changes the last script (a) started and no load is pending" 'grep -aq "PROBE last.false.rapid_a" "$RLOG" && [ "$(grep -a "PROBE init" "$RLOG" | tail -n 3 | grep -c "init a")" -ge 1 ]'
            chk "after devices came and went during three more changes the last script (b) is running" 'grep -aq "PROBE last2.false.rapid_b" "$RLOG"'
            chk "no error in the clear or in a device removal (no traceback, no grid.lua / arc.lua error, no failed step)" '! grep -aE "attempt to index|stack traceback|script clear: .* failed|hook: .* failed|remove failed" "$RLOG"'
            chk "a call through the pointer of a removed grid is ignored and said (no write into freed memory), and the removed device is gone from grid.devices" 'grep -aq "PROBE grid devices after close.true" "$RLOG" && grep -aq "this grid or arc is gone" "$RLOG" && grep -aq "PROBE grid rows of a gone grid.0" "$RLOG"'
            chk "clicks on the window after the churn did not crash it" 'grep -aq "PROBE clicks done" "$RLOG"'
            chk "no crash report" '[ -z "$(ls "$RH"/logs/crash 2>/dev/null)" ]'
            return $bad
        }
        run "window:quick script changes (five loads before the engine of the one before is reported, devices coming and going, a controller playing: the last script starts, no error)" rapid_ok
        rm -rf "$RH"
    }
    rapid_scenario
    # the serialosc note in the real window (docs/port/KNOWN-ISSUES.md 33): the toast pill on the box and on the detached screen window and the guide on the norns screen; every line the page draws is measured with the real font
    toast_scenario() {
        TH2="$(mktemp -d)"
        ln -s "$REPO" "$TH2/norns"
        mkdir -p "$TH2/dust/code/probe"
        cp "$REPO/linux/tests/scripts/window_probe.lua" "$TH2/dust/code/probe/"
        TLOG2="$T/toast.log"
        DC="$REPO/linux/tests/detach_check.sh" NORNS_HOME="$TH2" "$REPO/linux/tests/norns_probe.sh" "$REPO/linux/tests/probe_toast.lua" "$TLOG2" > /dev/null 2>&1
        toast_ok() {
            local bad=0
            chk() { eval "$2" > /dev/null 2>&1 || { echo "missing: $1"; bad=1; }; }
            chk "the probe ran" 'grep -aq "PROBE toast done" "$TLOG2"'
            chk "the list of SYSTEM > DEVICES fits the screen (widest line 128 or less)" '[ "$(grep -a "PROBE devices list widest" "$TLOG2" | tail -n 1 | awk "{print \$NF}" | cut -d. -f1)" -le 128 ]'
            chk "every line of the SERIALOSC guide fits the screen" '[ "$(grep -a "PROBE guide widest" "$TLOG2" | tail -n 1 | awk "{print \$(NF-1)}" | cut -d. -f1)" -le 128 ]'
            chk "every line of the question fits the screen" '[ "$(grep -a "PROBE question widest" "$TLOG2" | tail -n 1 | awk "{print \$(NF-1)}" | cut -d. -f1)" -le 128 ]'
            chk "the captures exist" '[ -s "$TH2/serialosc-note.png" ] && [ -s "$TH2/serialosc-devices.png" ] && [ -s "$TH2/serialosc-screen.png" ]'
            return $bad
        }
        run "window:the serialosc note fits its border (the toast on the box and on the screen window, the guide on the norns screen, measured)" toast_ok
        mkdir -p "${SHOT_DIR:-/dev/null}" 2> /dev/null
        cp "$TH2/serialosc-note.png" "${SHOT_DIR:-/dev/null}/serialosc-note.png" 2> /dev/null
        cp "$TH2/serialosc-devices.png" "${SHOT_DIR:-/dev/null}/serialosc-devices.png" 2> /dev/null
        cp "$TH2/serialosc-screen.png" "$T/serialosc-screen-full.png" 2> /dev/null
        rm -rf "$TH2"
    }
    toast_scenario
    # the virtual grid (F6), keys (F7) and arc (F8) windows: the norns window keeps its size and position while they open and close again and again, from the norns window and from their own window, also with the detached
    # screen window open; each closes with the key that opens it (F7 did not close the keys window: its key events never reached norns)
    window_toggle_scenario() {
        TH="$(mktemp -d)"
        ln -s "$REPO" "$TH/norns"
        mkdir -p "$TH/dust/code/probe"
        cp "$REPO/linux/tests/scripts/window_probe.lua" "$TH/dust/code/probe/"
        printf 'style=pixel\npreset=DARK\nbox=2C2E33\nkeys=444853\nencoders=5D6270\nbuttons=3A3D45\nfont=E4E6EA\nshow_buttons=1\n' > "$TH/box.conf"
        TLOG="$T/toggle.log"
        NORNS_HOME="$TH" "$REPO/linux/tests/norns_probe.sh" "$REPO/linux/tests/probe_toggle.lua" "$TLOG" > /dev/null 2>&1
        toggle_ok() {
            grep -q "PROBE toggle done" "$TLOG" || { echo "missing: the probe ran"; return 1; }
            python3 -I - "$TH/probe.marks" << 'PY'
import sys
m = dict(l.rstrip("\n").split("=", 1) for l in open(sys.argv[1]) if "=" in l)
bad = []
base = m.get("base")
if base is None or not base.startswith("800x516+"):
    bad.append("the norns window could not be set to 800 x 516 (base=%s)" % base)
for k, v in m.items():
    if k.endswith("_main") and v != base:
        bad.append("the norns window changed at %s: %s instead of %s" % (k, v, base))
    elif "_open" in k and not k.endswith("_main") and v != "1":
        bad.append("%s: %s window(s), wanted 1 (the key did not open it)" % (k, v))
    elif "_closed" in k and not k.endswith("_main") and v != "0":
        bad.append("%s: %s window(s), wanted 0 (the key did not close it)" % (k, v))
for need in ("grid_open1", "arc_open2", "keys_closed1", "keys_closed2", "all_open_keys", "all_closed_keys", "d_keys_closed1", "d_arc_closed2", "d_grid_open2"):
    if need not in m:
        bad.append("no mark %s" % need)
if m.get("detached") != "1" or m.get("d_screen_still") != "1":
    bad.append("the detached screen window was not open (detached=%s, still=%s)" % (m.get("detached"), m.get("d_screen_still")))
for b in bad:
    print("missing: " + b)
sys.exit(1 if bad else 0)
PY
        }
        run "window:grid, keys and arc windows open and close with F6, F7, F8 again and again (from the norns window and from their own window, with the screen detached) and the norns window keeps its size and position" toggle_ok
        rm -rf "$TH"
    }
    window_toggle_scenario
    # the virtual arc from the keyboard and from MIDI in the real window (docs/port/arc-plan.md): 5/6 T/Y G/H B/N with the arc window in front (tier 1) and with the norns window in front (tier 2), a held key repeats and
    # its release steps nothing, no other key and no key in the menu turns it, a click on a ring while a learn is armed picks it, a CC played through JACK MIDI is learned and turns that ring, a closed window is not turned
    arc_scenario() {
        if [ ! -x "$T/midimap_send" ]; then
            echo "SKIP  window:arc (the JACK sender did not build)"
            return
        fi
        AH="$(mktemp -d)"
        ln -s "$REPO" "$AH/norns"
        mkdir -p "$AH/dust/code/probe"
        cp "$REPO/linux/tests/scripts/window_probe.lua" "$AH/dust/code/probe/"
        printf 'style=pixel\npreset=DARK\nbox=2C2E33\nkeys=444853\nencoders=5D6270\nbuttons=3A3D45\nfont=E4E6EA\nshow_buttons=1\n' > "$AH/box.conf"
        ALOG="$T/arc.log"
        MMS="$T/midimap_send" NORNS_HOME="$AH" "$REPO/linux/tests/norns_probe.sh" "$REPO/linux/tests/probe_arc.lua" "$ALOG" > /dev/null 2>&1
        # the arc deltas between two markers of the log, one "ring delta" per line
        between() { sed -n "/$1/,/$2/p" "$ALOG" | sed -n 's/^PROBE arcdelta[[:space:]]*\([0-9]*\)[[:space:]]*\(-*[0-9]*\)$/\1 \2/p' | tr '\n' ','; }
        arc_ok() {
            local bad=0
            chk() { eval "$2" > /dev/null 2>&1 || { echo "missing: $1 (got: $(eval "${3:-true}"))"; bad=1; }; }
            chk "the probe ran" 'grep -q "PROBE arc done" "$ALOG"'
            chk "tier 1, the arc window in front: 5, y, shift+g, b = ring 1 left, 2 right, 3 left fine, 4 left" '[ "$(between "PROBE window init" "PROBE tier1 done")" = "1 -16,2 16,3 -4,4 -16," ]' 'between "PROBE window init" "PROBE tier1 done"'
            chk "tier 2, the norns window in front: 6 and n" '[ "$(between "PROBE tier1 done" "PROBE tier2 done")" = "1 16,4 16," ]' 'between "PROBE tier1 done" "PROBE tier2 done"'
            chk "a held key repeats, in steps of 16, and nothing comes after the release" '[ "$(between "PROBE tier2 done" "PROBE hold done" | tr "," "\n" | grep -c "^2 -16$")" -ge 3 ] && [ "$(between "PROBE tier2 done" "PROBE hold done" | tr "," "\n" | grep -vc "^2 -16$")" = 0 ] && [ -z "$(between "PROBE hold done" "PROBE other keys done")" ]'
            chk "the keys 1 and 2 do not turn the arc" '[ -z "$(between "PROBE hold done" "PROBE other keys done")" ]'
            chk "with a text entry open and the arc window in front the keys 5 y 6 are typed into the entry and turn nothing" 'grep -q "PROBE entry text.5y6.true" "$ALOG" && [ -z "$(between "PROBE other keys done" "PROBE entry text")" ]' 'between "PROBE other keys done" "PROBE entry text"'
            chk "after the entry the key 5 turns ring 1 again" '[ "$(between "PROBE entry text" "PROBE after entry done")" = "1 -16," ]' 'between "PROBE entry text" "PROBE after entry done"'
            chk "in the menu the keys are not the arc (H there is the colour picker's)" '[ -z "$(between "PROBE after entry done" "PROBE menu keys done")" ]'
            chk "a learn is armed from the page" 'grep -q "PROBE learn state.pick" "$ALOG"'
            chk "a click on ring 3 picks it and does not turn it" 'grep -q "PROBE picked.listen.a3" "$ALOG" && [ -z "$(between "PROBE learn state" "PROBE picked")" ]'
            chk "the controller played through JACK MIDI is learned for A3: CC 76, offset binary" 'grep -q "PROBE learned.idle.cc.76.relob" "$ALOG"'
            chk "the learned CC turns ring 3: 8 ticks a unit, the right way" '[ "$(between "PROBE learned" "PROBE arc closed done")" = "3 8,3 -8,3 16," ]' 'between "PROBE learned" "PROBE arc closed done"'
            chk "with the arc window closed a mapped CC turns nothing" '[ "$(between "PROBE learned" "PROBE arc done")" = "3 8,3 -8,3 16," ]' 'between "PROBE learned" "PROBE arc done"'
            chk "WATCH shows what the unit sends: CC 76, offset binary, six values" 'grep -q "PROBE watch.76.relob.LOOKS LIKE REL OFS.6" "$ALOG"'
            chk "midimap.conf has the arc mapping" 'grep -q "^a3.num=76" "$AH/midimap.after" && grep -q "^a3.mode=relob" "$AH/midimap.after" && grep -q "^a3.gain=8" "$AH/midimap.after"'
            return $bad
        }
        run "window:virtual arc from the keyboard (both windows, hold, release) and from MIDI (learn by clicking the ring, ticks, closed window)" arc_ok
        mkdir -p "${SHOT_DIR:-/dev/null}" 2> /dev/null
        cp "$AH/watch-real.png" "${SHOT_DIR:-/dev/null}/arc-watch.png" 2> /dev/null
        rm -rf "$AH"
    }
    arc_scenario
    # the pixel looks in the real window (docs/port/retro-look-plan.md): from box.conf, switched live from the THEME page's PIXEL LOOK row, each look is another picture, saved, remembered after a restart, and the
    # colour picker changes a colour live in a retro look
    retro_scenario() {
        RH="$(mktemp -d)"
        ln -s "$REPO" "$RH/norns"
        mkdir -p "$RH/dust/code/probe"
        cp "$REPO/linux/tests/scripts/window_probe.lua" "$RH/dust/code/probe/"
        printf 'style=pixel\npixel_look=retro\npreset=DARK\nbox=2C2E33\nkeys=444853\nencoders=5D6270\nbuttons=3A3D45\nfont=E4E6EA\nshow_buttons=1\n' > "$RH/box.conf"
        RLOG1="$T/retro1.log"; RLOG2="$T/retro2.log"
        NORNS_HOME="$RH" "$REPO/linux/tests/norns_probe.sh" "$REPO/linux/tests/probe_retro.lua" "$RLOG1" > /dev/null 2>&1
        cp "$RH/probe.marks" "$RH/marks1" 2> /dev/null
        NORNS_HOME="$RH" "$REPO/linux/tests/norns_probe.sh" "$REPO/linux/tests/probe_retro_restart.lua" "$RLOG2" > /dev/null 2>&1
        rpx() { convert "$RH/$1" -format "%[hex:u.p{$2,$3}]" info:; }
        rdiff() { [ "$(compare -metric AE "$RH/$1" "$RH/$2" null: 2>&1 | cut -d' ' -f1)" != 0 ]; }
        retro_ok() {
            local bad=0
            chk() { eval "$2" > /dev/null 2>&1 || { echo "missing: $1"; bad=1; }; }
            local live
            live="$(sed -n 's/^PROBE picker live[[:space:]]\([0-9A-F]*\).*/\1/p' "$RLOG1" | tail -1)"
            chk "the probe ran" 'grep -q "PROBE before restart" "$RLOG1"'
            chk "box.conf pixel_look=retro is read at start" 'grep -q "PROBE start look.retro" "$RLOG1"'
            chk "E3 on PIXEL LOOK: pixel, 8-bit, 16-bit in turn (live)" 'grep -q "PROBE look after E3 left.pixel" "$RLOG1" && grep -q "PROBE look after E3 right x2.8-bit" "$RLOG1" && grep -q "PROBE look after E3 right.16-bit" "$RLOG1"'
            chk "every look is another picture (6 pairs)" 'rdiff rt-pixel.png rt-retro.png && rdiff rt-pixel.png rt-8bit.png && rdiff rt-pixel.png rt-16bit.png && rdiff rt-retro.png rt-8bit.png && rdiff rt-retro.png rt-16bit.png && rdiff rt-8bit.png rt-16bit.png'
            chk "PIXEL in the window: the box face is the BOX colour and a key is the KEYS colour" '[ "$(rpx rt-pixel.png 676 300)" = 2C2E33 ] && [ "$(rpx rt-pixel.png 260 273)" = 444853 ]'
            chk "the retro looks keep the colours: the key is the KEYS colour" '[ "$(rpx rt-retro.png 260 273)" = 444853 ] && [ "$(rpx rt-8bit.png 260 273)" = 444853 ]'
            chk "the choice is saved in box.conf" '[ "$(sed -n "s/^saved_16bit=//p" "$RH/marks1" | tail -1)" = yes ]'
            chk "a look with the COLOUR colours: the key is the COLOUR keys colour in RETRO" '[ "$(rpx rt-retro-colour.png 260 273)" = F2B63D ]'
            chk "the picker changes the key live in RETRO ($live) and the look stays retro" '[ -n "$live" ] && [ "$(rpx rt-picker-live.png 260 273)" = "$live" ] && grep -q "PROBE picker live.*retro" "$RLOG1"'
            chk "after a restart the look is remembered (8-bit) and drawn" 'grep -q "PROBE restart look.8-bit" "$RLOG2" && rdiff rt-restart.png rt-retro-colour.png'
            return $bad
        }
        run "window:pixel looks (PIXEL RETRO 8-BIT 16-BIT from box.conf and the THEME row, live, saved, the colours and the picker work with them, remembered after a restart)" retro_ok
        rm -rf "$RH"
    }
    retro_scenario
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
            chk "a cell press reaches the script while the screen is detached" '[ "$(grep -c "PROBE gridkey.[0-9]*.[0-9]*.1" "$D1")" -ge 1 ]'
            chk "...and again while the screen window is hidden" '[ "$(grep -c "PROBE gridkey.[0-9]*.[0-9]*.1" "$D1")" -ge 2 ]'
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
