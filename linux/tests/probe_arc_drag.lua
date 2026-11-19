# the left-button drag in the real arc window under Xvfb, with real mouse events from xdotool (docs/port/phase-m14.md): ARC DRAG up and down (up is clockwise, 12 ticks a pixel at 1:1, a lap of 1024 ticks
# in 85 pixels) and round the ring (unchanged: a quarter turn of the pointer is 64 ticks), the drag goes on outside the window until the button is let go (the mouse is captured), nothing moves the window, nothing turns after the release.
# the arc window is 830 x 260 pixels here; ring n is centred at x 130 + 190 (n - 1), y 130 (varc_skin.c). the script is window_probe.lua (it prints "PROBE arcdelta ring delta")
#sleep 5
norns.script.load("code/probe/window_probe.lua")
#sleep 3
mm = norns.midimap
S = require "core/midimap_settings"
print("PROBE default", S.state.arc_drag)
-- (the default of new settings is up and down since M25; the first step is round the ring, so it is chosen here, as MIDI MAP > ARC DRAG does)
S.set_arc_drag("circle")
mm.changed()
_norns.grid_window("arc")
#sleep 2
#xdo search --name ^arc$ windowfocus
#sleep 0.5
#sh xdotool search --name '^arc$' getwindowgeometry --shell | tr '\n' ' ' > "$MARKS.geom0"
# 1. round the ring (chosen above): from the top of ring 1 to its right side, a quarter turn, in steps of 15 degrees on a circle of 40 pixels (one xdotool call a step with a short pause: xdotool's own chained moves right after a press lose one)
#sh ID=$(xdotool search --name '^arc$' | head -1); xdotool mousemove --window $ID 130 90 mousedown 1; for d in 15 30 45 60 75 90; do x=$(awk -v d=$d 'BEGIN { printf "%d", 130 + 40 * sin(d * 3.14159265 / 180) }'); y=$(awk -v d=$d 'BEGIN { printf "%d", 130 - 40 * cos(d * 3.14159265 / 180) }'); xdotool mousemove --window $ID $x $y; sleep 0.05; done; xdotool mouseup 1
#sleep 0.5
print("PROBE circle done")
# 2. switch to up and down (what MIDI MAP > ARC DRAG does) and drag: 86 pixels up, then 86 down, in steps of 2 pixels
S.set_arc_drag("updown")
mm.changed()
print("PROBE setting", S.state.arc_drag, mm.arc_drag_updown())
#sh cp "$NORNS_HOME/midimap.conf" "$NORNS_HOME/midimap.during"
#sleep 0.5
#sh ID=$(xdotool search --name '^arc$' | head -1); a="mousemove --window $ID 130 150 mousedown 1"; for i in $(seq 43); do a="$a mousemove_relative -- 0 -2"; done; xdotool $a mouseup 1
#sleep 0.5
print("PROBE up done")
#sh ID=$(xdotool search --name '^arc$' | head -1); a="mousemove --window $ID 130 100 mousedown 1"; for i in $(seq 43); do a="$a mousemove_relative -- 0 2"; done; xdotool $a mouseup 1
#sleep 0.5
print("PROBE down done")
# 3. (no Shift step here: xdotool's Shift under Xvfb reached SDL only part of the way through the drag in about one run in seven, so a check on it would be a coin toss. Shift is checked by the C numbers
#     (arc_input_test.c) and, in the real program, by the Windows CI hook with SDL_SetModState; the real key is on the owner's checklist)
print("PROBE shift done")
# 4. the mouse leaves the window: from y 150 straight up 200 pixels (the top of the window is 150 pixels up: 50 pixels outside), the pointer is over another window or the root, still counted; released there
#sh ID=$(xdotool search --name '^arc$' | head -1); a="mousemove --window $ID 130 150 mousedown 1"; for i in $(seq 100); do a="$a mousemove_relative -- 0 -2"; done; xdotool $a mouseup 1
#sleep 0.5
print("PROBE outside done")
# 5. after the release nothing turns: move over the ring with no button
#sh ID=$(xdotool search --name '^arc$' | head -1); a="mousemove --window $ID 130 200"; for i in $(seq 20); do a="$a mousemove_relative -- 0 -2"; done; xdotool $a
#sleep 0.5
print("PROBE free move done")
# 6. a drag on ring 3 (centre x 510), straight down 20 pixels: -240 on ring 3 only
#sh ID=$(xdotool search --name '^arc$' | head -1); a="mousemove --window $ID 510 110 mousedown 1"; for i in $(seq 10); do a="$a mousemove_relative -- 0 2"; done; xdotool $a mouseup 1
#sleep 0.5
print("PROBE ring3 done")
# 7. the right button still pushes (down and up are keys, nothing turns), the wheel still turns by 2 a notch
#sh ID=$(xdotool search --name '^arc$' | head -1); xdotool mousemove --window $ID 130 150 mousedown 3 mousemove_relative -- 0 -30 mouseup 3 click 4
#sleep 0.5
print("PROBE push wheel done")
# 8. back to round the ring: a drag straight down on the right side of ring 1 is a turn clockwise (about 26 degrees, 19 ticks), and the file has the setting
S.set_arc_drag("circle")
mm.changed()
#sh ID=$(xdotool search --name '^arc$' | head -1); xdotool mousemove --window $ID 170 130 mousedown 1; for i in $(seq 10); do xdotool mousemove_relative -- 0 2; sleep 0.03; done; xdotool mouseup 1
#sleep 0.5
print("PROBE circle again done")
# 9. M25: Ctrl is the four times faster turn on Linux as on Windows (the Super key opens the desktop's menu when it is let go): one wheel notch is 2 ticks, with Ctrl held 8
#sh ID=$(xdotool search --name '^arc$' | head -1); xdotool mousemove --window $ID 130 150; sleep 0.3; xdotool keydown ctrl; sleep 0.4; xdotool click 4; sleep 0.4; xdotool keyup ctrl; sleep 0.3
print("PROBE ctrl wheel done")
#sh xdotool click 4
#sleep 0.5
print("PROBE plain wheel done")
#sh cp "$NORNS_HOME/midimap.conf" "$NORNS_HOME/midimap.after"
#sh xdotool search --name '^arc$' getwindowgeometry --shell | tr '\n' ' ' > "$MARKS.geom1"
print("PROBE arc drag done")
