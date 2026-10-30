# MIDI MAP in the real window (run_all.sh, midimap_scenario; docs/port/midi-map-plan.md): a click on E2 in the window while a pick is armed picks it (and does not turn it), a controller playing into Verdandi:midi_in through
# JACK MIDI is learned (CC 71, relative two's complement), then drives E2 for the script, which also receives every message; a CC key presses K2. $MMS is the sender (linux/tests/midimap_send.c). the home has box.conf: pixel, DARK
#sleep 5
norns.script.load("code/probe/window_probe.lua")
#sleep 3
jm = nil for i = 1, 16 do if midi.vports[i].name == "Verdandi JACK in" then jm = midi.connect(i) end end
jm.event = function(d) local m = midi.to_msg(d) print("PROBE script", m.type, m.cc, m.val) end
mm = norns.midimap
S = require "core/midimap_settings"
pg = require "core/menu/midimap"
_menu.set_mode(true)
_menu.set_page("MIDIMAP")
#sleep 1
#shot @home/mm-idle.png
pg.pos = 2
pg.key(3, 1)
#sleep 1
print("PROBE learn state", mm.learn.state)
#shot @home/mm-pick.png
#click Verdandi 0.756 0.592
#sleep 1
print("PROBE picked", mm.learn.state, mm.learn.target)
#shot @home/mm-listen.png
#sh ("$MMS" B0:47:01 B0:47:7F B0:47:01 B0:47:7F B0:47:02 B0:47:7E > "$MARKS.send" 2>&1 &)
#sleep 4
print("PROBE learned", mm.learn.state, S.state.ctl.e2.type, S.state.ctl.e2.num, S.state.ctl.e2.mode, S.state.ctl.e2.dev)
#shot @home/mm-learned.png
_menu.set_mode(false)
#sleep 1
#sh ("$MMS" B0:47:01 B0:47:01 B0:47:7F B0:09:05 > "$MARKS.send2" 2>&1 &)
#sleep 3
S.set("k2", "type", "cc") S.set("k2", "num", 85)
#sh ("$MMS" B0:55:7F B0:55:00 > "$MARKS.send3" 2>&1 &)
#sleep 3
#sh cp "$NORNS_HOME/midimap.conf" "$NORNS_HOME/midimap.after"
print("PROBE midimap done")
#sleep 1
#xdo key ctrl+q
#sleep 3
