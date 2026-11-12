-- SYSTEM > AUDIO in the Windows build (lua/core/menu/audio_win.lua with lua/core/menu/winui.lua; chosen by audio.lua when _norns.audio_devices exists): ONE rule: E2 selects a row, E3 CHOOSES a value (the row
-- shows it at once and says 'K3 apply'), K3 APPLIES (the row says 'applying...' and then 'applied'), K2 leaves and never applies; a boxed help of at most 3 lines for the selected row, messages that belong to
-- a row and go when E2 moves, TEST results on the row itself, nothing wider than the screen (real font metrics when FONT_WIDTHS is set), bright text.
-- run from the repo root:   FONT_WIDTHS=<table from linux/tests/font_widths_dump.c> lua5.3 linux/tests/audio_page_windows_test.lua
local _print = print
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

local winui = dofile("lua/core/menu/winui.lua")
package.loaded["core/menu/winui"] = winui
check(require("core/menu/audio") == require("core/menu/audio_win"), "audio.lua hands the page to audio_win.lua when the program has audio_devices")
package.loaded["core/menu/audio"] = nil
page = dofile("lua/core/menu/audio_win.lua")
local function shown(s) for _, t in ipairs(drawn) do if t.s:find(s, 1, true) then return true end end return false end
local function conf() local h = real_open(tmp .. "/audio.conf"); if not h then return nil end local c = h:read("a"); h:close(); return c end
local function select_row(row_pos) page.enc(2, -9); page.enc(2, row_pos - 1) end
local function turn(row_pos, delta) select_row(row_pos); page.enc(3, delta) end
local function ticks(n) for _ = 1, n do _menu.timer.event() end end
local function pos_of(name) for i, r in ipairs({"DRIVER", "OUTPUT", "INPUT", "BUFFER", "TEST"}) do if r == name then return i end end end


local function lines_of_box() -- the help box: the texts drawn inside the box rect at the lower part of the screen
  local out = {}
  for _, t in ipairs(drawn) do if t.box then out[#out + 1] = t.s end end
  return out
end
-- texts drawn after the box rect belong to it: mark them (y of the lines is in the lower part). the recorder has no y, so the page exposes its box lines
local function help_lines() return page.help_lines and page.help_lines() or {} end

-- ---- the list: three rows around the selected one, the help box under them ----
info = mkinfo()
page.init(); page.redraw()
check(shown("DRIVER") and shown("OUTPUT") and shown("INPUT"), "the first three rows are DRIVER, OUTPUT, INPUT")
check(not shown("APPLY") and not shown("RATE") and not shown("LATENCY") and not shown("MEASURED") and not shown("LEVEL") and not shown("IN L"), "none of the old rows")
check(shown("normal") and shown("default") and shown("none"), "defaults: normal driver, default output, no input")
check(shown("normal  35 ms  u0 x0"), "ONE short status line: the mode and the numbers")
local dim = false
for _, t in ipairs(drawn) do if t.l < 11 then dim = true end end
check(not dim, "every text is at level 11 or more")
check(timer_running and _menu.timer.time == 0.25 and _menu.timer.count == -1, "the page uses the menu's own timer (metro 32), not a script metro that a script change could take away")

-- ---- the help box: at most 3 short lines of plain words, for the selected row only, gone when E2 moves ----
local ROWS5 = {"DRIVER", "OUTPUT", "INPUT", "BUFFER", "TEST"}
for i, name in ipairs(ROWS5) do
  select_row(i); page.redraw()
  local h = help_lines()
  check(#h >= 2 and #h <= 3, "help for " .. name .. " has 2 or 3 lines (" .. #h .. ")")
  check(h[1] and h[1]:find(name, 1, true) == 1, "and starts with the name of the row: " .. tostring(h[1]))
  for _, l in ipairs(h) do if screen.text_extents(l) > 118 then check(false, "a help line is wider than the box: " .. l) end end
  check(#boxes >= 1, "a box is drawn for the help of " .. name)
  local others = true
  for j, other in ipairs(ROWS5) do if j ~= i and shown(other .. ": ") then others = false end end
  check(others, "only the help of the selected row (" .. name .. ") is on the screen")
end
info = mkinfo({sys_available = false, sys_reason = "SYS is off: no WASAPI loopback"})
page.init(); select_row(3); page.redraw()
local h3 = help_lines()
check(#h3 == 3 and h3[3]:find("SYS", 1, true) and h3[3]:find("loopback", 1, true), "INPUT help: the third line says SYS is not available and why: " .. tostring(h3[3]))
info = mkinfo({sys_available = true})
page.init(); select_row(3); page.redraw()
check(#help_lines() == 2, "and nothing about SYS when it is there")

-- ---- E3 CHOOSES: the new value is on the row at once, the row says K3 apply, nothing is applied yet ----
info = mkinfo()
page.init(); applied = {}
select_row(2); page.enc(3, 2); page.redraw()
check(shown("K3 apply"), "the row says K3 apply")
check(shown("Speakers (RME") or shown("Speakers (Realtek"), "and shows the chosen device at once")
check(#applied == 0, "nothing is applied by turning E3")
ticks(40)
check(#applied == 0, "not by waiting either (no timer applies anything)")
page.enc(2, 1); page.redraw()
check(#applied == 0 and shown("K3 apply") == true, "not by moving to another row (the choice stays pending, the row still says so)")
page.enc(2, -1)

-- ---- K3 APPLIES: 'applying...', then 'applied' on the row, and the confirmation on the status line ----
local before_rc = apply_rc
page.key(3, 1); page.redraw()
check(#applied == 1, "K3 on a changed row applies (one call to the program)")
check(applied[1]:find("output=wasapi:Speakers", 1, true), "with the audio.conf lines")
check(shown("applied") and not shown("K3 apply"), "the row says applied now")
check(page.status and page.status:find("OUTPUT", 1, true) and page.status:find("applied", 1, true), "and the status line confirms it: " .. tostring(page.status))
local c = conf()
check(c and c:find("buffer=auto", 1, true) and c:find("block=128", 1, true), "audio.conf is written after it worked")
check(#input_calls >= 1 and input_calls[#input_calls][1] == "off", "a new device: the input goes OFF (the MIC button state follows)")
check(not restarted, "norns is not restarted")
page.enc(2, 1); page.redraw()
check(not shown("applied") and page.status == nil, "moving to another row clears the 'applied' mark and the message")

-- ---- leaving never applies ----
info = mkinfo(); page.init(); applied = {}
turn(pos_of("BUFFER"), 2)
page.key(2, 1)
page.deinit()
check(#applied == 0, "K2 (and deinit) leave without applying: nothing was applied")
page.init(); page.redraw()
check(shown("K3 apply") == false, "and the pending choice is gone when the page is opened again")
page.enc(2, -9); page.enc(2, 3); page.redraw()
check(shown("auto"), "BUFFER is back to what runs: auto")

-- ---- 'applying...' is visible while it takes time ----
local seen_applying = false
local real_apply = _norns.audio_apply
_norns.audio_apply = function(text) page.redraw(); seen_applying = shown("applying"); return real_apply(text) end
page.init(); turn(pos_of("BUFFER"), 2); page.key(3, 1)
check(seen_applying, "during the call the row says applying...")
_norns.audio_apply = real_apply

-- ---- a setting that cannot be used: back to what runs, one plain line, no 'applied' ----
apply_rc, apply_msg = 1, "'Busy Headset' is busy or in use by another program: back to Fake Speakers"
info = mkinfo({config = "output=wasapi:Speakers (RME Fireface UC)\ninput=\nrate=48000\nblock=128\nbuffer=0\nexclusive=0\nout_first=1\nin_l=1\nin_r=2\n"})
page.init()
turn(pos_of("OUTPUT"), -1); page.key(3, 1); page.redraw()
check(shown("busy: another program has it"), "a busy device: one plain line")
check(shown("Speakers (RME") and not shown("applied"), "the row shows what runs again and no applied mark")
page.enc(2, 1); page.redraw()
check(not shown("busy: another program has it"), "and the message goes when E2 moves")
apply_rc, apply_msg = 0, ""

-- ---- DRIVER and ASIO ----
info = mkinfo(); page.init()
turn(pos_of("DRIVER"), 1); page.redraw()
check(shown("exclusive") and shown("K3 apply"), "E3 on DRIVER: exclusive, K3 apply")
page.key(3, 1)
check(applied[#applied]:find("exclusive=1", 1, true), "exclusive=1 goes to the program on K3")
info = mkinfo({host_apis = "WASAPI ASIO"}); page.init()
turn(pos_of("DRIVER"), 2); page.redraw()
check(shown("low latency"), "with ASIO: low latency is a DRIVER choice")
page.enc(2, 1); page.redraw()
check(shown("ASIO Fireface USB"), "OUTPUT lists the ASIO driver")
page.enc(2, 1); page.redraw()
check(shown("OUT CH") or shown("K3 apply") or shown("1+2"), "OUT CH appears")
page.key(3, 1)
check(applied[#applied]:find("output=asio:ASIO Fireface USB", 1, true), "the asio: uid is applied")
page.init(); page.enc(2, 9); page.redraw()
check(shown("TEST"), "TEST is the last row")

-- ---- BUFFER ----
info = mkinfo(); page.init()
turn(pos_of("BUFFER"), 2); page.redraw()
check(shown("128  2.7 ms"), "BUFFER 128 shows its length at once")
page.key(3, 1)
check(applied[#applied]:find("buffer=128", 1, true), "buffer=128 is applied by K3")
check(page.status:find("BUFFER 128", 1, true) and page.status:find("applied", 1, true), "and confirmed: " .. tostring(page.status))

-- ---- TEST: 'testing...' on the row, the short result on the row itself, while the row stays selected ----
local function press_test() select_row(5); page.key(3, 1); page.redraw() end
info = mkinfo(); page.init(); selftest_started = 0; printed_lines = {}; press_test()
check(selftest_started == 1 and shown("testing..."), "TEST with no input: the row says testing... at once (self-test, no cables needed)")
selftest = {state = 2, verdict = 0, callbacks = 201, avg_ms = 10.0, max_ms = 10.4, expect_ms = 10.0, engine_blocks = 750, late = 0, glitches = 0}
ticks(1)
check(shown("ok") and not shown("testing..."), "and the short result 'ok' on the row itself, without leaving it")
check(page.status == "self-test ok", "status line: self-test ok")
local d = table.concat(printed_lines, "\n")
check(d:find("self-test ok: card calls every 10.0 ms (longest 10.4), engine answered 750 blocks, 0 late, 0 glitches", 1, true) and d:find("no input selected", 1, true), "details in norns.log")
for _, v in ipairs({{1, "no card", "self-test: no card"}, {2, "no scsynth", "self-test: no scsynth"}, {3, "card late", "self-test: card late"}, {4, "engine late", "self-test: engine late"}, {5, "glitches", "self-test: glitches"}}) do
  page.init(); printed_lines = {}; press_test()
  selftest = {state = 2, verdict = v[1], callbacks = 100, avg_ms = 10, max_ms = 80, expect_ms = 10, engine_blocks = 5, late = 7, glitches = 3}
  ticks(1)
  check(shown(v[2]) and page.status == v[3], "self-test verdict " .. v[1] .. ": '" .. v[2] .. "' on the row, '" .. v[3] .. "' on the status line")
end
info = mkinfo({in_active = true, input = "mic", measured_ms = -1, config = "output=\ninput=wasapi:Line In 1/2 (RME Fireface UC)\nrate=48000\nblock=128\nbuffer=0\nexclusive=0\nout_first=1\nin_l=1\nin_r=2\n"})
page.init(); selftest_started = 0; select_row(6); page.key(3, 1); page.redraw()
check(selftest_started == 0 and shown("listening"), "TEST with an open input: the click test, 'listening...' on the row")
info.measured_ms = -2; ticks(1)
check(shown("no click heard") and page.status == "no click heard (is an output wired to the input?)", "no click: on the row, the sentence on the status line")
info.measured_ms = 37.4; page.init(); select_row(6); page.key(3, 1); info.measured_ms = 37.4; ticks(1)
check(shown("37 ms"), "a click: the round trip in ms on the row")
info = mkinfo({in_active = false, config = "output=\ninput=wasapi:Line In 1/2 (RME Fireface UC)\nrate=48000\nblock=128\nbuffer=0\nexclusive=0\nout_first=1\nin_l=1\nin_r=2\n"})
page.init(); selftest_started = 0; printed_lines = {}; select_row(6); page.key(3, 1)
check(selftest_started == 1, "an input that is chosen but not open: the self-test runs")
selftest = {state = 2, verdict = 0, callbacks = 201, avg_ms = 10.0, max_ms = 10.4, expect_ms = 10.0, engine_blocks = 750, late = 0, glitches = 0}; ticks(1)
check(table.concat(printed_lines, "\n"):find("choose it again on INPUT", 1, true), "and the log says the input did not open and what to do")
select_row(3); page.redraw()
check(page.value_text("INPUT"):find("(not open)", 1, true), "the INPUT row says '(not open)'")
info = mkinfo({mode = "fallback", note = "no sound: audio device is busy"})
page.init(); select_row(5); page.key(3, 1); page.redraw()
check(shown("no card"), "no card: the row says so at once")
-- the result of TEST goes when E2 moves to another row
info = mkinfo(); page.init(); press_test(); selftest = {state = 2, verdict = 0, callbacks = 1, avg_ms = 10, max_ms = 10, expect_ms = 10, engine_blocks = 9, late = 0, glitches = 0}; ticks(1)
page.enc(2, -1); page.enc(2, 1); page.redraw()
check(not shown("self-test ok") and page.status == nil, "moving away clears the status message of TEST")

-- ---- the status line says which mode runs; and the card's own rate ----
info = mkinfo(); page.init(); page.redraw()
check(shown("normal  35 ms  u0 x0"), "normal")
info = mkinfo({exclusive = true, total_ms = 21.2}); page.init(); page.redraw()
check(shown("exclusive  21 ms  u0 x0"), "exclusive")
info = mkinfo({host_api = "ASIO", device = "ASIO Fireface USB", total_ms = 9.4}); page.init(); page.redraw()
check(shown("ASIO  9 ms"), "ASIO")
info = mkinfo({device_rate = 44100}); page.init(); page.redraw()
check(shown("card 44100 Hz"), "the card's own rate when it differs")
info = mkinfo({device_rate = 48000}); page.init(); page.redraw()
check(not shown(" Hz"), "and nothing when it is the same")
local line = page.log_line(nil)
check(line and line:find("device 48000 Hz", 1, true) and line:find("hold-back", 1, true), "the log line has the device rate and the hold-back: " .. tostring(line))
info = mkinfo({mode = "fallback", note = "no sound: audio device 'X' is busy or in use by another program. null audio is used"}); page.init(); page.redraw()
check(shown("no sound: device busy"), "a busy device is said in one line")
info = mkinfo({mode = "null"}); page.init(); page.redraw()
check(shown("null audio (silent)"), "null audio is said")
info = mkinfo({underruns = 3, xruns = 2, total_ms = 41.2}); page.init(); page.redraw()
check(shown("normal  41 ms  u3 x2"), "the numbers: delay, u, x")

-- ---- exclusive refused: the exact reason on the status line (paged), audio.conf stops asking at the start ----
apply_rc = 0
apply_msg = "exclusive mode was refused (Invalid sample rate; the device runs at 44100 Hz, exclusive takes: 44100): normal mode is used"
info = mkinfo(); page.init(); turn(pos_of("DRIVER"), 1); page.key(3, 1)
check(page.status:find("exclusive refused: Invalid sample rate; the device runs at 44100 Hz, exclusive takes: 44100", 1, true), "K3 on exclusive that is refused: the exact reason: " .. tostring(page.status))
apply_msg = ""
local f = real_open(tmp .. "/audio.conf", "w") f:write("output=\ninput=\nrate=48000\nblock=128\nbuffer=auto\nexclusive=1\n") f:close()
info = mkinfo({note = "exclusive mode was refused (Invalid sample rate; the device runs at 44100 Hz, exclusive takes: 44100): normal mode is used"})
page.init(); printed_lines = {}
check(page.forget_exclusive(info) == true, "forget_exclusive acts when exclusive was asked for and refused")
check(conf() and conf():find("exclusive=0", 1, true) and not conf():find("exclusive=1", 1, true), "audio.conf says exclusive=0 now")
check(#printed_lines == 2 and printed_lines[1]:find("Invalid sample rate", 1, true), "and the reason is written once to the log")
check(page.forget_exclusive(info) == false, "nothing happens a second time")

-- ---- widths: nothing wider than the screen, every row, with the longest device names ----
local widths_ok, checked = true, 0
if W then
  info = mkinfo({host_apis = "WASAPI ASIO", config = "output=wasapi:Speakers (Realtek High Definition Audio(SST))\ninput=wasapi:Microphone Array (Realtek High Definition Audio(SST))\nrate=48000\nblock=128\nbuffer=0\nexclusive=0\nout_first=1\nin_l=1\nin_r=2\n",
    in_active = true, measured_ms = -2})
  for _, drv in ipairs({0, 1}) do
    page.init()
    if drv == 1 then page.enc(2, -9); page.enc(3, 1) end
    for pos = 1, 7 do
      page.enc(2, -9); page.enc(2, pos - 1)
      page.key(3, 1)
      for t = 0, 70, 3 do
        page.tick = t
        W.clear(); page.redraw()
        checked = checked + 1
        local bad = W.violations()
        if #bad > 0 then widths_ok = false; _print("   too wide: " .. table.concat(bad, "; ")) end
      end
    end
  end
  check(widths_ok and checked > 100, "no text wider than the screen or over another, " .. checked .. " views with the longest device names (rows, help box, status line, pending marks)")
end

-- ---- winui ----
check(winui.remap(0) == 0 and winui.remap(1) >= 8 and winui.remap(4) >= 10 and winui.remap(15) == 15, "levels: 0 stays black, dim levels become readable, 15 stays 15")
local seen = {}
local real = screen.level
screen.level = function(l) seen[#seen + 1] = l end
winui.wrap(function() screen.level(4); screen.level(15) end)()
check(seen[1] >= 10 and seen[2] == 15, "winui.wrap brightens the levels of a page")
local ok = pcall(winui.wrap(function() error("boom") end))
screen.level(1)
check(not ok and seen[#seen] == 1, "and gives screen.level back even when the page fails")
screen.level = real
local long = "A very long device name that cannot fit on the screen of a norns"
check(screen.text_extents(winui.fit(long, 80, false, 0)) <= 80 and winui.fit(long, 80, false, 0):sub(-2) == "..", "a long value is cut with ..")
check(winui.fit(long, 80, true, 0):sub(1, 6) == long:sub(1, 6), "the selected row's marquee rests first")
check(winui.fit(long, 80, true, 20) ~= winui.fit(long, 80, true, 0) and screen.text_extents(winui.fit(long, 80, true, 20)) <= 80, "then runs, and always fits")
check(winui.fit("short", 80, true, 50) == "short", "a short value never moves")

os.execute("rm -rf " .. tmp)
print = _print
print(fails == 0 and "audio page (windows): all scenarios pass" or (fails .. " failures"))
os.exit(fails == 0)
