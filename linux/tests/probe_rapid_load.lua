# quick script changes in the real window (run_all.sh, rapid_scenario; docs/port/KNOWN-ISSUES.md 29): the virtual grid and arc are open, a controller is mapped and playing, and the script is changed again and again before the
# engine of the one before has been reported. the last one must start (it used to stay behind a pending engine load for good: "frozen script load"), nothing may raise in the clear, and the virtual devices stay usable
#sleep 5
_norns.grid_window("grid")
_norns.grid_window("arc")
#sleep 2
S = require "core/midimap_settings"
S.set("e2", "num", 71) S.set("e2", "mode", "rel2c") S.set("k2", "type", "cc") S.set("k2", "num", 85)
norns.midimap.changed()
#sh ("$MMS" B0:47:01 B0:47:01 B0:47:7F B0:55:7F B0:55:00 B0:47:01 B0:47:01 B0:47:01 B0:47:01 B0:47:01 B0:55:7F B0:55:00 > "$MARKS.send" 2>&1 &)
norns.script.load("code/probe/rapid_a.lua")
norns.script.load("code/probe/rapid_b.lua")
norns.script.load("code/probe/rapid_a.lua")
norns.script.load("code/probe/rapid_b.lua")
norns.script.load("code/probe/rapid_a.lua")
#sleep 8
print("PROBE last", engine.is_loading, norns.state.shortname)
# and once more, with the devices going and coming while a load is waiting
_norns.grid_window("grid")
norns.script.load("code/probe/rapid_b.lua")
_norns.grid_window("grid")
norns.script.load("code/probe/rapid_a.lua")
_norns.grid_window("arc")
norns.script.load("code/probe/rapid_b.lua")
_norns.grid_window("arc")
#sleep 8
print("PROBE last2", engine.is_loading, norns.state.shortname)
print("PROBE rapid done")
#xdo key ctrl+q
#sleep 4
