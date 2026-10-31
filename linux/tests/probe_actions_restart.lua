# the restart of actions_scenario (probe_actions.lua left the MIDI actions OFF through the menu): the menu shows OFF without a click, the page row too, and a mapped pad does nothing; the menu item turns it on
#sleep 5
norns.script.load("code/probe/window_probe.lua")
#sleep 3
mm = norns.midimap
S = require "core/midimap_settings"
lvl = function() return tostring(params:get("output_level")) end
print("PROBE restart state", S.state.actions_on, S.state.actions.mute.num)
#xdo search --name ^Verdandi.Linux$ windowfocus
#xdo key F10
#sleep 0.5
#xdo key Down Down Down Down Down Down Down Down Down Down Down Down Down Down Down Down
#sleep 0.5
#shot @home/menu-restart.png
#xdo key Escape
#sleep 0.5
#sh "$MMS" 90:26:64 80:26:00 > "$MARKS.r1" 2>&1
#sleep 1.5
print("PROBE restart pad", lvl())
#xdo key F10
#sleep 0.5
#xdo key Down Down Down Down Down Down Down Down Down Down Down Down Down Down Down Down
#sleep 0.5
#xdo key Return
#sleep 1
print("PROBE restart menu on", S.state.actions_on)
#sh "$MMS" 90:26:64 80:26:00 > "$MARKS.r2" 2>&1
#sleep 1.5
print("PROBE restart pad on", lvl())
print("PROBE actions restart done")
#xdo key ctrl+q
#sleep 4
