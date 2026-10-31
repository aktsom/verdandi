# MIDI actions in the real window (run_all.sh, actions_scenario; docs/port/midi-actions-plan.md). pads of a controller play into Verdandi:midi_in through JACK MIDI ($MMS, notes as hex: 36 = 24 ... 44 = 2C):
#   the mouse and the MIDI path do the same thing (TAPE page, MUTE, the keys window), also with the row of buttons hidden; screenshot makes a file; fullscreen needs the screen detached (docked: nothing happens),
#   detach docks and undocks; with the master switch OFF nothing fires and a mapped E and K still do; Ctrl+Shift+M works from the norns window and the screen window; the tick in the menu (F10, 17th item) and its saved value.
# $DC is detach_check.sh. the home has box.conf: pixel, DARK, buttons shown
#sleep 5
norns.script.load("code/probe/window_probe.lua")
#sleep 3
mm = norns.midimap
S = require "core/midimap_settings"
pg = require "core/menu/midimap"
bs = require "core/box_settings"
S.clear_all_actions()
S.assign_action("mix", "note", 36)
S.assign_action("tape", "note", 37)
S.assign_action("mute", "note", 38)
S.assign_action("keys", "note", 39)
S.assign_action("screenshot", "note", 40)
S.assign_action("detach", "note", 41)
S.assign_action("fullscreen", "note", 42)
S.assign_action("home", "note", 43)
S.set("e2", "num", 71) S.set("e2", "mode", "rel2c") S.set("k2", "type", "cc") S.set("k2", "num", 85)
mm.set_actions(true)
mm.changed()
st = function() return tostring(_menu.mode) .. "." .. tostring(_menu.page) end
lvl = function() return tostring(params:get("output_level")) end
print("PROBE start", S.state.actions_on, S.count_actions())
#xdo search --name ^Verdandi.Linux$ windowfocus
#sleep 0.5
# 1. the TAPE button: mouse, then the MIDI note (notes off and velocity 0 do nothing more)
_menu.set_mode(false)
#click ^Verdandi.Linux$ 0.169 0.109
#sleep 1
print("PROBE mouse tape", st())
_menu.set_mode(false)
#sleep 0.5
#sh "$MMS" 90:25:64 80:25:00 90:25:00 > "$MARKS.s1" 2>&1
#sleep 1
print("PROBE midi tape", st())
_menu.set_mode(false)
# 2. MUTE: mouse (twice: muted, unmuted), MIDI (twice)
#click ^Verdandi.Linux$ 0.911 0.109
#sleep 1
print("PROBE mouse mute1", lvl())
#click ^Verdandi.Linux$ 0.911 0.109
#sleep 1
print("PROBE mouse mute2", lvl())
#sh "$MMS" 90:26:64 80:26:00 > "$MARKS.s2" 2>&1
#sleep 1
print("PROBE midi mute1", lvl())
#sh "$MMS" 90:26:64 80:26:00 > "$MARKS.s3" 2>&1
#sleep 1
print("PROBE midi mute2", lvl())
# 3. the keys window: mouse opens and closes it, then MIDI does
#click ^Verdandi.Linux$ 0.645 0.109
#sleep 1.5
#sh "$DC" count km1 '^keys$'
#click ^Verdandi.Linux$ 0.645 0.109
#sleep 1.5
#sh "$DC" count km2 '^keys$'
#sh "$MMS" 90:27:64 80:27:00 > "$MARKS.s4" 2>&1
#sleep 1.5
#sh "$DC" count kd1 '^keys$'
#sh "$MMS" 90:27:64 80:27:00 > "$MARKS.s5" 2>&1
#sleep 1.5
#sh "$DC" count kd2 '^keys$'
#xdo search --name ^Verdandi.Linux$ windowfocus
# 4. the row of buttons hidden: MUTE by MIDI still works (nothing is drawn for it)
bs.set_show_buttons(false)
#sleep 1
#sh "$MMS" 90:26:64 80:26:00 > "$MARKS.s6" 2>&1
#sleep 1
print("PROBE hidden mute1", lvl())
#sh "$MMS" 90:26:64 80:26:00 > "$MARKS.s7" 2>&1
#sleep 1
print("PROBE hidden mute2", lvl())
bs.set_show_buttons(true)
#sleep 1
# 5. the screenshot action makes a file
#sh echo "shots_before=$(ls "$NORNS_HOME"/dust/Verdandi*.png 2>/dev/null | wc -l)" >> "$MARKS"
#sh "$MMS" 90:28:64 80:28:00 > "$MARKS.s8" 2>&1
#sleep 2
#sh echo "shots_after=$(ls "$NORNS_HOME"/dust/Verdandi*.png 2>/dev/null | wc -l)" >> "$MARKS"
# 6. fullscreen with the screen docked: a message, nothing else
#sh "$MMS" 90:2A:64 80:2A:00 > "$MARKS.s9" 2>&1
#sleep 1
#sh "$DC" count docked_screens '^Verdandi.screen$'
#sh "$DC" alive docked_alive
# 7. the master switch OFF: no action, E2 and K2 still work; Ctrl+Shift+M (norns window) turns it on
mm.set_actions(false)
#sleep 0.5
print("PROBE master off", S.state.actions_on)
#sh "$MMS" 90:25:64 80:25:00 90:26:64 80:26:00 B0:47:01 B0:55:7F B0:55:00 > "$MARKS.s10" 2>&1
#sleep 1.5
print("PROBE off mute", lvl(), st())
#xdo search --name ^Verdandi.Linux$ windowfocus
#xdo key ctrl+shift+m
#sleep 1
print("PROBE shortcut norns", S.state.actions_on)
#sh grep -q '^actions=1' "$NORNS_HOME/midimap.conf" && echo "conf_shortcut_on=yes" >> "$MARKS" || echo "conf_shortcut_on=no" >> "$MARKS"
#sh "$MMS" 90:26:64 80:26:00 > "$MARKS.s11" 2>&1
#sleep 1
print("PROBE on mute", lvl())
#sh "$MMS" 90:26:64 80:26:00 > "$MARKS.s12" 2>&1
#sleep 1
print("PROBE on unmute", lvl())
# 8. detach by MIDI, fullscreen by MIDI (the saved state says it), the shortcut from the screen window, dock by MIDI
#sh "$MMS" 90:29:64 80:29:00 > "$MARKS.s13" 2>&1
#sleep 2
#sh "$DC" count detached_screens '^Verdandi.screen$'
#sh "$MMS" 90:2A:64 80:2A:00 > "$MARKS.s14" 2>&1
#sleep 1.5
#sh "$DC" conf conf_fs_on
#sh "$MMS" 90:2A:64 80:2A:00 > "$MARKS.s15" 2>&1
#sleep 1.5
#sh "$DC" conf conf_fs_off
#xdo search --name ^Verdandi.screen$ windowfocus
#sleep 0.5
#xdo key ctrl+shift+m
#sleep 1
print("PROBE shortcut screen off", S.state.actions_on)
#xdo key ctrl+shift+m
#sleep 1
print("PROBE shortcut screen on", S.state.actions_on)
#sh "$MMS" 90:29:64 80:29:00 > "$MARKS.s16" 2>&1
#sleep 2
#sh "$DC" count redocked_screens '^Verdandi.screen$'
#xdo search --name ^Verdandi.Linux$ windowfocus
# 9. the real capture of the ACTIONS list on the page
_menu.set_mode(true)
_menu.set_page("MIDIMAP")
pg.pos = 13
pg.key(3, 1)
pg.apos = 1
pg.redraw()
#sleep 1
#sh "$DC" cap '^Verdandi.Linux$' "$NORNS_HOME/actions-list.png"
pg.key(2, 1)
pg.key(2, 1)
_menu.set_mode(false)
# 10. the menu item (F10, then the 17th item): ticked now; Return unticks it and says so; the picture of both
#xdo search --name ^Verdandi.Linux$ windowfocus
#xdo key F10
#sleep 0.5
#xdo key Down Down Down Down Down Down Down Down Down Down Down Down Down Down Down Down
#sleep 0.5
#shot @home/menu-on.png
#xdo key Return
#sleep 4.5
print("PROBE menu off", S.state.actions_on)
#sh grep -q '^actions=0' "$NORNS_HOME/midimap.conf" && echo "conf_menu_off=yes" >> "$MARKS" || echo "conf_menu_off=no" >> "$MARKS"
#xdo key F10
#sleep 0.5
#xdo key Down Down Down Down Down Down Down Down Down Down Down Down Down Down Down Down
#sleep 0.5
#shot @home/menu-off.png
#xdo key Escape
#sleep 0.5
print("PROBE actions done")
#xdo key ctrl+q
#sleep 4
