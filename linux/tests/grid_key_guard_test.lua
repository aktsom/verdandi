-- an error in a script's grid key handler (g.key, or the vport's key) is not only a line in the log: on the desktop it is logged with the traceback, shown on the window for a few seconds (the note of the
-- menu handlers), the other handler of the same press still runs, and norns goes on. on the device the error goes up as before. run from the repo root:
--   NORNS_PLATFORM=linux lua5.3 linux/tests/grid_key_guard_test.lua    (the device case is the same file without NORNS_PLATFORM)
package.path = "lua/?.lua;lua/core/?.lua;lua/lib/?.lua;" .. package.path
local fails = 0
local real_print = print
local function check(ok, what) if not ok then fails = fails + 1; real_print("FAIL " .. what) end end
local desktop = os.getenv("NORNS_PLATFORM") ~= nil
local printed = {}
print = function(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end printed[#printed + 1] = table.concat(t, " ") end
local function logged(part) for _, l in ipairs(printed) do if l:find(part, 1, true) then return true end end return false end

util = dofile("lua/lib/util.lua")
package.loaded.util = util
tab = dofile("lua/lib/tabutil.lua")
local noted = {}
_menu = {handler_error = function(what, err) noted[#noted + 1] = what .. ": " .. tostring(err) end}
_norns = {grid = {}}
local Grid = dofile("lua/core/grid.lua")

local calls = {}
Grid.devices[1] = {port = 1, key = function(x, y, z) calls[#calls + 1] = "device"; error("boom in g.key") end}
Grid.vports[1].key = function(x, y, z) calls[#calls + 1] = "vport" end

local ok, err = pcall(_norns.grid.key, 1, 3, 2, 1)
if desktop then
  check(ok, "desktop: the error does not go up to the caller (norns goes on): " .. tostring(err))
  check(#noted == 1 and noted[1]:find("grid key", 1, true) and noted[1]:find("boom in g.key", 1, true), "it is reported to the menu (the note on the window): " .. tostring(noted[1]))
  check(logged("grid key handler error") and logged("boom in g.key") and logged("stack traceback"), "it is logged, with the traceback")
  check(calls[1] == "device" and calls[2] == "vport", "the vport's handler of the same press still ran")
  -- an error in the vport's handler
  calls, noted = {}, {}
  Grid.devices[1].key = function() calls[#calls + 1] = "device" end
  Grid.vports[1].key = function() error("boom in vport key") end
  check(pcall(_norns.grid.key, 1, 1, 1, 0) and #noted == 1 and noted[1]:find("boom in vport key", 1, true), "an error in the vport's handler too")
  -- no error: nothing is said
  calls, noted, printed = {}, {}, {}
  Grid.vports[1].key = function() calls[#calls + 1] = "vport" end
  check(pcall(_norns.grid.key, 1, 1, 1, 1) and #noted == 0 and not logged("handler error") and calls[1] == "device" and calls[2] == "vport", "a good press says nothing")
  -- an unknown grid is still an error of norns's own (as before)
  check(not pcall(_norns.grid.key, 99, 1, 1, 1), "a press for a grid that is not listed is still an error")
else
  check(not ok and tostring(err):find("boom in g.key", 1, true), "device: the error goes up as before")
  check(#noted == 0, "device: nothing is reported to the menu")
  check(calls[1] == "device" and calls[2] == nil, "device: as before, the vport's handler did not run after it")
end

print = real_print
if fails == 0 then print("grid_key_guard_test: all passed") end
os.exit(fails == 0 and 0 or 1)
