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
trap 'rm -rf "$T"' EXIT
WAF="${WAF:-/opt/waf/waf}"

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
    grep -q "running post-startup" "$PROBE_LOG" &&
        grep -q "PROBE engines.5" "$PROBE_LOG" &&
        grep -q "PROBE script init ok" "$PROBE_LOG" &&
        grep -q "PROBE loaded.probe.PolyPerc" "$PROBE_LOG" &&
        grep -q "PROBE key.2.1" "$PROBE_LOG" &&
        grep -q "PROBE enc.1" "$PROBE_LOG"
}
run "boot:headless (xvfb, jackd dummy, crone, sclang, script)" boot_ok

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
        wl "PROBE window init" && wl "PROBE window done" &&
            wl "PROBE key.2.1" && wl "PROBE key.2.0" && wl "PROBE enc.2" && # mouse: K2, wheel on E2
            wl "PROBE key.3.1" && wl "PROBE key.3.0" && wl "PROBE enc.1" && # keyboard: 3, w
            wl "PROBE devices.virtual grid m0000001.monome arc virtual m0000002" &&
            wl "PROBE gridkey.2.2.1" && wl "PROBE gridkey.2.2.0" && # a click on the grid window
            wl "PROBE arcdelta.1.2" && wl "PROBE arckey.1.1" && wl "PROBE arckey.1.0"
    }
    run "window:mouse, keyboard, virtual grid and arc" window_ok
    # the oled shows the script's rectangle (about 8% of it is white), the grid shows the lit key
    oled_mean() { convert "$WH/window-device.png" -crop 420x220+235+440 -colorspace Gray -format "%[fx:mean]" info:; }
    window_pixels() { awk -v m="$(oled_mean)" 'BEGIN { exit !(m > 0.03 && m < 0.3) }'; }
    run "window:oled pixels" window_pixels
    cp "$WH/window-device.png" "$WH/window-devices.png" "${SHOT_DIR:-/dev/null}" 2> /dev/null
else
    echo "SKIP  window (xdotool and imagemagick not installed)"
fi

echo
echo "known failures: ${#KNOWN[@]}  unexpected failures: ${#FAILED[@]}"
[ ${#FAILED[@]} -eq 0 ]
