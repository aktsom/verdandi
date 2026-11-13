-- lua/core/test_cycles.lua (the start/restart cycle test of the Windows CI): inactive without VERDANDI_TEST_CYCLES; with it a restart is asked for after the start-up until the start number (VERDANDI_ROUND) reaches
-- the total, then a shutdown. run from the repo root:  lua5.3 linux/tests/test_cycles_test.lua
package.path = "lua/?.lua;lua/core/?.lua;" .. package.path
local fails = 0
local function check(ok, what) if not ok then fails = fails + 1; print("FAIL " .. what) end end

local env = {}
local getenv = os.getenv
os.getenv = function(k) if env[k] ~= nil then return env[k] end return getenv(k) end
local M = dofile("lua/core/test_cycles.lua")

local calls
local function actions()
  calls = {}
  return {
    sleep = function(s) calls[#calls + 1] = "sleep " .. s end,
    run = function(f) f() end,
    restart = function() calls[#calls + 1] = "restart" end,
    shutdown = function() calls[#calls + 1] = "shutdown" end,
    ui = {}, -- (no settings module: the real one would write ui.conf)
  }
end

env = {}
check(M.settings() == nil, "no VERDANDI_TEST_CYCLES: inactive")
M.after_startup("ok", actions())
check(#calls == 0, "and nothing is done")

env = {VERDANDI_TEST_CYCLES = "3", VERDANDI_ROUND = "1"}
M.after_startup("ok", actions())
check(table.concat(calls, ",") == "sleep 3,restart", "round 1 of 3: wait 3 s, restart (" .. table.concat(calls, ",") .. ")")
env.VERDANDI_ROUND = "2"
M.after_startup("timeout", actions())
check(table.concat(calls, ",") == "sleep 3,restart", "round 2 of 3, start-up timed out: still a restart: the cycle goes on and the failure is in the log")
env.VERDANDI_ROUND = "3"
M.after_startup("ok", actions())
check(table.concat(calls, ",") == "sleep 3,sleep 1,shutdown", "round 3 of 3: shutdown, no restart (" .. table.concat(calls, ",") .. ")")
env = {VERDANDI_TEST_CYCLES = "1"}
M.after_startup("ok", actions())
check(table.concat(calls, ",") == "sleep 3,sleep 1,shutdown", "no round number: it counts as round 1 (of 1: shutdown)")

-- settings that must survive a restart: the value of the round before is read back, the new one saved
local fake_disk = nil
local ui = {state = {}, save = function() fake_disk = nil; return true end}
env = {VERDANDI_TEST_CYCLES = "5", VERDANDI_ROUND = "1"}
local printed = {}
local real_print = print
print = function(l) printed[#printed + 1] = tostring(l) end
local a = actions(); a.ui = ui
M.after_startup("ok", a)
check(printed[2] and printed[2]:find("round=1 first", 1, true) and ui.state.brightness == M.keep_value(1), "round 1: saves its value, nothing to compare")
printed = {}
ui.state.brightness = M.keep_value(1) -- what a restart reads back (the file held it)
env.VERDANDI_ROUND = "2"
a = actions(); a.ui = ui
M.after_startup("ok", a)
check(printed[2] and printed[2]:find("ok=true", 1, true), "round 2: the value of round 1 was read back: " .. tostring(printed[2]))
printed = {}
ui.state.brightness = 1.0 -- a restart that lost the save: the default came back
env.VERDANDI_ROUND = "3"
a = actions(); a.ui = ui
M.after_startup("ok", a)
check(printed[2] and printed[2]:find("ok=false", 1, true), "a lost save is reported as ok=false: " .. tostring(printed[2]))
print = real_print
env = {VERDANDI_TEST_CYCLES = "abc"}
check(M.settings() == nil, "a total that is not a number: inactive")

-- startup.lua only arms it when the variable is there
local src = io.open("lua/core/startup.lua"):read("a")
check(src:find('os.getenv("VERDANDI_TEST_CYCLES") and require(\'core/test_cycles\') or nil', 1, true) ~= nil, "startup.lua requires the module only with VERDANDI_TEST_CYCLES")
check(select(2, src:gsub("test_cycles.after_startup", "")) == 2, "and calls it at the end of both start-up handlers")
-- the simulated script copy (M7 round 4)
do
  local mod = require('core/test_cycles')
  local old = os.getenv
  local printed = {}
  local calls = {}
  local real_print = print
  print = function(...) printed[#printed + 1] = table.concat({...}, " ") end
  os.getenv = function(k) if k == "VERDANDI_TEST_SCRIPT_COPY" then return nil end return old(k) end
  assert(mod.simulate_script_copy(2, function(c) calls[#calls + 1] = c return true end) == nil and #calls == 0, "off: nothing happens")
  os.getenv = function(k) if k == "VERDANDI_TEST_SCRIPT_COPY" then return "1" end return old(k) end
  local line = mod.simulate_script_copy(2, function(c) calls[#calls + 1] = c return true end)
  print = real_print
  os.getenv = old
  assert(line == "VERDANDI_CYCLE_COPY round=2 ok=true", "on: the line says it was done: " .. tostring(line))
  assert(#calls == 1 and calls[1]:find("/home/we/.local/share/SuperCollider/Extensions/mi-UGens-copy", 1, true) and calls[1]:find("mi-UGens/Classes", 1, true), "on: the copy of the classes is made below the per-user folder")
  print("test_cycles script copy: ok")
end

if fails == 0 then print("test_cycles_test: all passed") end
os.exit(fails == 0 and 0 or 1)
