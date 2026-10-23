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
trap '[ -n "${KEEP_LOGS:-}" ] && { mkdir -p "$KEEP_LOGS" && cp "$T"/*.log "$KEEP_LOGS"/ 2> /dev/null; }; rm -rf "$T"' EXIT
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

for t in menu_pages input_modes fileselect_finder output_fader; do
    run "lua:$t" lua5.3 "$M/${t}_test.lua"
done
run "lua:keyboard_hardware" env NORNS_HARDWARE_KEYS=1 lua5.3 "$M/keyboard_hardware_test.lua"
VH="$(mktemp -d)"
run "lua:virtual_home" env HOME="$VH" lua5.3 "$M/virtual_home_test.lua" lua/core/virtual_home.lua

# gnu11, not c11: M_PI and ptsname need the GNU feature macros, as in the waf build
CFLAGS="-std=gnu11 -D_GNU_SOURCE -I $P -I /usr/local/include"
cc $CFLAGS "$M/window_keys_test.c" "$P/window_keys.c" -o "$T/wkt" && run "c:window_keys" "$T/wkt"
cc $CFLAGS $(pkg-config --cflags cairo) "$M/device_skin_test.c" "$P/device_skin.c" "$P/vgrid_skin.c" \
    "$P/varc_skin.c" "$P/vkeys_skin.c" -o "$T/dst" $(pkg-config --libs cairo) -lm && run "c:device_skin" "$T/dst"
cc $CFLAGS -I matron/src/platform/linux $(pkg-config --cflags cairo) linux/tests/menu_skin_test.c \
    matron/src/platform/linux/menu_skin.c -o "$T/mst" $(pkg-config --libs cairo) -lm && run "c:menu_skin" "$T/mst"
# needs libmonome with linux/patches/libmonome-pty-serial.patch (linux/setup-deps.sh)
cc $CFLAGS "$M/vgrid_test.c" "$P/vgrid_proto.c" "$P/vgrid_device.c" -L/usr/local/lib -lmonome -lpthread \
    -o "$T/vgt" && LD_LIBRARY_PATH=/usr/local/lib run "c:vgrid" "$T/vgt"
cc $CFLAGS "$M/dust_import_test.c" "$P/dust_import.c" -o "$T/dit" && run "c:dust_import" "$T/dit"
# the same as an ordinary user: root can read every file, so the failed-copy case only runs here
chmod 755 "$T" && setpriv --reuid=65534 --regid=65534 --clear-groups true 2> /dev/null &&
    run "c:dust_import (as nobody)" setpriv --reuid=65534 --regid=65534 --clear-groups "$T/dit"
echo "SKIP  c:gif (links ImageIO), objc: drop_test app_input_test"

run "waf:unit tests" "$WAF" test

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
        done
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
        grep -q "PROBE input done" "$ILOG" || { echo "probe did not finish"; bad=1; }
        return $bad
    }
    run "input:MIC, SYS (all apps but norns), APP, sink monitor, OFF by port flags and names" input_ok
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
    oled_mean() { convert "$WH/window-device.png" -crop 420x220+235+440 -colorspace Gray -format "%[fx:mean]" info:; }
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
else
    echo "SKIP  window (xdotool and imagemagick not installed)"
fi

echo
echo "known failures: ${#KNOWN[@]}  unexpected failures: ${#FAILED[@]}"
[ ${#FAILED[@]} -eq 0 ]
