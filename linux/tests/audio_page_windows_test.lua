-- SYSTEM > AUDIO in the Windows build (lua/core/menu/audio_win.lua with lua/core/menu/winui.lua; chosen by audio.lua when _norns.audio_devices exists): one short list, E2 selects, E3 changes, every change is applied
-- live (_norns.audio_apply) about a second after the last turn, one status line, TEST results in plain words, nothing wider than the screen (real font metrics when FONT_WIDTHS is set), bright text.
-- run from the repo root:   FONT_WIDTHS=<table from linux/tests/font_widths_dump.c> lua5.3 linux/tests/audio_page_windows_test.lua
package.path = "lua/?.lua;lua/core/?.lua;lua/lib/?.lua;" .. package.path
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
local level, drawn = 15, {}
local base = {}
for _, k in ipairs({"clear", "text", "text_right", "level", "move", "rect", "fill", "update"}) do base[k] = screen[k] end
screen.clear = function() drawn = {}; if base.clear then base.clear() end end
screen.level = function(l) level = l end
screen.text = function(s) drawn[#drawn + 1] = {s = s, l = level, right = false}; if base.text then base.text(s) end end
screen.text_right = function(s) drawn[#drawn + 1] = {s = s, l = level, right = true}; if base.text_right then base.text_right(s) end end
screen.move = function(x, y) if base.move then base.move(x, y) end end
screen.rect = function() end
screen.fill = function() end
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
_menu = {redraw = function() redraws = redraws + 1; if page then page.redraw() end end, set_page = function(p) _menu.page = p end, set_input = function(...) input_calls[#input_calls + 1] = {...} end, show_note = function() end}
norns = {none = function() end}

local winui = dofile("lua/core/menu/winui.lua")
package.loaded["core/menu/winui"] = winui
check(require("core/menu/audio") == require("core/menu/audio_win"), "audio.lua hands the page to audio_win.lua when the program has audio_devices")
package.loaded["core/menu/audio"] = nil
page = dofile("lua/core/menu/audio_win.lua")
local function shown(s) for _, t in ipairs(drawn) do if t.s:find(s, 1, true) then return true end end return false end
local function conf() local h = real_open(tmp .. "/audio.conf"); if not h then return nil end local c = h:read("a"); h:close(); return c end
local function turn(row_pos, delta) page.enc(2, -9); page.enc(2, row_pos - 1); page.enc(3, delta) end
local function ticks(n) for _ = 1, n do page.timer() end end
local function pos_of(name) for i, r in ipairs({"DRIVER", "OUTPUT", "INPUT", "BUFFER", "TEST"}) do if r == name then return i end end end

-- ---- the list ----
page.init(); page.redraw()
check(shown("DRIVER") and shown("OUTPUT") and shown("INPUT") and shown("BUFFER") and shown("TEST"), "the rows are DRIVER, OUTPUT, INPUT, BUFFER, TEST (no APPLY, no RATE, no latency rows)")
check(not shown("APPLY") and not shown("RATE") and not shown("LATENCY") and not shown("MEASURED") and not shown("LEVEL") and not shown("IN L"), "none of the old rows")
check(shown("normal") and shown("default") and shown("auto") and shown("none"), "defaults: normal driver, default output, auto buffer, no input")
check(shown("35 ms  u0 x0"), "ONE short status line with the numbers")
-- unselected rows are bright
local dim = false
for _, t in ipairs(drawn) do if t.l < 11 then dim = true end end
check(not dim, "every text is at level 11 or more (unselected rows 11, the selected row 15)")

-- ---- a change applies by itself, without APPLY and without a restart ----
turn(pos_of("OUTPUT"), 2)
page.redraw()
check(shown("Speakers (RME") or shown("Speakers (Realtek"), "E3 on OUTPUT chooses a device")
check(#applied == 0, "nothing is applied while E3 is still being turned")
ticks(3)
check(#applied == 0, "not before the quiet second")
ticks(2)
check(#applied == 1, "about a second after the last turn the new setting is applied: " .. #applied)
check(applied[1]:find("output=wasapi:Speakers (Realtek High", 1, true) or applied[1]:find("output=wasapi:Speakers (RME", 1, true), "the audio.conf lines go to the program")
check(not restarted, "norns is not restarted")
local c = conf()
check(c and c:find("buffer=auto", 1, true) and c:find("block=128", 1, true) and c:find("in_l=1", 1, true), "audio.conf is written after it worked: " .. tostring(c))
check(page.status and page.status:find("applied", 1, true), "the status line confirms what was applied")
check(#input_calls >= 1 and input_calls[#input_calls][1] == "off", "the input goes OFF after a new device (the MIC button state follows)")

-- ---- a setting that cannot be used: the page goes back and says why in one short line ----
apply_rc, apply_msg = 1, "'Busy Headset' is busy or in use by another program: back to Fake Speakers"
info = mkinfo({config = "output=wasapi:Speakers (RME Fireface UC)\ninput=\nrate=48000\nblock=128\nbuffer=0\nexclusive=0\nout_first=1\nin_l=1\nin_r=2\n"})
page.init()
turn(pos_of("OUTPUT"), -1); ticks(6); page.redraw()
check(shown("busy: another program has it"), "a busy device: one plain line")
check(shown("Speakers (RME"), "and the list shows what runs again")
apply_rc, apply_msg = 0, ""

-- ---- DRIVER ----
page.init()
turn(pos_of("DRIVER"), 1); page.redraw()
check(shown("exclusive"), "E3 on DRIVER: exclusive")
turn(pos_of("DRIVER"), 1); page.redraw()
check(shown("exclusive") and not shown("low latency"), "no low latency driver in a build without ASIO")
ticks(6)
check(applied[#applied]:find("exclusive=1", 1, true), "exclusive=1 goes to the program")
info = mkinfo({host_apis = "WASAPI ASIO"})
page.init()
turn(pos_of("DRIVER"), 2); page.redraw()
check(shown("low latency") and shown("ASIO Fireface USB"), "with ASIO: DRIVER low latency, OUTPUT is the ASIO driver")
check(shown("OUT CH") and shown("1+2"), "and OUT CH appears")
ticks(6)
check(applied[#applied]:find("output=asio:ASIO Fireface USB", 1, true), "the asio: uid is applied")
-- the input of the ASIO driver, and its channels
page.enc(2, -9); page.enc(2, 3); page.enc(3, 1); page.redraw()
check(shown("ASIO Fireface USB") and shown("IN CH"), "INPUT can be the same driver, then IN CH appears")
page.enc(2, 1); page.enc(3, 1); page.redraw()
check(shown("3+4"), "IN CH picks 3+4")
ticks(6)
check(applied[#applied]:find("in_l=3", 1, true) and applied[#applied]:find("in_r=4", 1, true), "in_l=3 in_r=4")

-- ---- BUFFER ----
info = mkinfo()
page.init()
turn(pos_of("BUFFER"), 2); page.redraw()
check(shown("128  2.7 ms"), "BUFFER 128 shows its length")
ticks(6)
check(applied[#applied]:find("buffer=128", 1, true), "buffer=128 is applied")
turn(pos_of("BUFFER"), -9); ticks(6)
check(applied[#applied]:find("buffer=auto", 1, true), "back to auto")

-- ---- TEST: a plain result every time; without an input (or one that did not open) a self-test of the card and the engine, no cables needed ----
local function key_test() page.enc(2, -9); page.enc(2, 9); page.key(3, 1); page.redraw() end
local function finish_selftest(t) selftest = t; ticks(1) end
page.init(); selftest_started = 0; key_test()
check(selftest_started == 1 and shown("testing"), "TEST with no input: the self-test starts (no cables needed) and the row says testing")
finish_selftest({state = 2, verdict = 0, callbacks = 201, avg_ms = 10.0, max_ms = 10.4, expect_ms = 10.0, engine_blocks = 750, late = 0, glitches = 0})
page.redraw()
check(shown("ok") and page.status:find("self-test ok: card calls every 10.0 ms (longest 10.4), engine answered 750 blocks, 0 late, 0 glitches", 1, true), "self-test ok: one sentence with the numbers: " .. tostring(page.status))
check(page.status:find("no input selected", 1, true), "and it says why there was no click test: no input selected")
for _, c in ipairs({{1, "no card", "no sound card is running"}, {2, "no scsynth", "SuperCollider is not attached"}, {3, "card late", "the card calls late"}, {4, "engine late", "the engine was late"}, {5, "glitches", "the card glitched"}}) do
  page.init(); key_test()
  finish_selftest({state = 2, verdict = c[1], callbacks = 100, avg_ms = 10, max_ms = 80, expect_ms = 10, engine_blocks = 5, late = 7, glitches = 3})
  page.redraw()
  check(shown(c[2]) and page.status:find(c[3], 1, true), "self-test verdict " .. c[1] .. ": the row says '" .. c[2] .. "' and the sentence '" .. c[3] .. "': " .. tostring(page.status))
end
info = mkinfo({in_active = true, input = "mic", measured_ms = -1, config = "output=\ninput=wasapi:Line In 1/2 (RME Fireface UC)\nrate=48000\nblock=128\nbuffer=0\nexclusive=0\nout_first=1\nin_l=1\nin_r=2\n"})
page.init(); selftest_started = 0; key_test()
check(selftest_started == 0 and shown("listening"), "TEST with an input that is open: the click test starts (no self-test)")
info.measured_ms = -2; page.redraw()
check(shown("no click heard") and page.status == "no click heard (is an output wired to the input?)", "no click: 'no click heard' and the sentence on the status line")
info.measured_ms = 37.4; page.init(); key_test(); info.measured_ms = 37.4; page.redraw()
check(shown("37 ms"), "a click: the round trip in ms")
info = mkinfo({in_active = false, config = "output=\ninput=wasapi:Line In 1/2 (RME Fireface UC)\nrate=48000\nblock=128\nbuffer=0\nexclusive=0\nout_first=1\nin_l=1\nin_r=2\n"})
page.init(); selftest_started = 0; key_test()
check(selftest_started == 1, "an input that is chosen but not open: the self-test runs")
finish_selftest({state = 2, verdict = 0, callbacks = 201, avg_ms = 10.0, max_ms = 10.4, expect_ms = 10.0, engine_blocks = 750, late = 0, glitches = 0}); page.redraw()
check(page.status:find("did not open", 1, true) and page.status:find("choose it again on INPUT", 1, true), "and the sentence says the input did not open and what to do: " .. tostring(page.status))
page.enc(2, -9); page.enc(2, 2); page.redraw()
check(page.value_text("INPUT"):find("(not open)", 1, true), "the INPUT row itself says '(not open)': " .. page.value_text("INPUT"))
info = mkinfo({mode = "fallback", note = "no sound: audio device is busy"})
page.init(); key_test()
check(shown("no card"), "no card: the row says so at once")

-- ---- the status line says which mode runs ----
info = mkinfo()
page.init(); page.redraw()
check(shown("normal  35 ms  u0 x0"), "the status line starts with the mode: normal")
info = mkinfo({exclusive = true, total_ms = 21.2})
page.init(); page.redraw()
check(shown("exclusive  21 ms  u0 x0"), "exclusive")
info = mkinfo({host_api = "ASIO", device = "ASIO Fireface USB", total_ms = 9.4})
page.init(); page.redraw()
check(shown("ASIO  9 ms"), "ASIO")

-- ---- a help line per row (shown for a few seconds after E2 lands on the row, then the numbers come back) ----
info = mkinfo()
page.init()
local rows_help = {DRIVER = "exclusive", OUTPUT = "wired", INPUT = "MIC button", BUFFER = "auto", TEST = "click"}
for name, word in pairs(rows_help) do
  local h = page.help(name)
  check(h and #h > 20 and #h < 200 and h:find(word, 1, true), "help for " .. name .. " mentions '" .. word .. "': " .. tostring(h))
end
page.enc(2, -9); page.enc(2, 1); page.redraw()
check(page.help_now() and page.help_now():find("wired", 1, true), "moving to OUTPUT shows its help (the pairs may not be wired)")
check(page.status_text():find("wired", 1, true), "on the status line")
ticks(40)
check(not page.help_now(), "after a few seconds the help goes and the numbers come back")

-- ---- every change is confirmed on the status line ----
info = mkinfo()
page.init()
turn(pos_of("BUFFER"), 3); ticks(6)
check(page.status == "BUFFER 256  5.3 ms applied", "BUFFER: the status line says 'BUFFER 256  5.3 ms applied': " .. tostring(page.status))
page.init()
turn(pos_of("OUTPUT"), 2); ticks(6)
check(page.status:find("OUTPUT ", 1, true) == 1 and page.status:find("applied (pairs on the interface may not be wired to anything)", 1, true), "OUTPUT: confirmed, with the help that pairs on the interface may not be wired: " .. tostring(page.status))
page.init()
turn(pos_of("DRIVER"), 1); ticks(6)
check(page.status == "DRIVER exclusive applied", "DRIVER: 'DRIVER exclusive applied': " .. tostring(page.status))
page.init()
page.enc(2, -9); page.enc(2, 2); page.enc(3, 1); ticks(6)
check(page.status:find("INPUT ", 1, true) == 1 and page.status:find(" applied", 1, true), "INPUT: confirmed: " .. tostring(page.status))
-- exclusive refused: the exact reason on the status line
apply_rc = 0
apply_msg = "exclusive mode was refused (Invalid sample rate; the device runs at 44100 Hz, exclusive takes: 44100): normal mode is used"
info = mkinfo()
page.init()
turn(pos_of("DRIVER"), 1); ticks(6)
check(page.status:find("exclusive refused: Invalid sample rate; the device runs at 44100 Hz, exclusive takes: 44100", 1, true), "exclusive refused: the exact reason is on the status line: " .. tostring(page.status))
apply_msg = ""

-- ---- exclusive refused at the start: the reason once in the log, audio.conf says exclusive=0 from then on ----
local f = real_open(tmp .. "/audio.conf", "w") f:write("output=\ninput=\nrate=48000\nblock=128\nbuffer=auto\nexclusive=1\n") f:close()
info = mkinfo({note = "exclusive mode was refused (Invalid sample rate; the device runs at 44100 Hz, exclusive takes: 44100): normal mode is used"})
page.init()
local printed = {}
local real_print = print
print = function(...) printed[#printed + 1] = table.concat({...}, " ") end
check(page.forget_exclusive(info) == true, "forget_exclusive acts when exclusive was asked for and refused")
print = real_print
check(conf() and conf():find("exclusive=0", 1, true) and not conf():find("exclusive=1", 1, true), "audio.conf says exclusive=0 now")
check(#printed == 2 and printed[1]:find("Invalid sample rate", 1, true) and printed[2]:find("exclusive=0", 1, true), "the reason and the change are written to the log once")
check(page.forget_exclusive(info) == false, "and nothing happens a second time")
info = mkinfo()
check(page.forget_exclusive(info) == false, "nothing happens when exclusive was not refused")

-- ---- the card's own rate ----
info = mkinfo({device_rate = 44100})
page.init(); page.redraw()
check(shown("card 44100 Hz"), "the status line shows the card's own rate when it differs from norns's")
info = mkinfo({device_rate = 48000})
page.init(); page.redraw()
check(not shown("card "), "and says nothing when they are the same")
local line = page.log_line(nil)
check(line and line:find("device 48000 Hz", 1, true) and line:find("hold-back", 1, true), "the log line has the device rate and the hold-back: " .. tostring(line))

-- ---- the status line when something is wrong ----
info = mkinfo({mode = "fallback", note = "no sound: audio device 'X' is busy or in use by another program. null audio is used"})
page.init(); page.redraw()
check(shown("no sound: device busy"), "a busy device is said in one line")
info = mkinfo({mode = "null"})
page.init(); page.redraw()
check(shown("null audio (silent)"), "null audio is said")
info = mkinfo({underruns = 3, xruns = 2, total_ms = 41.2})
page.init(); page.redraw()
check(shown("41 ms  u3 x2"), "the numbers: delay, u (scsynth late), x (card glitches)")

-- ---- widths: nothing wider than the screen, at every row, every tick of the marquee, with the longest names ----
local widths_ok, checked = true, 0
if W then
  info = mkinfo({host_apis = "WASAPI ASIO", config = "output=wasapi:Speakers (Realtek High Definition Audio(SST))\ninput=wasapi:Microphone Array (Realtek High Definition Audio(SST))\nrate=48000\nblock=128\nbuffer=0\nexclusive=0\nout_first=1\nin_l=1\nin_r=2\n",
    in_active = true, measured_ms = -2})
  for _, drv in ipairs({0, 1}) do
    page.init()
    if drv == 1 then page.enc(2, -9); page.enc(3, 1) end -- exclusive
    for pos = 1, 7 do
      page.enc(2, -9); page.enc(2, pos - 1)
      page.key(3, 1)
      for t = 0, 70, 3 do
        page.tick = t
        W.clear(); page.redraw()
        checked = checked + 1
        local bad = W.violations()
        if #bad > 0 then widths_ok = false; print("   too wide: " .. table.concat(bad, "; ")) end
      end
    end
  end
  check(widths_ok and checked > 100, "no text wider than the screen or over another, " .. checked .. " views with the longest device names and a running marquee")
end

-- ---- winui ----
check(winui.remap(0) == 0 and winui.remap(1) >= 8 and winui.remap(4) >= 10 and winui.remap(15) == 15, "levels: 0 stays black, dim levels become readable, 15 stays 15")
local seen = {}
local real = screen.level
screen.level = function(l) seen[#seen + 1] = l end
local wrapped = winui.wrap(function() screen.level(4); screen.level(15) end)
wrapped()
check(seen[1] >= 10 and seen[2] == 15 and screen.level ~= nil, "winui.wrap brightens the levels of a page")
local ok = pcall(winui.wrap(function() error("boom") end))
screen.level(1)
check(not ok and seen[#seen] == 1, "and gives screen.level back even when the page fails")
screen.level = real
screen.text_extents = screen.text_extents or function(s) return #s * 5 end
local long = "A very long device name that cannot fit on the screen of a norns"
check(screen.text_extents(winui.fit(long, 80, false, 0)) <= 80 and winui.fit(long, 80, false, 0):sub(-2) == "..", "a long value is cut with ..")
check(winui.fit(long, 80, true, 0):sub(1, 6) == long:sub(1, 6), "the selected row's marquee rests first")
check(winui.fit(long, 80, true, 20) ~= winui.fit(long, 80, true, 0) and screen.text_extents(winui.fit(long, 80, true, 20)) <= 80, "then runs, and always fits")
check(winui.fit("short", 80, true, 50) == "short", "a short value never moves")

os.execute("rm -rf " .. tmp)
print(fails == 0 and "audio page (windows): all scenarios pass" or (fails .. " failures"))
os.exit(fails == 0)
