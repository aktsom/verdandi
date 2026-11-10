-- SYSTEM > AUDIO in the Windows build (lua/core/menu/audio_win.lua, chosen by audio.lua when _norns.audio_devices exists): devices and host APIs come from the program, the choice is saved in audio.conf
-- (output= input= rate= period= out_first= in_l= in_r=), APPLY restarts, the rows show channels and latency numbers, the bottom line says what runs or why there is no sound. run from the repo root:
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
local restarted, measured = false, false
local function mkinfo(t)
  local i = {mode = "device", device = "Speakers (Realtek)", in_device = "", host_api = "Windows WASAPI shared", host_apis = "WASAPI", input = "off", rate = 48000, frames = 512,
    out_latency_ms = 21.3, in_latency_ms = 0, block_ms = 10.7, engine_ms = 10.7, peak_db = -120, measured_ms = -1, in_active = false, note = "", in_note = "", sys_note = "", underruns = 0}
  for k, v in pairs(t or {}) do i[k] = v end
  return i
end
local info = mkinfo()
local DEVS = table.concat({
  "wasapi:Speakers (Realtek)\tSpeakers (Realtek) (default)\t0\t2\tWASAPI\t21\t0\t0",
  "wasapi:Microphone (Realtek)\tMicrophone (Realtek)\t2\t0\tWASAPI\t0\t12\t0",
  "wasapi:Speakers (Realtek) [Loopback]\tSpeakers (Realtek) [Loopback]\t2\t0\tWASAPI\t0\t12\t1",
  "wasapi:Speakers (RME Fireface UC)\tSpeakers (RME Fireface UC)\t0\t2\tWASAPI\t21\t0\t0",
  "asio:ASIO Fireface USB\tASIO Fireface USB\t8\t8\tASIO\t6\t6\t0",
}, "\n") .. "\n"
_norns = {
  restart = function() restarted = true end,
  audio_status = function() return "", "", "" end,
  audio_devices = function() return DEVS end,
  audio_info = function() return info end,
  audio_measure = function() measured = true end,
}
_menu = {redraw = function() end, set_page = function() end}
norns = {none = function() end}
package.path = "lua/?.lua;" .. package.path
check(require("core/menu/audio") == require("core/menu/audio_win"), "audio.lua hands the page to audio_win.lua when the program has audio_devices")
package.loaded["core/menu/audio"] = nil
local page = dofile("lua/core/menu/audio_win.lua")
local function shown(s) for _, t in ipairs(texts) do if t:find(s, 1, true) then return true end end return false end
local function conf() local h = real_open(tmp .. "/audio.conf"); if not h then return nil end local c = h:read("a"); h:close(); return c end
local ROW = {HOST = 1, OUTPUT = 2, OUTCH = 3, INPUT = 4, INL = 5, INR = 6, RATE = 7, BUFFER = 8, APPLY = 9, TEST = 10, LATENCY = 11, MEASURED = 12, LEVEL = 13}
local function go(row) for _ = 1, 20 do page.enc(2, -1) end for _ = 2, row do page.enc(2, 1) end end
local function write(s) local f = real_open(tmp .. "/audio.conf", "w") f:write(s) f:close() end

page.init(); page.redraw()
check(shown("WASAPI"), "the host row says WASAPI (no ASIO in this build)")
check(shown("default") and shown("512"), "the default block is 512 and the output is the default device")
check(shown("playing: Speakers (Realtek)"), "the bottom line names the device that is playing")
check(shown("48000 Hz  512 frames  under 0"), "the stream, with the underrun count")
go(ROW.HOST); page.enc(3, 1); page.redraw()
check(shown("WASAPI") and not shown("ASIO"), "E3 on HOST cannot choose ASIO when the build has none")
go(ROW.OUTPUT); page.enc(3, 1); page.redraw()
check(shown("Speakers (Realtek) (default)") or shown("Speakers (Realtek)"), "E3 on OUTPUT chooses the first device of the list")
page.enc(3, 1); page.enc(3, 1); page.redraw()
check(shown("RME Fireface"), "and the RME device (WASAPI)")
go(ROW.INPUT); page.redraw()
check(shown("none"), "the input is none until chosen")
page.enc(3, 1); page.redraw()
check(shown("Microphone (Realtek)"), "E3 on INPUT: the first capture device (loopback devices are not offered, SYS is for those)")
page.enc(3, 1); page.redraw()
check(shown("Microphone (Realtek)") and not shown("Loopback"), "no loopback device in the INPUT list")
go(ROW.INR); page.enc(3, 5); page.redraw()
check(shown("2"), "IN R stays within the device's two channels")
go(ROW.RATE); page.enc(3, -1)
go(ROW.BUFFER); page.enc(3, -2); page.redraw()
check(shown("128") or shown("256"), "the block can be made smaller")
go(ROW.APPLY); page.key(3, 1)
local c = conf()
check(c and c:find("output=wasapi:Speakers (RME Fireface UC)", 1, true), "APPLY saves output=<uid>: " .. tostring(c))
check(c and c:find("input=wasapi:Microphone (Realtek)", 1, true) and c:find("in_l=1", 1, true) and c:find("in_r=2", 1, true), "and input= with the channels in_l= in_r=")
check(c and c:find("rate=44100", 1, true) and c:find("period=", 1, true) and c:find("out_first=1", 1, true), "and rate= period= out_first=")
check(restarted, "and restarts norns")

-- the stored choice comes back
restarted = false
page.init(); page.redraw()
check(shown("RME Fireface") and shown("Microphone (Realtek)"), "the saved devices are selected when the page opens again")

-- "default" again: no output= line
page.init()
go(ROW.OUTPUT); page.enc(3, -9); page.redraw()
go(ROW.APPLY); page.key(3, 1)
c = conf()
check(c and not c:find("output=", 1, true) and c:find("rate=", 1, true), "APPLY with default writes no output= line: " .. tostring(c))
restarted = false
-- old files and devices that are gone select default
write("output=\nrate=48000\nperiod=512\n")
page.init(); page.redraw()
check(shown("default"), "an empty output= is default")
write("output=wasapi:Gone Speakers\nrate=48000\nperiod=512\n")
page.init(); page.redraw()
check(shown("default"), "a device that is gone is shown as default (the program says it fell back)")

-- ASIO build: the host row offers ASIO, the device list is the ASIO drivers, channels in pairs, the input is the same driver
info = mkinfo({host_apis = "WASAPI ASIO"})
write("output=asio:ASIO Fireface USB\ninput=asio:ASIO Fireface USB\nrate=48000\nperiod=256\nout_first=3\nin_l=3\nin_r=4\n")
page.init(); page.redraw()
check(shown("ASIO") and shown("ASIO Fireface USB"), "a stored asio: output selects the ASIO host and the driver")
check(shown("3+4"), "OUT CH shows the stored pair 3+4")
go(ROW.INL); page.redraw()
check(shown("3"), "IN L is the stored channel")
go(ROW.OUTPUT); page.enc(3, 5); page.redraw()
check(not shown("RME Fireface"), "the OUTPUT list of the ASIO host has only ASIO drivers")
go(ROW.OUTCH); page.enc(3, 9); page.redraw()
check(shown("7+8"), "OUT CH goes up to the last pair of 8 outputs")
go(ROW.HOST); page.enc(3, -1); page.redraw()
check(shown("WASAPI") and shown("default"), "back to WASAPI: output default, input none")
go(ROW.HOST); page.enc(3, 1); go(ROW.APPLY); page.key(3, 1)
c = conf()
restarted = false

-- the number rows
info = mkinfo({host_apis = "WASAPI ASIO", out_latency_ms = 21.3, in_latency_ms = 12.1, engine_ms = 10.7, in_active = true, input = "mic", peak_db = -18.4, underruns = 3})
write("")
page.init()
go(ROW.LATENCY); page.redraw()
check(shown("out 21 in 12 +11 ms"), "LATENCY: what the driver reports, and the extra block of the bridge")
go(ROW.LEVEL); page.redraw()
check(shown("-18 dB"), "LEVEL shows the input peak")
check(shown("under 3"), "the underrun count is on the page")
info = mkinfo({measured_ms = -1})
go(ROW.MEASURED); page.redraw()
check(shown("press TEST"), "MEASURED before a test")
go(ROW.TEST); page.redraw()
check(shown("click out"), "the TEST row says what it does")
page.key(3, 1)
check(measured, "K3 on TEST starts the measurement")
info = mkinfo({measured_ms = 37.4}); go(ROW.MEASURED); page.redraw()
check(shown("37 ms"), "the measured round trip is shown")
info = mkinfo({measured_ms = -2}); page.redraw()
check(shown("no signal"), "no click heard: said plainly")

-- a fallback: the plain words are on the page
info = mkinfo({mode = "fallback", device = "", host_api = "", note = "no sound: ASIO driver 'ASIO Fireface USB' is busy: another program has it. null audio is used"})
page.init(); page.redraw()
check(shown("device busy"), "a busy device is said on the page")
info = mkinfo({mode = "null", device = "", host_api = ""})
page.init(); page.redraw()
check(shown("null audio (silent)"), "forced null audio is said")
info = mkinfo({note = "ASIO driver 'X' is busy. Using WASAPI instead"})
page.init(); page.redraw()
check(shown("Using WASAPI"), "a replacement (ASIO busy -> WASAPI) is said")

os.execute("rm -rf " .. tmp)
print(fails == 0 and "audio page (windows): all scenarios pass" or (fails .. " failures"))
os.exit(fails == 0)
