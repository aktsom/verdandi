-- removing a grid or an arc that no port holds (lua/core/grid.lua, lua/core/arc.lua; KNOWN-ISSUES 28). run from the repo root:
--   NORNS_PLATFORM=linux lua5.3 linux/tests/grid_remove_test.lua
-- upstream's remove handler indexes Grid.vports[g.port]: a device that has no port (a fifth grid, an iii grid, a virtual grid that no vport took) raised "attempt to index a nil value (field '?')", the entry stayed in
-- Grid.devices and a later script clear was left in a state nobody had planned. the device must go in every case, callbacks that raise must not stop it, and one report (a log line) says what was wrong
package.path = "lua/?.lua;lua/core/?.lua;lua/lib/?.lua;" .. package.path
local fails = 0
local real_print = print
local function check(ok, what) if not ok then fails = fails + 1; real_print("FAIL " .. what) end end
local printed = {}
print = function(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end printed[#printed + 1] = table.concat(t, " ") end
local function logged(part) for _, l in ipairs(printed) do if l:find(part, 1, true) then return true end end return false end

tab = require 'tabutil'
_norns = {grid_rows = function() return 8 end, grid_cols = function() return 16 end, arc_set_led = function() end, arc_all_led = function() end, monome_refresh = function() end, grid_all_led = function() end}
local Grid = require 'core/grid'
local Arc = require 'core/arc'

-- six grids: four get a port, two do not
for id = 1, 6 do _norns.grid.add(id, "m" .. id, "monome grid", {}) end
local with_port, without = 0, 0
for _, g in pairs(Grid.devices) do if g.port then with_port = with_port + 1 else without = without + 1 end end
check(with_port == 4 and without == 2, "setup: four grids have a port, two do not (" .. with_port .. ", " .. without .. ")")

local removed = {}
Grid.remove = function(dev) removed[#removed + 1] = dev.id end
for id = 1, 6 do
  local ok, err = pcall(_norns.grid.remove, id)
  check(ok, "removing grid " .. id .. " raised: " .. tostring(err))
  check(Grid.devices[id] == nil, "grid " .. id .. " is still in Grid.devices")
end
check(#removed == 6, "Grid.remove was called for each of the six (" .. #removed .. ")")
check(next(Grid.devices) == nil, "no grid is left")

-- callbacks that raise: the device still goes, the next one too, and the log says what happened
for i = 1, 4 do Grid.vports[i].name = "none" end -- (a vport keeps the name of the grid it had: free them for the next ones)
_norns.grid.add(10, "x10", "monome grid", {}); _norns.grid.add(11, "x11", "monome grid", {})
Grid.remove = function() error("boom in Grid.remove") end
Grid.vports[Grid.devices[10].port].remove = function() error("boom in a vport callback") end
local ok = pcall(_norns.grid.remove, 10)
check(ok, "a raising callback stopped the removal of a grid")
check(Grid.devices[10] == nil, "the grid whose callback raised is still listed")
ok = pcall(_norns.grid.remove, 11)
check(ok and Grid.devices[11] == nil, "the next removal did not work after a raising callback")
check(logged("boom in Grid.remove") and logged("boom in a vport callback"), "the errors of the callbacks are not in the log")
-- a removal of something that is not there
check(pcall(_norns.grid.remove, 99), "removing an unknown grid raised")

-- the same for the arc
for id = 21, 26 do _norns.arc.add(id, "a" .. id, "monome arc", {}) end
local a_without = 0
for _, g in pairs(Arc.devices) do if not g.port then a_without = a_without + 1 end end
check(a_without == 2, "setup: two arcs have no port (" .. a_without .. ")")
Arc.remove = function() end
for id = 21, 26 do
  local ok2, err = pcall(_norns.arc.remove, id)
  check(ok2, "removing arc " .. id .. " raised: " .. tostring(err))
  check(Arc.devices[id] == nil, "arc " .. id .. " is still in Arc.devices")
end
_norns.arc.add(30, "a30", "monome arc", {})
Arc.remove = function() error("boom in Arc.remove") end
check(pcall(_norns.arc.remove, 30) and Arc.devices[30] == nil, "a raising Arc.remove kept the arc listed")

-- SYSTEM > DEVICES lists a grid name once even when two entries have it (KNOWN-ISSUES 31: the same grid twice)
do
  package.loaded['core/keyboard'] = {keymap = {us = {}}, selected_map = "us"}
  midi = {devices = {}}; hid = {devices = {}}
  grid = Grid; arc = Arc
  Grid.devices = {}; Arc.devices = {}
  Grid.devices[1] = {name = "monome 128 m1000218"}; Grid.devices[2] = {name = "monome 128 m1000218"}; Grid.devices[3] = {name = "monome 256 m2000001"}
  local page = dofile("lua/core/menu/devices.lua")
  page.refresh()
  local seen, dup = {}, false
  for _, n in ipairs(page.options.grid) do if seen[n] then dup = true end seen[n] = true end
  check(not dup, "the grid list of SYSTEM > DEVICES has the same name twice: " .. table.concat(page.options.grid, ", "))
  check(#page.options.grid == 3, "the grid list is none and the two grids (" .. #page.options.grid .. ")")
end

-- the monome dispatcher of startup.lua (arc or grid by what is registered)
print = real_print
if fails == 0 then print("grid remove: all passed") end
os.exit(fails == 0 and 0 or 1)
