-- SYSTEM > AUDIO in the Windows build (lua/core/menu/audio.lua with _norns.audio_devices / _norns.audio_info): the output devices come from the program, the choice is saved in audio.conf
-- (output=, rate=, period=) like on Linux, APPLY restarts, INPUT is read only, the bottom line says which device/rate/latency runs or why there is no sound. run from the repo root:
--   lua5.3 linux/tests/audio_page_windows_test.lua
local tmp = os.tmpname()
os.remove(tmp)
tmp = "/tmp/apw" .. tmp:match("(%w+)$")
os.execute("mkdir -p " .. tmp)
local real_open, real_remove = io.open, os.remove
local function map(p) return (p:gsub("^/home/we", tmp)) end
io.open = function(p, m) return real_open(map(p), m) end
os.remove = function(p) return real_remove(map(p)) end
local fails = 0
local function check(ok, what) if not ok then fails = fails + 1; print("FAIL", what) end end

package.loaded.util = {
  clamp = function(x, lo, hi) return math.max(lo, math.min(hi, x)) end,
  file_exists = function(p) local h = real_open(map(p)); if h then h:close() return true end return false end,
  os_capture = function() error("no shell command on Windows") end,
}
util = package.loaded.util
local texts = {}
screen = {clear = function() texts = {} end, level = function() end, move = function() end, update = function() end,
  text = function(s) texts[#texts + 1] = s end, text_right = function(s) texts[#texts + 1] = s end, text_extents = function(s) return #s * 3 end}
local restarted = false
local info = {mode = "device", device = "Speakers (Realtek)", host_api = "Windows WASAPI shared", rate = 48000, frames = 512, latency_ms = 21.3, note = ""}
_norns = {
  restart = function() restarted = true end,
  audio_status = function() return "", "", "" end,
  audio_devices = function() return "wasapi:Speakers (Realtek)\tSpeakers (Realtek) (default)\t0\t2\nwasapi:USB DAC\tUSB DAC\t0\t2\n" end,
  audio_info = function() return info end,
}
_menu = {redraw = function() end, set_page = function() end}
norns = {none = function() end}
local page = dofile("lua/core/menu/audio.lua")
local function shown(s) for _, t in ipairs(texts) do if t:find(s, 1, true) then return true end end return false end
local function conf() local h = real_open(tmp .. "/audio.conf"); if not h then return nil end local c = h:read("a"); h:close(); return c end
local function go(row) for _ = 1, 10 do page.enc(2, -1) end for _ = 2, row do page.enc(2, 1) end end

page.init(); page.redraw()
check(shown("default") and shown("512"), "the default block is 512 and the output is the default device")
check(shown("playing: Speakers (Realtek)"), "the bottom line names the device that is playing")
go(1); page.enc(3, 1); page.redraw()
check(shown("none yet"), "INPUT cannot be changed (no input from the sound card yet)")
go(2); page.enc(3, 1); page.redraw()
check(shown("Speakers (Realtek) (default)"), "E3 on OUTPUT chooses the first device of the program's list")
page.enc(3, 1); page.redraw()
check(shown("USB DAC"), "and the next one")
go(3); page.enc(3, -1)
go(4); page.enc(3, -2); page.redraw()
check(shown("128") or shown("256"), "the block can be made smaller")
go(5); page.key(3, 1)
local c = conf()
check(c and c:find("output=wasapi:USB DAC", 1, true), "APPLY saves output=<uid> in audio.conf: " .. tostring(c))
check(c and c:find("rate=44100", 1, true) and c:find("period=", 1, true), "and rate= and period=")
check(restarted, "and restarts norns (the launcher starts it again with the new device)")

-- the stored choice comes back
restarted = false
page.init(); page.redraw()
check(shown("USB DAC"), "the saved device is selected when the page opens again")

-- "default" again: APPLY leaves no output= line (the Windows default device is followed), and the page shows "default" after a restart
page.init(); page.redraw()
go(2); page.enc(3, -5); page.redraw()
check(shown("default") and not shown("USB DAC"), "E3 back to the first entry: default")
go(5); page.key(3, 1)
c = conf()
check(c and not c:find("output=", 1, true) and c:find("rate=", 1, true), "APPLY with default writes no output= line: " .. tostring(c))
check(restarted, "and restarts")
restarted = false
page.init(); page.redraw()
check(shown("default"), "the page shows default after a restart")
-- an old file with output= empty or with the name of a device that is gone selects default too
local f = real_open(tmp .. "/audio.conf", "w") f:write("output=\nrate=48000\nperiod=512\n") f:close()
page.init(); page.redraw()
check(shown("default"), "an empty output= is default")
f = real_open(tmp .. "/audio.conf", "w") f:write("output=wasapi:Gone Speakers\nrate=48000\nperiod=512\n") f:close()
page.init(); page.redraw()
check(shown("default"), "a device that is gone is shown as default (the program says it fell back)")

-- a fallback: the plain words are on the page
info = {mode = "fallback", device = "", host_api = "", rate = 48000, frames = 512, latency_ms = 0, note = "no sound: audio device 'USB DAC' is busy or in use by another program. null audio is used"}
page.init(); page.redraw()
check(shown("device busy"), "a busy device is said on the page")
info = {mode = "null", device = "", host_api = "", rate = 48000, frames = 512, latency_ms = 0, note = ""}
page.init(); page.redraw()
check(shown("null audio (silent)"), "forced null audio is said")

os.execute("rm -rf " .. tmp)
print(fails == 0 and "audio page (windows): all scenarios pass" or (fails .. " failures"))
os.exit(fails == 0)
