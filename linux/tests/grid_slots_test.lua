-- M45 (docs/port/phase-m45.md): the virtual grid never moves a real grid's slot for good (lua/core/grid.lua). run from the repo root:
--   NORNS_PLATFORM=linux lua5.3 linux/tests/grid_slots_test.lua     (the Linux desktop)
--   NORNS_PLATFORM=macos lua5.3 linux/tests/grid_slots_test.lua     (the Mac: skipped, nothing changes there)
-- the owner's case first: the real grid is in slot 2 and slot 1 is "none" (a mod takes over the grid that is set in slot 2): the virtual grid takes slot 1, goes again, the real grid stays in slot 2
package.path = "lua/?.lua;lua/core/?.lua;lua/lib/?.lua;" .. package.path
if os.getenv("NORNS_PLATFORM") ~= "linux" then print("grid_slots_test: skipped (not the Linux desktop)") os.exit(0) end
local fails = 0
local real_print = print
local function check(ok, what) if not ok then fails = fails + 1; real_print("FAIL " .. what) end end
local printed = {}
print = function(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end printed[#printed + 1] = table.concat(t, " ") end
tab = require 'tabutil'
local peer_log = {}
_norns = {grid_rows = function(d) return d.rows or 8 end, grid_cols = function(d) return d.cols or 16 end, arc_set_led = function() end, arc_all_led = function() end, monome_refresh = function() end,
          grid_all_led = function() end, grid_peer = function(d) peer_log[#peer_log + 1] = d and d.tag or "nil" end}
local Grid = require 'core/grid'

local R1, R2, V = {tag = "r1", rows = 8, cols = 16}, {tag = "r2", rows = 8, cols = 16}, {tag = "virtual", rows = 8, cols = 16}
local N1, N2, NV = "monome 128 m1", "monome 128 m2", "virtual grid v0"
local function plug(id, serial, name, dev) _norns.grid.add(id, serial, name, dev) end
local function slots() local t = {} for i = 1, 4 do t[i] = Grid.vports[i].name end return table.concat(t, "|") end
local function set_slots(a, b, c, d) -- as the menu does it: names into the slots, then update_devices
  local v = {a, b, c, d}
  for i = 1, 4 do Grid.vports[i].name = v[i] or "none" end
  Grid.update_devices()
end
local function virtual_on() plug(9, "v0", "virtual grid", V) end
local function virtual_off() _norns.grid.remove(9) end
local function reset()
  for id in pairs(Grid.devices) do _norns.grid.remove(id) end
  for i = 1, 4 do Grid.vports[i].name = "none" end
  Grid.switch = nil
  Grid.update_devices()
  printed, peer_log = {}, {}
end
local function persist(i) return Grid.persistent_name and Grid.persistent_name(i) or Grid.vports[i].name end -- (what core/state.lua writes: before M45 the slot name as it is)
local function last_peer() return peer_log[#peer_log] end

-- 1. the owner's case: the real grid in slot 2, slot 1 none. five times on and off
reset()
plug(1, "m1", "monome 128", R1)
set_slots("none", N1)
check(slots() == "none|" .. N1 .. "|none|none", "setup 1: " .. slots())
for round = 1, 5 do
  virtual_on()
  check(slots() == NV .. "|" .. N1 .. "|none|none", "1 on, round " .. round .. ": the virtual grid is in slot 1, the real grid stays in slot 2 (" .. slots() .. ")")
  check(Grid.devices[1].port == 2, "1 on, round " .. round .. ": the real grid is on port 2")
  check(persist(1) == "none" and persist(2) == N1, "1 on, round " .. round .. ": the saved settings have slot 1 none and slot 2 the real grid (" .. persist(1) .. ", " .. persist(2) .. ")")
  check(last_peer() == "nil", "1 on, round " .. round .. ": no real grid hands its LEDs to the virtual grid (the peer is " .. tostring(last_peer()) .. ")")
  virtual_off()
  check(slots() == "none|" .. N1 .. "|none|none", "1 off, round " .. round .. ": only slot 1 is cleared, the real grid is still in slot 2 (" .. slots() .. ")")
  check(Grid.devices[1].port == 2, "1 off, round " .. round .. ": the real grid is on port 2")
  check(last_peer() == "nil", "1 off, round " .. round .. ": no peer (" .. tostring(last_peer()) .. ")")
end

-- 2. the real grid in slot 1: the virtual grid takes slot 1 at once, the real grid goes to the first free slot and comes back to slot 1
reset()
plug(1, "m1", "monome 128", R1)
check(slots() == N1 .. "|none|none|none", "setup 2: " .. slots())
for round = 1, 5 do
  virtual_on()
  check(slots() == NV .. "|" .. N1 .. "|none|none", "2 on, round " .. round .. ": " .. slots())
  check(persist(1) == N1 and persist(2) == "none", "2 on, round " .. round .. ": the saved settings still have the real grid in slot 1 (" .. persist(1) .. ", " .. persist(2) .. ")")
  check(last_peer() == "r1", "2 on, round " .. round .. ": the real grid is the peer of the LED copy (" .. tostring(last_peer()) .. ")")
  virtual_off()
  check(slots() == N1 .. "|none|none|none", "2 off, round " .. round .. ": the real grid is in slot 1 again and slot 2 is none again (" .. slots() .. ")")
  check(Grid.devices[1].port == 1, "2 off, round " .. round .. ": the real grid is on port 1")
  check(last_peer() == "r1", "2 off, round " .. round .. ": the peer is the real grid in slot 1")
end

-- 3. the real grid is unplugged and plugged in again while the virtual grid is on
reset()
plug(1, "m1", "monome 128", R1)
set_slots("none", N1)
virtual_on()
_norns.grid.remove(1)
plug(1, "m1", "monome 128", R1)
check(slots() == NV .. "|" .. N1 .. "|none|none" and Grid.devices[1].port == 2, "3a: replugged while on (it was in slot 2): back in slot 2, not in a new one (" .. slots() .. ")")
virtual_off()
check(slots() == "none|" .. N1 .. "|none|none", "3a: after off: " .. slots())
reset()
plug(1, "m1", "monome 128", R1)
virtual_on()
_norns.grid.remove(1)
plug(1, "m1", "monome 128", R1)
check(slots() == NV .. "|" .. N1 .. "|none|none" and Grid.devices[1].port == 2, "3b: replugged while on (it was in slot 1): in the slot it was pushed to (" .. slots() .. ")")
virtual_off()
check(slots() == N1 .. "|none|none|none" and Grid.devices[1].port == 1, "3b: after off: slot 1 again (" .. slots() .. ")")
-- unplugged while off, plugged in while on
reset()
plug(1, "m1", "monome 128", R1)
set_slots("none", N1)
_norns.grid.remove(1)
virtual_on()
plug(1, "m1", "monome 128", R1)
check(Grid.devices[1].port == 2 and slots() == NV .. "|" .. N1 .. "|none|none", "3c: plugged in while on: its remembered slot 2 (" .. slots() .. ")")
virtual_off()
check(slots() == "none|" .. N1 .. "|none|none", "3c: after off: " .. slots())

-- 4. no real grid at all
reset()
for round = 1, 5 do
  virtual_on()
  check(slots() == NV .. "|none|none|none", "4 on, round " .. round .. ": " .. slots())
  virtual_off()
  check(slots() == "none|none|none|none", "4 off, round " .. round .. ": " .. slots())
end

-- 5. the real grid in slot 3
reset()
plug(1, "m1", "monome 128", R1)
set_slots("none", "none", N1)
for round = 1, 3 do
  virtual_on()
  check(slots() == NV .. "|none|" .. N1 .. "|none" and Grid.devices[1].port == 3, "5 on, round " .. round .. ": the real grid stays in slot 3 (" .. slots() .. ")")
  virtual_off()
  check(slots() == "none|none|" .. N1 .. "|none" and Grid.devices[1].port == 3, "5 off, round " .. round .. ": " .. slots())
end

-- 6. two real grids: one in slot 1, one in slot 2
reset()
plug(1, "m1", "monome 128", R1)
plug(2, "m2", "monome 128", R2)
check(slots() == N1 .. "|" .. N2 .. "|none|none", "setup 6: " .. slots())
for round = 1, 3 do
  virtual_on()
  check(slots() == NV .. "|" .. N2 .. "|" .. N1 .. "|none", "6 on, round " .. round .. ": the grid of slot 1 goes to the first free slot, the other stays (" .. slots() .. ")")
  virtual_off()
  check(slots() == N1 .. "|" .. N2 .. "|none|none", "6 off, round " .. round .. ": " .. slots())
end
-- all slots taken: the pushed-out grid has no port while the virtual grid is on, and is in slot 1 again afterwards
reset()
plug(1, "m1", "monome 128", R1)
set_slots(N1, "other a", "other b", "other c")
virtual_on()
check(slots() == NV .. "|other a|other b|other c" and Grid.devices[1].port == nil, "6b: all slots taken: the real grid has no port while the virtual grid is on (" .. slots() .. ")")
virtual_off()
check(slots() == N1 .. "|other a|other b|other c" and Grid.devices[1].port == 1, "6b: back in slot 1 (" .. slots() .. ")")

-- 7. what the owner sets while the virtual grid is on stays
reset()
plug(1, "m1", "monome 128", R1)
set_slots("none", N1)
virtual_on()
set_slots(NV, "none", "none", N1) -- on SYSTEM > DEVICES > GRID: the real grid to slot 4
virtual_off()
check(slots() == "none|none|none|" .. N1, "7: a slot the owner changed while the virtual grid was on stays as the owner left it (" .. slots() .. ")")

-- 8. the saved settings (core/state.lua) while the virtual grid is on
reset()
plug(1, "m1", "monome 128", R1)
set_slots("none", N1)
virtual_on()
local saved = {}
for i = 1, 4 do saved[i] = persist(i) end
check(table.concat(saved, "|") == "none|" .. N1 .. "|none|none", "8: the file written while the virtual grid is on has the settings the owner chose (" .. table.concat(saved, "|") .. ")")
virtual_off()
-- a file from an older package that has the virtual grid's name in slot 1: it is no setting
reset()
set_slots(NV, N1)
plug(1, "m1", "monome 128", R1)
virtual_on()
check(slots() == NV .. "|" .. N1 .. "|none|none", "8b: a saved virtual-grid name in slot 1 is not kept as the real grid's: " .. slots())
virtual_off()
check(slots() == "none|" .. N1 .. "|none|none", "8b: after off: " .. slots())

-- no error in the log
for _, l in ipairs(printed) do
  if l:find("failed") or l:find("error") or l:find("boom") then check(false, "an error in the log: " .. l) end
end
if fails > 0 then real_print("grid_slots_test: " .. fails .. " failed") os.exit(1) end
real_print("grid_slots_test: all passed (Linux desktop)")
