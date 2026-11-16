-- SYSTEM > AUDIO and ASIO (Windows 0.10.10, docs/port/phase-m19.md): the ASIO build without a usable driver says so (the DRIVER row's help, the status line, a row that cannot be chosen), the normal build says nothing about it,
-- an ASIO driver's buffer sizes (frames and ms) are the BUFFER choices, its channels are the OUT CH / IN CH choices. run from the repo root:   NORNS_PLATFORM=linux lua5.3 linux/tests/audio_asio_page_test.lua
local _print = print
package.path = "lua/?.lua;lua/core/?.lua;lua/lib/?.lua;" .. package.path
local tmp = os.tmpname()
os.remove(tmp)
tmp = "/tmp/apa" .. tmp:match("(%w+)$")
os.execute("mkdir -p " .. tmp)
local real_open, real_remove = io.open, os.remove
local function map(p) return (p:gsub("^/home/we", tmp)) end
io.open = function(p, m) return real_open(map(p), m) end
os.remove = function(p) return real_remove(map(p)) end
local fails = 0
local function check(ok, what) if not ok then fails = fails + 1; _print("FAIL", what) end end

package.loaded.util = {
  clamp = function(x, lo, hi) return math.max(lo, math.min(hi, x)) end,
  file_exists = function(p) local h = real_open(map(p)); if h then h:close() return true end return false end,
  os_capture = function() error("no shell command on Windows") end,
}
util = package.loaded.util

-- the screen: real metrics when we have them, a recording of every text with its level
local W
if os.getenv("FONT_WIDTHS") then
  W = dofile("linux/tests/page_width.lua")
  W.load(os.getenv("FONT_WIDTHS"))
  W.install()
else
  screen = setmetatable({}, {__index = function() return function() end end})
  screen.text_extents = function(s) return #s * 5 end
end
local level, drawn, boxes = 15, {}, {}
local base = {}
for _, k in ipairs({"clear", "text", "text_right", "level", "move", "rect", "fill", "update"}) do base[k] = screen[k] end
screen.clear = function() drawn = {}; boxes = {}; if base.clear then base.clear() end end
screen.level = function(l) level = l end
screen.text = function(s) drawn[#drawn + 1] = {s = s, l = level, right = false}; if base.text then base.text(s) end end
screen.text_right = function(s) drawn[#drawn + 1] = {s = s, l = level, right = true}; if base.text_right then base.text_right(s) end end
screen.move = function(x, y) if base.move then base.move(x, y) end end
screen.rect = function(x, y, w, h) boxes[#boxes + 1] = {x = x, y = y, w = w, h = h}; if base.rect then base.rect(x, y, w, h) end end
screen.fill = function() end
screen.stroke = function() end
screen.line_width = function() end
screen.update = function() end

local selftest_started, selftest
local applied, restarted, redraws = {}, false, 0
local apply_rc, apply_msg = 0, ""
local input_calls = {}
local function mkinfo(t)
  local i = {mode = "device", device = "Speakers (Realtek)", in_device = "", host_api = "Windows WASAPI shared", host_apis = "WASAPI", input = "off", rate = 48000, frames = 128, card_frames = 480,
    out_latency_ms = 21.3, in_latency_ms = 0, block_ms = 2.7, engine_ms = 13.3, total_ms = 34.6, peak_db = -120, measured_ms = -1, in_active = false, note = "", in_note = "", sys_note = "", underruns = 0,
    xruns = 0, exclusive = false, device_rate = 0, engine_lag = 4, lag_raises = 0,
    config = "output=\ninput=\nrate=48000\nblock=128\nbuffer=0\nexclusive=0\nout_first=1\nin_l=1\nin_r=2\n"}
  for k, v in pairs(t or {}) do i[k] = v end
  return i
end
local info = mkinfo()
local DEVS = table.concat({
  "wasapi:Speakers (Realtek High Definition Audio(SST))\tSpeakers (Realtek High Definition Audio(SST)) (default)\t0\t2\tWASAPI\t21\t0\t0",
  "wasapi:Microphone Array (Realtek High Definition Audio(SST))\tMicrophone Array (Realtek High Definition Audio(SST))\t2\t0\tWASAPI\t0\t12\t0",
  "wasapi:Speakers (RME Fireface UC)\tSpeakers (RME Fireface UC)\t0\t2\tWASAPI\t21\t0\t0",
  "wasapi:Line In 1/2 (RME Fireface UC)\tLine In 1/2 (RME Fireface UC)\t8\t0\tWASAPI\t0\t12\t0",
  "wasapi:Speakers (Realtek) [Loopback]\tSpeakers (Realtek) [Loopback]\t2\t0\tWASAPI\t0\t12\t1",
  "asio:ASIO Fireface USB\tASIO Fireface USB\t8\t8\tASIO\t6\t6\t0",
}, "\n") .. "\n"
_norns = {
  restart = function() restarted = true end,
  audio_status = function() return "", "", "" end,
  audio_devices = function() return DEVS end,
  audio_info = function() return info end,
  audio_measure = function() info.measured_ms = -1 end,
  audio_selftest_start = function() selftest_started = (selftest_started or 0) + 1; selftest = {state = 1, verdict = 0} end,
  audio_selftest = function() return selftest end,
  audio_apply = function(text) applied[#applied + 1] = text; if apply_rc == 0 then info.config = text end; return apply_rc, apply_msg end,
}
local page
printed_lines = {}
print = function(...) printed_lines[#printed_lines + 1] = table.concat({...}, " ") end
local timer_running = false
_menu = {timer = {start = function() timer_running = true end, stop = function() timer_running = false end}, redraw = function() redraws = redraws + 1; if page then page.redraw() end end, set_page = function(p) _menu.page = p end, set_input = function(...) input_calls[#input_calls + 1] = {...} end, show_note = function() end}
norns = {none = function() end}

local page
local function setup(dev_lines, t)
  info = mkinfo(t)
  DEVS = table.concat(dev_lines, "\n") .. "\n"
  _norns.audio_devices = function() return DEVS end
  _norns.audio_info = function() return info end
  package.loaded["core/menu/audio"] = nil
  page = dofile("lua/core/menu/audio_win.lua")
  printed_lines = {}
  page.init()
end
local winui = dofile("lua/core/menu/winui.lua")
package.loaded["core/menu/winui"] = winui
local base_devs = {"wasapi:Speakers (RME Fireface UC)\tSpeakers (RME Fireface UC) (default)\t0\t2\tWASAPI\t21\t0\t0"}
local function row_pos(name) local r = page.rows and page.rows() end
local function select_row(n) page.enc(2, -9); page.enc(2, n - 1) end
local function text_of_status() return page.status_text and page.status_text() or "" end
local function help_of(rowno) select_row(rowno); local h = page.help_lines and page.help_lines() or {} return table.concat(h, " ") end

-- 1. the normal build: no ASIO host API and no ASIO in this PortAudio: nothing about ASIO anywhere
setup(base_devs, {asio_flavour = false, asio_note = "this is the normal build: its PortAudio has no ASIO (the ASIO zip has it)", host_apis = "WASAPI"})
check(not (help_of(1)):find("ASIO", 1, true), "the normal build: the DRIVER row says nothing about ASIO")
page.enc(3, 5) page.enc(3, 5)
check(info.mode == "device", "the normal build: stepping past exclusive changes nothing else")

-- 2. the ASIO build, no driver installed
setup(base_devs, {asio_flavour = true, asio_registered = 0, asio_usable = 0, asio_note = "no ASIO driver is installed on this PC: install the ASIO driver of your interface", host_apis = "WASAPI"})
check(page.status_text():find("ASIO", 1, true) ~= nil, "the ASIO build without a driver: the status line says it when the page opens (" .. page.status_text() .. ")")
local help = help_of(1)
check(help:find("ASIO", 1, true) and help:find("no driver installed", 1, true), "... and the DRIVER row's help says why (" .. help .. ")")
select_row(1)
page.enc(3, 1); page.enc(3, 1); page.enc(3, 1) -- normal, exclusive, "low latency: none"
page.redraw()
local txt = {}
for _, d in ipairs(drawn) do txt[#txt + 1] = d.s end
local all = table.concat(txt, " | ")
check(page.status_text():find("ASIO", 1, true) ~= nil, "stepping onto the entry that cannot be chosen repeats the reason on the status line (" .. page.status_text() .. ")")
page.key(3, 1) page.key(3, 0)

-- 3. a driver is registered but does not start
setup(base_devs, {asio_flavour = true, asio_registered = 1, asio_usable = 0, asio_note = "1 ASIO driver found but none starts: the driver refused to start: \"device in use\" (usually another program has the card)", host_apis = "WASAPI"})
check(help_of(1):find("will not start", 1, true) ~= nil, "a driver that does not start: the help says so (" .. help_of(1) .. ")")

-- 4. a working driver: its buffer sizes and channels
local devs4 = {base_devs[1], "asio:ASIO Fireface USB\tASIO Fireface USB\t8\t18\tASIO\t6\t6\t0\t64,2048,256,-1"}
setup(devs4, {asio_flavour = true, asio_registered = 1, asio_usable = 1, asio_note = "1 ASIO driver usable", host_apis = "WASAPI ASIO"})
check(not (help_of(1)):find("none", 1, true), "a working driver: no complaint in the DRIVER help")
select_row(1)
page.enc(3, 1); page.enc(3, 1); page.enc(3, 1) -- low latency
local function find_row(name) for i = 1, 12 do select_row(i); if shown_row == name then return i end end end
-- rows now: DRIVER OUTPUT OUT CH INPUT BUFFER TEST
select_row(3)
local oc = help_of(3)
check(oc:find("18 outputs", 1, true) ~= nil, "OUT CH names the driver's number of outputs (" .. oc .. ")")
select_row(5) -- BUFFER
local bh = help_of(5)
check(bh:find("driver's own sizes", 1, true) ~= nil, "BUFFER says the sizes are the driver's (" .. bh .. ")")
page.redraw()
local lines = {}
for _, d in ipairs(drawn) do lines[#lines + 1] = d.s end
local joined = table.concat(lines, "|")
check(joined:find("auto  256  5.3 ms", 1, true) ~= nil, "BUFFER auto shows the driver's preferred size in frames and ms (" .. joined .. ")")
local seen = {}
for i = 1, 12 do
  page.enc(3, 1)
  page.redraw()
  for _, d in ipairs(drawn) do local f = d.s:match("^(%d+)  [%d%.]+ ms$"); if f then seen[tonumber(f)] = d.s end end
end
local want = {64, 128, 256, 512, 1024, 2048}
for _, f in ipairs(want) do check(seen[f] ~= nil, "BUFFER offers " .. f .. " frames with its ms (" .. tostring(seen[f]) .. ")") end
check(seen[32] == nil and seen[4096] == nil, "and nothing outside the driver's range")
check(seen[128] == "128  2.7 ms", "128 frames are 2.7 ms (" .. tostring(seen[128]) .. ")")

if fails == 0 then _print("audio asio page: all scenarios pass") else _print(fails .. " FAILED") os.exit(1) end
