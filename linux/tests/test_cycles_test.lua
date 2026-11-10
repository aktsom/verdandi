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
env = {VERDANDI_TEST_CYCLES = "abc"}
check(M.settings() == nil, "a total that is not a number: inactive")

-- startup.lua only arms it when the variable is there
local src = io.open("lua/core/startup.lua"):read("a")
check(src:find('os.getenv("VERDANDI_TEST_CYCLES") and require(\'core/test_cycles\') or nil', 1, true) ~= nil, "startup.lua requires the module only with VERDANDI_TEST_CYCLES")
check(select(2, src:gsub("test_cycles.after_startup", "")) == 2, "and calls it at the end of both start-up handlers")
if fails == 0 then print("test_cycles_test: all passed") end
os.exit(fails == 0 and 0 or 1)
