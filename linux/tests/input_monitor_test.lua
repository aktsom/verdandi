-- the input monitor (crone's ADC -> DAC path) per input mode on Linux, from lua/core/menu.lua. run from the repo root:
--   lua5.3 linux/tests/input_monitor_test.lua
-- MIC and OFF hear the monitor; SYS, APP and the optional sink monitor do not (the applications play directly, and the sink
-- monitor contains norns' own output: the monitor on would be a loop)
local src = io.open("lua/core/menu.lua"):read("a")
local block = src:match("(%-%- MIC: what norns' input hears.-)\nhook%.system_post_startup")
assert(block, "input block not found")
local mic_off, kept = os.tmpname(), os.tmpname()
os.remove(mic_off)
os.remove(kept)
block = block:gsub('"/home/we/%.mic%-off"', string.format("%q", mic_off))
block = block:gsub('"/home/we/%.norns%-input"', string.format("%q", kept))

local fails = 0
local function check(cond, what) if not cond then fails = fails + 1; print("FAIL " .. what) end end

local getenv = os.getenv
os.getenv = function(k) if k == "NORNS_SYS_MONITOR" then return "1" end return getenv(k) end

local calls
util = {os_capture = function() return "" end, file_exists = function() return false end}
_norns = {
  mic_input = function(live) calls.mic = live end,
  app_input = function(target) calls.app = target end,
  monitor_out = function(on) calls.monitor = on end,
  set_warning = function(text) calls.warning = text end,
  show_control = function() end,
}
_menu = {}
load(block)()

local function mode(m, bundle)
  calls = {}
  _menu.set_input(m, bundle, bundle, true)
end

mode("mic");     check(calls.monitor == true, "MIC: the monitor is heard")
mode("off");     check(calls.monitor == true, "OFF: the monitor is heard (nothing is in it)")
mode("system");  check(calls.monitor == false, "SYS: the monitor is off (the applications play directly)")
mode("app", "Vivaldi"); check(calls.monitor == false, "APP: the monitor is off")
mode("monitor"); check(calls.monitor == false, "sink monitor: the monitor is off (it contains norns' own output)")
check(calls.app == "sink-monitor", "sink monitor: that is what is tapped")
check(calls.warning and calls.warning:find("feedback"), "sink monitor: the warning is on the device")
mode("mic");     check(calls.monitor == true and calls.mic == true, "back to MIC: the monitor is heard again")

os.remove(mic_off)
os.remove(kept)
print(fails == 0 and "input monitor per mode: all scenarios pass" or (fails .. " failures"))
os.exit(fails == 0)
