# the virtual arc from the keyboard and from MIDI in the real window under Xvfb 1280x800 with no window manager (run_all.sh, arc_scenario; docs/port/arc-plan.md): $MMS is the sender (linux/tests/midimap_send.c).
# tier 1: the arc window in front: 5 y shift+g b are ring 1 left, ring 2 right, ring 3 left fine, ring 4 left; tier 2: the norns window in front: 6 and n; a held key repeats; a release steps nothing;
# a click on ring 3 while a learn is armed picks it (the ring does not turn), a CC played through JACK MIDI is learned and then turns ring 3 for the script
#sleep 5
norns.script.load("code/probe/window_probe.lua")
#sleep 3
mm = norns.midimap
S = require "core/midimap_settings"
_norns.grid_window("arc")
#sleep 1.5
#xdo search --name ^arc$ windowfocus
#sleep 0.4
#xdo key 5
#xdo key y
#xdo key shift+g
#xdo key b
#sleep 0.5
print("PROBE tier1 done")
#xdo search --name ^Verdandi.Linux$ windowfocus
#sleep 0.4
#xdo key 6
#xdo key n
#sleep 0.5
print("PROBE tier2 done")
#xdo keydown t
#sleep 1.6
#xdo keyup t
#sleep 0.5
print("PROBE hold done")
#xdo key 1 2
#sleep 0.4
print("PROBE other keys done")
_menu.set_mode(true)
_menu.set_page("MIDIMAP")
#xdo key h
#sleep 0.4
print("PROBE menu keys done")
mm.start_pick()
#sleep 0.5
print("PROBE learn state", mm.learn.state)
#click ^arc$ 0.614 0.5
#sleep 1
print("PROBE picked", mm.learn.state, mm.learn.target)
#sh ("$MMS" B0:4C:41 B0:4C:3F B0:4C:41 B0:4C:3F B0:4C:41 B0:4C:41 > "$MARKS.send" 2>&1 &)
#sleep 4
print("PROBE learned", mm.learn.state, S.state.ctl.a3.type, S.state.ctl.a3.num, S.state.ctl.a3.mode)
_menu.set_mode(false)
#sh ("$MMS" B0:4C:41 B0:4C:3F B0:4C:42 > "$MARKS.send2" 2>&1 &)
#sleep 3
_norns.grid_window("arc")
#sleep 1
#sh ("$MMS" B0:4C:41 > "$MARKS.send3" 2>&1 &)
#sleep 2
print("PROBE arc closed done")
# the WATCH view: a unit that sends 65 and 63 around the middle is offset binary (the capture of the plan)
_menu.set_mode(true)
_menu.set_page("MIDIMAP")
pg = require "core/menu/midimap"
pg.pos = 13
pg.key(3, 1)
#sleep 1
#sh ("$MMS" B0:4C:41 B0:4C:3F B0:4C:41 B0:4C:3F B0:4C:41 B0:4C:41 > "$MARKS.send4" 2>&1 &)
#sleep 3
v = mm.watch_view()
print("PROBE watch", v.cc, v.mode, v.verdict, #v.values)
#shot @home/watch-real.png
pg.key(2, 1)
#sh cp "$NORNS_HOME/midimap.conf" "$NORNS_HOME/midimap.after"
print("PROBE arc done")
#sleep 1
#xdo key ctrl+q
#sleep 3
