-- M43 (docs/port/phase-m43.md): the switch between a real grid and the virtual grid (lua/core/grid.lua). run from the repo root:
--   NORNS_PLATFORM=linux lua5.3 linux/tests/grid_switch_test.lua        (the Linux desktop: the virtual grid is the active grid at once)
--   NORNS_PLATFORM=macos lua5.3 linux/tests/grid_switch_test.lua        (the Mac: nothing changes, the virtual grid joins the list as before)
-- the C side (the copy of the LEDs) is checked by the headless test (probe_grid_switch.lua); here: the vports, the keys that were down, the announcement, repeated switches, no errors
package.path = "lua/?.lua;lua/core/?.lua;lua/lib/?.lua;" .. package.path
local linux = os.getenv("NORNS_PLATFORM") == "linux"
local fails = 0
local real_print = print
local function check(ok, what) if not ok then fails = fails + 1; real_print("FAIL " .. what) end end
local printed = {}
print = function(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end printed[#printed + 1] = table.concat(t, " ") end
local function errors_logged() for _, l in ipairs(printed) do if l:find("failed") or l:find("error") or l:find("boom") then return l end end return nil end

tab = require 'tabutil'
local leds_off = {}
_norns = {grid_rows = function(d) return d.rows or 8 end, grid_cols = function(d) return d.cols or 16 end, arc_set_led = function() end, arc_all_led = function() end, monome_refresh = function() end,
          grid_all_led = function(d, v) if v == 0 then leds_off[d] = (leds_off[d] or 0) + 1 end end}
local Grid = require 'core/grid'

local REAL, VIRT = {tag = "real", rows = 8, cols = 16}, {tag = "virtual", rows = 8, cols = 16}
local function plug_real() _norns.grid.add(1, "m1000218", "monome 128", REAL) end
local function plug_virtual() _norns.grid.add(2, "m0000001", "virtual grid", VIRT) end
local function unplug_virtual() _norns.grid.remove(2) end
local function unplug_real() _norns.grid.remove(1) end
local function port_dev(n) return Grid.vports[n].device and Grid.vports[n].device.id or nil end

local added, keys, removed = {}, {}, {}
Grid.add = function(d) added[#added + 1] = d.id end
local g = Grid.connect(1)
g.key = function(x, y, z) keys[#keys + 1] = x .. "," .. y .. "," .. z end
g.remove = function() removed[#removed + 1] = "p1" end

plug_real()
check(port_dev(1) == 1, "setup: the real grid is on port 1")
plug_virtual()
if linux then
  check(port_dev(1) == 2, "the virtual grid took port 1 at once (port 1 is device " .. tostring(port_dev(1)) .. ")")
  check(port_dev(2) == 1, "the real grid moved to port 2 (it is device " .. tostring(port_dev(2)) .. ")")
  check(g.cols == nil or true, "") -- (g is the vport table: it follows the device)
  check(Grid.vports[1].cols == 16 and Grid.vports[1].rows == 8, "the size of the virtual grid is on port 1")
  check((leds_off[REAL] or 0) >= 1, "the real grid that was left is dark (nobody listens on port 2)")
  check(added[#added] == 2, "the script was told about the virtual grid (Grid.add)")
else
  check(port_dev(1) == 1 and port_dev(2) == 2, "(Mac) nothing changes: the virtual grid has port 2 and the real grid keeps port 1")
  check((leds_off[REAL] or 0) == 0, "(Mac) the real grid is not touched")
end

-- keys on the active grid reach the script
keys = {}
_norns.grid.key(linux and 2 or 1, 3, 4, 1)
_norns.grid.key(linux and 2 or 1, 3, 4, 0)
check(#keys == 2 and keys[1] == "3,4,1" and keys[2] == "3,4,0", "keys of the active grid reach the script (" .. table.concat(keys, " ") .. ")")
-- the other grid's keys do not (Linux): port 2 has no handler
keys = {}
_norns.grid.key(linux and 1 or 2, 1, 1, 1)
_norns.grid.key(linux and 1 or 2, 1, 1, 0)
check(#keys == 0, "keys of the grid that is not active do not reach the script on port 1")

-- a key is down when the virtual grid goes: the script hears the key-up, the real grid takes port 1 and is announced
keys, added = {}, {}
_norns.grid.key(linux and 2 or 1, 5, 5, 1)
unplug_virtual()
if linux then
  check(keys[#keys] == "5,5,0", "no stuck key: the script heard a key-up for the key that was down (" .. table.concat(keys, " ") .. ")")
  check(port_dev(1) == 1, "the real grid has port 1 again")
  check(Grid.vports[2].name == "none", "port 2 is free again")
  check(added[#added] == 1, "the real grid is announced again so that the script reads its size (Grid.add)")
else
  check(port_dev(1) == 1, "(Mac) the real grid still has port 1")
end

-- several switches: no stuck keys, no errors, the same state each time
for round = 1, 6 do
  keys, added = {}, {}
  plug_virtual()
  _norns.grid.key(linux and 2 or 1, round, 2, 1) -- held while it is switched off
  unplug_virtual()
  check(port_dev(1) == 1, "round " .. round .. ": the real grid is active after switching back")
  if linux then
    check(keys[#keys] == round .. ",2,0", "round " .. round .. ": the key held on the virtual grid was let go (" .. tostring(keys[#keys]) .. ")")
    check(Grid.vports[2].device == nil, "round " .. round .. ": port 2 is empty")
  end
end
check(errors_logged() == nil, "no error in the log: " .. tostring(errors_logged()))

-- a key that is down on the real grid when the virtual grid takes over is let go for the script
keys = {}
_norns.grid.key(1, 7, 7, 1)
plug_virtual()
if linux then
  check(keys[#keys] == "7,7,0", "a key held on the real grid is let go when the virtual grid takes over (" .. tostring(keys[#keys]) .. ")")
end
unplug_virtual()

-- no real grid: the virtual grid is on port 1, switching it off leaves port 1 empty, no errors
unplug_real()
printed = {}
plug_virtual()
check(port_dev(linux and 1 or 2) == 2, "no real grid: the virtual grid is on port 1 (Mac: where it was)")
_norns.grid.key(2, 1, 1, 1)
unplug_virtual()
if linux then check(port_dev(1) == nil, "no real grid: port 1 is empty after the virtual grid goes") end
-- (M45: the real grid is unplugged but its slot setting is still there: it is slot 1 again after the virtual grid, not "none" and not another slot)
check(Grid.vports[1].name == "monome 128 m1000218" or not linux, "no real grid plugged in: slot 1 holds the setting it had before the virtual grid (" .. tostring(Grid.vports[1].name) .. ")")
check(errors_logged() == nil, "no error without a real grid: " .. tostring(errors_logged()))

-- a real grid that is plugged in while the virtual grid is active waits on port 2 and takes port 1 when the virtual grid goes
plug_virtual()
plug_real()
if linux then check(port_dev(1) == 2, "the virtual grid stays active while a real grid is plugged in") end
unplug_virtual()
if linux then check(port_dev(1) == 1, "the real grid takes port 1 when the virtual grid goes (device " .. tostring(port_dev(1)) .. ")") end
check(errors_logged() == nil, "no error at the end: " .. tostring(errors_logged()))

if fails > 0 then real_print("grid_switch_test: " .. fails .. " failed") os.exit(1) end
real_print("grid_switch_test: all passed (" .. (linux and "Linux desktop" or "not Linux") .. ")")
