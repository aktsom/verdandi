-- script clear and load (lua/core/script.lua, lua/core/engine.lua; KNOWN-ISSUES 29). run from the repo root:
--   NORNS_PLATFORM=linux lua5.3 linux/tests/script_clear_test.lua
-- the owner's report: a script load froze (every process alive) after a failed clear. causes reproduced here with stubs: (1) a load that is still waiting for the engine when the script is changed again left
-- engine.is_loading set, so the next engine.load returned false and nothing ever started; (2) one failing step of a clear (a grid, a hook) stopped the rest of it; (3) mod cleanup hooks ran again after a failed load,
-- against parameters the first clear had removed; (4) nothing said that a load was taking long
package.path = "lua/?.lua;lua/core/?.lua;lua/lib/?.lua;" .. package.path
local fails = 0
local real_print = print
local function check(ok, what) if not ok then fails = fails + 1; real_print("FAIL " .. what) end end
local printed = {}
print = function(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end printed[#printed + 1] = table.concat(t, " ") end
local function logged(part) for _, l in ipairs(printed) do if l:find(part, 1, true) then return true end end return false end
local function count_logged(part) local n = 0 for _, l in ipairs(printed) do if l:find(part, 1, true) then n = n + 1 end end return n end

local tmp = os.tmpname(); os.remove(tmp); os.execute("mkdir -p " .. tmp)
local function script(name, body) local f = io.open(tmp .. "/" .. name .. ".lua", "w") f:write(body) f:close() return tmp .. "/" .. name .. ".lua" end
local good_a = script("a", 'engine.name = "EngA"\ninit = function() INIT_LOG[#INIT_LOG + 1] = "a" end\n')
local good_b = script("b", 'engine.name = "EngB"\ninit = function() INIT_LOG[#INIT_LOG + 1] = "b" end\n')
local bad = script("bad", 'this is not lua\n')

tab = require 'tabutil'
util = {file_exists = function(p) local f = io.open(p, "r") if f then f:close() return true end return false end, make_dir = function() end,
  time = function() return NOW end, clamp = function(x, lo, hi) return math.max(lo, math.min(hi, x)) end, string_starts = function(s, p) return s:sub(1, #p) == p end}
package.loaded.util = util
NOW = 100
INIT_LOG = {}
local calls = {}
local function rec(n) return function(...) calls[#calls + 1] = n end end
_path = {dust = tmp .. "/", code = tmp .. "/", data = tmp .. "/data/"}
_norns = {report = {}, free_engine = rec("free_engine"), load_engine = function(name) calls[#calls + 1] = "load_engine:" .. name end, execute = function() end}
norns = {none = function() end, blank = function() end, enc = {accel = rec("enc.accel"), sens = rec("enc.sens")},
  state = {save = rec("state.save"), resume = function() end}, version = {update = 999}, crow = {init = rec("crow.init")},
  pmap = {clear = rec("pmap.clear"), read = rec("pmap.read")}, menu = {status = function() return false end}, scripterror = function(m) calls[#calls + 1] = "scripterror:" .. tostring(m) end,
  try = function(f, msg) local ok, err = pcall(f) if not ok then print("### " .. msg .. ": " .. tostring(err)) end return ok end,
  init_done = function() end, script = {}}
_norns.screen_save = function() end; _norns.screen_restore = function() end
json, _json = nil, {}
grid = {cleanup = rec("grid.cleanup")}; arc = {cleanup = rec("arc.cleanup")}; midi = {cleanup = rec("midi.cleanup")}; hid = {cleanup = rec("hid.cleanup")}; osc = {cleanup = rec("osc.cleanup")}
local metros = {}
metro = {free_all = function() metros = {} calls[#calls + 1] = "metro.free_all" end,
  init = function(f, t, n) local m = {f = f, t = t, running = false, start = function(self) self.running = true end, stop = function(self) self.running = false end} metros[#metros + 1] = m return m end}
clock = {cleanup = rec("clock.cleanup"), add_params = rec("clock.add_params")}
poll = {clear_all = rec("poll.clear_all")}; softcut = {reset = rec("softcut.reset")}
audio = {routing_is_altered = function() return false end, add_params = rec("audio.add_params")}
keyboard = {clear = rec("keyboard.clear")}; gamepad = {clear = rec("gamepad.clear")}
params = {clear = rec("params.clear"), string = function() return "internal" end, name = nil}
screen = setmetatable({}, {__index = function() return function() end end})
local hook = require 'core/hook'
engine = tab.readonly{table = require 'core/engine', except = {'name'}} -- as lua/core/startup.lua makes it: only `name` can be set
local Script = require 'core/script'
norns.script = Script
local function reset() calls = {}; printed = {}; INIT_LOG = {} end
local function has(name) for _, c in ipairs(calls) do if c == name then return true end end return false end
local function n_calls(name) local n = 0 for _, c in ipairs(calls) do if c == name then n = n + 1 end end return n end

-- ---- a load that is still waiting for the engine when the script is changed again (two quick changes)
Script.load(good_a)
check(n_calls("load_engine:EngA") == 1 and engine.is_loading == true, "script a asked for its engine")
Script.load(good_b) -- the engine of a was never reported: sclang is busy or the report was lost
check(n_calls("load_engine:EngB") == 1, "the second load never asked for its engine: it is stuck behind the first (engine.is_loading stayed set)")
_norns.report.did_engine_load()
check(INIT_LOG[#INIT_LOG] == "b" and engine.is_loading == false, "script b was not started when its engine was reported (" .. tostring(INIT_LOG[#INIT_LOG]) .. ")")
-- a third and a fourth load in quick succession, and the engine loads between them
Script.load(good_a); Script.load(good_b); Script.load(good_a)
_norns.report.did_engine_load()
check(INIT_LOG[#INIT_LOG] == "a" and engine.is_loading == false, "after three quick loads the last script did not start")
check(engine.load("EngB", function() end) == true, "a new engine.load after a clear is refused")
Script.clear()
check(engine.is_loading == false, "a clear leaves a pending engine load behind")

-- ---- a step of the clear that raises does not stop the rest of it, and the next load goes on
reset()
grid.cleanup = function() error("grid cleanup boom") end
local ok = pcall(Script.clear)
check(ok, "a failing grid cleanup stopped the clear")
check(has("arc.cleanup") and has("midi.cleanup") and has("metro.free_all") and has("params.clear") and has("softcut.reset"), "the steps after the failing one did not run")
check(logged("grid cleanup boom"), "the failing step is not in the log")
midi.cleanup = function() error("midi cleanup boom") end
ok = pcall(Script.clear)
check(ok and has("params.clear"), "a failing midi cleanup stopped the clear")
grid.cleanup = rec("grid.cleanup"); midi.cleanup = rec("midi.cleanup")
reset()
Script.load(good_a)
check(has("load_engine:EngA"), "a load after clears with failing steps did not reach the engine")
_norns.report.did_engine_load()

-- ---- mod cleanup hooks: run once for a script that was started, not again for the clear after a failed load
reset()
local hook_runs = 0
hook.script_post_cleanup:register("modx", function() hook_runs = hook_runs + 1 end)
local pre = 0
hook.script_pre_init:register("modx", function() pre = pre + 1 end)
Script.load(good_b)                 -- a is running: its clear runs the hooks once; b starts (pre_init)
_norns.report.did_engine_load()
check(pre >= 1, "pre_init hook did not run")
hook_runs = 0
Script.load(bad)                    -- b is cleared (hooks once); bad fails to load; the clear after the failure has nothing of a mod to clean
check(hook_runs == 1, "the mod cleanup hook ran " .. hook_runs .. " times for a load that failed (wanted 1: the script that was running)")
hook.script_post_cleanup:deregister("modx"); hook.script_pre_init:deregister("modx")
-- a hook that raises does not stop the clear
hook.script_post_cleanup:register("mody", function() error("invalid paramset index: sidv_nb_player_1") end)
Script.load(good_a); _norns.report.did_engine_load()
reset()
ok = pcall(Script.load, good_b)
check(ok and has("load_engine:EngB"), "a mod cleanup hook that raised stopped the load")
check(logged("invalid paramset index"), "the hook's error is not in the log")
hook.script_post_cleanup:deregister("mody")

-- ---- the watchdog: a load that takes more than 15 s says so, once, with what it waits for
reset()
Script.load(good_a)                  -- the engine is never reported
check(Script.load_pending ~= nil and Script.load_pending.engine == "EngA", "the load is not marked as pending")
NOW = NOW + 5; Script.check_load()
check(not logged("taking longer"), "the watchdog spoke after 5 s")
NOW = NOW + 11; Script.check_load()
check(logged("taking longer than 15 s") and logged("EngA"), "no watchdog line after 16 s (" .. table.concat(printed, " | ") .. ")")
local n = count_logged("taking longer")
NOW = NOW + 30; Script.check_load()
check(count_logged("taking longer") == n, "the watchdog line is repeated")
_norns.report.did_engine_load()
check(Script.load_pending == nil, "a finished load is still marked as pending")
check(#metros >= 0, "(metros)")
NOW = NOW + 100; Script.check_load()
check(count_logged("taking longer") == n, "the watchdog spoke after the load finished")
-- a metro runs the check
reset()
Script.load(good_b)
local watch_metro
for _, m in ipairs(metros) do if m.running then watch_metro = m end end
check(watch_metro ~= nil, "no running metro for the watchdog")
NOW = NOW + 20; if watch_metro then watch_metro.f() end
check(logged("taking longer than 15 s"), "the metro did not run the check")
_norns.report.did_engine_load()

-- ---- reports of an engine that was cancelled in the middle (two quick loads): the polls list can have holes; a late report is not run twice
do
  local Poll = require 'core/poll'
  local okp, errp = pcall(Poll.register, {{1, "amp_in_l"}, nil, {3, nil}, {4, "amp_out_l"}}, 4)
  check(okp, "a polls report with holes raised: " .. tostring(errp))
  check(Poll.polls["amp_in_l"] ~= nil and Poll.polls["amp_out_l"] ~= nil, "the good entries of a polls report with holes were not registered")
  reset()
  Script.load(good_a); _norns.report.did_engine_load(); _norns.report.did_engine_load(); _norns.report.did_engine_load()
  local inits = 0 for _, v in ipairs(INIT_LOG) do if v == "a" then inits = inits + 1 end end
  check(inits == 1, "the script's init ran " .. inits .. " times for three reports of one load (late reports of cancelled loads must be ignored)")
end

print = real_print
os.execute("rm -rf '" .. tmp .. "'")
if fails == 0 then print("script clear: all passed") end
os.exit(fails == 0 and 0 or 1)
