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
-- mouse events after the churn: SDL looks up a hint on every click (the crash of KNOWN-ISSUES 28 was in that lookup): clicks on the box, a key, an encoder and the screen
#click ^Verdandi.Linux$ 0.30 0.60
#click ^Verdandi.Linux$ 0.10 0.70
#click ^Verdandi.Linux$ 0.85 0.65
#click ^Verdandi.Linux$ 0.50 0.15 3
#xdo key Escape
#sleep 1
print("PROBE clicks done")
-- a script that kept a removed grid: the call through the stale pointer must not write into freed memory (matron says it is gone and ignores it)
stale = nil
for id, d in pairs(grid.devices) do stale = d.dev end
print("PROBE stale pointer", stale ~= nil)
_norns.grid_window("grid")
#sleep 3
print("PROBE grid devices after close", next(grid.devices) == nil)
_norns.grid_all_led(stale, 0, false)
_norns.grid_set_led(stale, 1, 1, 15, false)
_norns.monome_refresh(stale)
print("PROBE grid rows of a gone grid", _norns.grid_rows(stale))
#sleep 1
print("PROBE rapid done")
#xdo key ctrl+q
#sleep 4
