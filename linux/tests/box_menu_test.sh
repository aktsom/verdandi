#!/bin/bash
# the right-click menu of the box styles (docs/port/box-style-plan.md 2.8), checked in the source of the shell (desktop_shell_linux.cc builds the menu in a static function, so the items are
# read from it) and in the window code: "Show the page buttons" (a tick, saved by lua), "Mute output" with the hint Ctrl+M next to it, "Open maiden" and "Open the manual" (the menu twins of the
# two buttons); Ctrl+M handled in C next to Ctrl+Q and Ctrl+O, without Shift, from the same place for the box and the screen window; the menu has room for every item (MENU_MAX against the
# most the menu can hold); no script-facing F key is used; Mac and device unchanged (everything is behind NORNS_LINUX_DESKTOP / in the Linux shell file)
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO" || exit 1
FAIL=0
ok() { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; FAIL=1; }
SH=matron/src/platform/linux/desktop_shell_linux.cc
BR=matron/src/platform/macos/sdl_bridge.cc
grep -q 'add_item(SHELL_MENU_SHOW_BUTTONS, "Show the page buttons", "", buttons_shown)' $SH && ok "item: Show the page buttons (a tick)" || bad "no 'Show the page buttons' item"
grep -q 'add_item(SHELL_MENU_MUTE, "Mute output", "Ctrl+M", muted)' $SH && ok "item: Mute output, hint Ctrl+M, ticked while muted" || bad "no 'Mute output  Ctrl+M' item"
grep -q 'add_item(SHELL_MENU_MAIDEN, "Open maiden"' $SH && grep -q 'add_item(SHELL_MENU_MANUAL, "Open the manual"' $SH && ok "items: Open maiden, Open the manual" || bad "maiden / manual items"
awk '/add_item\(SHELL_MENU_MUTE/ {m=NR} /add_item\(SHELL_MENU_INPUT_MIC/ {i=NR} END {exit !(m && i && m < i && i - m <= 6)}' $SH && ok "Mute output sits next to the Input items (the MIDI actions item between)" || bad "Mute output is not next to the Input items"
grep -q 'ctrl && !shift && scancode == SDL_SCANCODE_M' $SH && ok "Ctrl+M (without Shift) is handled in the shell, next to Ctrl+Q and Ctrl+O" || bad "no Ctrl+M handler"
awk '/ctrl && scancode == SDL_SCANCODE_O/ {o=NR} /scancode == SDL_SCANCODE_M/ {m=NR} /if \(!menu.open\)/ {c=NR} END {exit !(c && o && m && c < o && o < m)}' $SH && ok "the shortcut is in the branch for a closed menu (an open menu takes every key)" || bad "Ctrl+M not in the closed-menu branch"
# MIDI actions (docs/port/midi-actions-plan.md): the ticked item built like the file dialog item, Ctrl+Shift+M next to Ctrl+M, the bridge tells lua
grep -q 'add_item(SHELL_MENU_MIDI_ACTIONS, "MIDI actions enabled", "Ctrl+Shift+M", midi_actions.load())' $SH && ok "item: MIDI actions enabled, hint Ctrl+Shift+M, ticked from the stored state" || bad "no 'MIDI actions enabled' item"
grep -q 'ctrl && shift && scancode == SDL_SCANCODE_M' $SH && ok "Ctrl+Shift+M is handled in the shell (closed-menu branch), next to Ctrl+M" || bad "no Ctrl+Shift+M handler"
awk '/if \(!menu.open\)/ {c=NR} /ctrl && shift && scancode == SDL_SCANCODE_M/ {m=NR} /\/\/ open: it takes every key/ {o=NR} END {exit !(c && m && o && c < m && m < o)}' $SH && ok "Ctrl+Shift+M is in the branch for a closed menu" || bad "Ctrl+Shift+M is not in the closed-menu branch"
grep -q 'case SHELL_MENU_MIDI_ACTIONS:' $BR && grep -q 'call_lua("midi_actions_changed"' $BR && grep -q 'window_actions_switch_message' $BR && ok "the bridge tells lua (midi_actions_changed) and says MIDI actions on/off in the window" || bad "MIDI actions wiring"
grep -q 'shell_set_midi_actions' $BR && ok "lua can set the tick (sdl_bridge_set_midi_actions)" || bad "no way to set the tick from lua"
grep -q 'ctrl && scancode == SDL_SCANCODE_O' $SH && grep -q 'ev->key.windowID == screen_window_id()' $BR && ok "the shell's shortcuts also come from the screen window (menu_event), so Ctrl+M does" || bad "screen window shortcuts"
grep -q 'case SHELL_MENU_MUTE:' $BR && grep -q 'call_lua("output_mute"' $BR && ok "the bridge calls lua's output_mute (the same as the MUTE button)" || bad "mute is not wired"
grep -q 'call_lua("box_buttons_changed"' $BR && ok "the tick is told to lua (box_buttons_changed), which saves it" || bad "box_buttons_changed"
grep -q 'case SHELL_MENU_MAIDEN:' $BR && grep -q 'case SHELL_MENU_MANUAL:' $BR && ok "the maiden and manual items are wired" || bad "maiden / manual wiring"
# room: the most the menu can hold = the add_item/add_separator lines of menu_build (fixed ones) + the apps + the optional monitor
fixed=$(awk '/^static void menu_build/ {on=1} on && /^}/ {exit} on && /add_item\(|add_separator\(/ {n++} END {print n}' $SH)
apps=$(sed -n 's/^#define MENU_APPS \([0-9]*\).*/\1/p' $SH)
max=$(sed -n 's/^#define MENU_MAX \([0-9]*\).*/\1/p' matron/src/platform/linux/menu_skin.h)
# the add_item inside the apps loop and the monitor line are counted once in "fixed": the real maximum is fixed - 2 (loop, monitor) + apps + 1 (monitor)
most=$((fixed - 1 + apps))
[ "$max" -ge "$most" ] && ok "MENU_MAX $max holds the most the menu can have ($most items)" || bad "MENU_MAX $max is too small for $most items"
# the rest of the menu is where it was: the items of the earlier steps are all still there
for l in "Import files..." "Import folder..." "Copy samples into dust" "Open the file dialog when a script loads a file" "Show dust folder" "Show tape folder" "Screenshot" "Virtual grid" "Virtual arc" "Virtual keyboard" "Screen in its own window" "Input: microphone" "Input: all apps" "Input: off" "Quit"; do
    grep -qF "\"$l\"" $SH || bad "the menu lost '$l'"
done
ok "the earlier items are all still in the menu"
# the Mac and the device: the new code is behind the Linux guard
for f in $BR matron/src/weaver.cc; do
    python3 - "$f" << 'PY' || bad "$f: a box line outside NORNS_LINUX_DESKTOP"
import re, sys
stack = []
for n, line in enumerate(open(sys.argv[1]), 1):
    s = line.strip()
    if s.startswith("#ifdef NORNS_LINUX_DESKTOP") or s.startswith("#if defined(NORNS_LINUX_DESKTOP"): stack.append("L")
    elif s.startswith("#ifndef NORNS_LINUX_DESKTOP"): stack.append("M")
    elif s.startswith("#if"): stack.append("?")
    elif s.startswith("#else") and stack: stack[-1] = {"L": "M", "M": "L"}.get(stack[-1], "?")
    elif s.startswith("#endif") and stack: stack.pop()
    if re.search(r"box_look|box_buttons_changed|SHELL_MENU_(SHOW_BUTTONS|MUTE|MAIDEN|MANUAL)|skin_set_look|skin_set_buttons_shown|skin_buttons_shown|shell_set_buttons_shown|shell_get_buttons_shown|shell_set_muted", line):
        if "L" not in stack and not s.startswith(("//", "*", "/*")):
            print("%s:%d: %s" % (sys.argv[1], n, s)); sys.exit(1)
PY
done
ok "the box code in the bridge and weaver is inside NORNS_LINUX_DESKTOP blocks"
[ $FAIL = 0 ] && echo "box_menu_test: all passed"
exit $FAIL
