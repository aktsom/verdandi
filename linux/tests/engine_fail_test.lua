-- an engine that fails to build (lua/core/engine_fail.lua, lua/core/script.lua; docs/port/phase-m7.md section 4): a fake engine "Autumn" whose build raises
-- "Message 'ar' not understood" in Engine_Autumn:alloc after "Class Decimator not found" never reports; the load must stop within one tick of the trace
-- reaching logs/sclang.log (not after 15 s), say why in one plain line and on the screen, and leave norns able to load the next script. run from the repo root:
--   NORNS_PLATFORM=linux lua5.3 linux/tests/engine_fail_test.lua
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
_menu = {redraw = function() end}
local EF = require 'core/engine_fail'

-- ---- the parser, on traces as sclang prints them
local TRACE_CLASS = [[
Class Decimator not found
ERROR: Message 'ar' not understood.
RECEIVER: nil
ARGS:
   Instance of Array {    (0x1, gc=00, fmt=01, flg=00, set=01)
     indexed slots:
       0 : Instance of Meta_Decimator
CALL STACK:
	DoesNotUnderstandError:reportError
		arg this = DoesNotUnderstandError
	Nil:handleError
	Object:throw
	Object:doesNotUnderstand
	Engine_Autumn:alloc
	Crone:setEngine
]]
local f = EF.find(TRACE_CLASS, "Autumn")
check(f and f.class == "Decimator" and f.message == "ar", "class and message are read from the trace")
check(f and f.line == "engine Autumn failed: class Decimator is missing; this needs sc3-plugins", "plain line: " .. tostring(f and f.line))
check(f and #f.detail <= 5, "the screen text fits")
for _, l in ipairs(f and f.detail or {}) do check(#l <= 21, "screen line fits 128 px: " .. l) end
check(EF.find(TRACE_CLASS, "Other") == nil, "another engine's trace is not this engine's failure")
check(EF.find(TRACE_CLASS:gsub("Class Decimator not found", "Class 'Decimator' not found"), "Autumn") ~= nil, "quoted class form")
local f2 = EF.find("ERROR: Message 'foo' not understood.\nRECEIVER: nil\nCALL STACK:\n\tObject:doesNotUnderstand\n\tEngine_Autumn:alloc\n", "Autumn")
check(f2 and f2.class == nil and f2.line:find("its code raised an error", 1, true) and f2.line:find("'foo'", 1, true), "no class: the error is named")
local f3 = EF.find("Class 'MiPlaits' not found\nERROR: Message 'ar' not understood.\nCALL STACK:\n\tEngine_Autumn:alloc\n", "Autumn")
check(f3 and f3.line:find("mi-UGens", 1, true), "mi-UGens class names the pack")
check(EF.find("some text mentioning Engine_Autumn:alloc in a plain line", "Autumn") == nil, "no error trace: no failure")
check(EF.find("anything", "None") == nil and EF.find("", "Autumn") == nil, "None and empty")

-- ---- the load: a fake failing engine
local home = tmp .. "/norns-home"
os.execute("mkdir -p " .. home .. "/logs")
local logpath = home .. "/logs/sclang.log"
local function append(text) local h = io.open(logpath, "ab") h:write(text) h:close() end
local lf = io.open(logpath, "wb"); lf:write("old: Class Decimator not found\nERROR: Message 'ar' not understood.\n\tEngine_Autumn:alloc\n"); lf:close() -- an EARLIER failure
_G.__home = home
local real_getenv = os.getenv
os.getenv = function(k) if k == "NORNS_HOME" then return home end return real_getenv(k) end

local autumn = script("autumn", 'engine.name = "Autumn"\ninit = function() INIT_LOG[#INIT_LOG + 1] = "autumn" end\n')
local sent
reset()
NOW = 200
Script.load(autumn)
check(n_calls("load_engine:Autumn") == 1 and engine.is_loading == true, "the failing engine was asked for")
local m = metros[#metros]
check(m and m.t == 1 and m.running, "a one second tick watches the load")
m.f()
check(engine.is_loading == true and not has("scripterror:engine Autumn failed"), "the failure of an earlier start is not this load's")
NOW = 201
append("Class Decimator not found\n")
m.f()
check(engine.is_loading == true, "a missing class alone (no trace of this engine yet) does not stop the load")
append(TRACE_CLASS)
NOW = 202 -- 2 s after the load began, far below the 15 s timeout
m.f()
check(has("scripterror:engine Autumn failed"), "the load was stopped and the error shown (" .. table.concat(calls, ",") .. ")")
check(engine.is_loading == false and Script.load_pending == nil, "no load is pending after the failure")
check(not m.running, "the tick is stopped")
check(logged("engine Autumn failed: class Decimator is missing; this needs sc3-plugins"), "the plain line is in the log")
check(_menu.errordetail and _menu.errordetail[1] == "engine Autumn", "the screen detail is set")
check(#INIT_LOG == 0, "the script's init did not run")
check(n_calls("free_engine") >= 1 or has("free_engine"), "the engine was freed")
m.f() -- a late tick does nothing more
check(count_logged("engine Autumn failed") == 1, "said once")

-- the next script loads
reset()
Script.load(good_a)
check(n_calls("load_engine:EngA") == 1, "the next script asked for its engine")
_norns.report.did_engine_load()
check(INIT_LOG[#INIT_LOG] == "a", "the next script started")

-- an engine named "None" does not watch the log
reset()
local noeng = script("noeng", 'init = function() end\n')
Script.load(noeng)
check(Script.load_pending == nil or Script.load_pending.log == nil, "no engine: nothing to watch")

os.getenv = real_getenv
os.execute("rm -rf " .. tmp)
if fails > 0 then real_print(fails .. " FAILED"); os.exit(1) end
real_print("engine_fail_test: ok")
