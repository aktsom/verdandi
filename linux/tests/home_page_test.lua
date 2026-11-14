-- the HOME page of the menu (lua/core/menu/home.lua) with the globals of a system that has no stat thread: no norns.cpu, no norns.disk, no norns.temp, no wifi (the Windows build 0.10.1 gave
-- "home.lua:55: attempt to index a nil value (field 'cpu')" on K2 and on every redraw), and with the numbers of the Windows stat thread. run from the repo root: lua5.3 linux/tests/home_page_test.lua
package.path = "lua/?.lua;lua/lib/?.lua;lua/core/?.lua;" .. package.path
local fails = 0
local function check(c, what) if not c then fails = fails + 1; print("FAIL " .. what) end end
local drawn = {}
screen = setmetatable({}, {__index = function() return function() end end})
screen.text = function(s) drawn[#drawn + 1] = tostring(s) end
screen.text_right = function(s) drawn[#drawn + 1] = tostring(s) end
screen.clear = function() drawn = {} end
local function shown(s) for _, t in ipairs(drawn) do if t:find(s, 1, true) then return true end end return false end
util = {clamp = function(x, a, b) return math.max(a, math.min(b, x)) end, string_starts = function(s, p) return s:sub(1, #p) == p end}
_menu = {timer = {start = function() end, stop = function() end}, redraw = function() end, draw_panel = function() end, alt = false, showstats = false, set_page = function() end}
_norns = {audio_get_cpu_load = function() return 7.5 end, audio_get_xrun_count = function() return 0 end}
norns = {state = {name = "none"}, version = {update = "0"}, is_norns = false} -- no cpu, no disk, no temp
wifi = nil
local page = dofile("lua/core/menu/home.lua")
local ok, err = pcall(page.redraw)
check(ok, "redraw without stat numbers: " .. tostring(err))
page.key(2, 1)   -- K2: the statistics
check(_menu.showstats == true, "K2 turns the statistics on")
ok, err = pcall(page.redraw)
check(ok, "the statistics without stat numbers: " .. tostring(err))
check(shown("disk 0M") and shown("7%"), "zeros and the audio load are shown")
local temp_drawn = false
for _, t in ipairs(drawn) do if t:match("^%d+c$") then temp_drawn = true end end
check(not temp_drawn, "no temperature is drawn when it is not known")
page.enc(2, 1); page.enc(1, 1); page.enc(3, -1)
page.key(2, 1); page.key(2, 0); page.key(3, 0)
-- with the numbers of the Windows stat thread
norns.disk, norns.temp, norns.cpu_avg, norns.cpu = 123456, 0, 12, {10, 20, 30, 40}
wifi = {state = 0}
_menu.showstats = true
ok, err = pcall(page.redraw)
check(ok, "the statistics with the stat numbers: " .. tostring(err))
check(shown("disk 123456M") and shown("10.") and shown("40."), "the numbers are shown")
-- a system with a temperature (the Raspberry Pi)
norns.temp = 54
page.redraw()
check(shown("54c"), "a known temperature is drawn")
if fails > 0 then print(fails .. " failed"); os.exit(1) end
print("home page: all passed")
