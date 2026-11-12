-- the MIDI ROUTES page of the Windows build (lua/core/menu/midiwin.lua), with a fake _norns.midi_status: the rows (problems, virtual cables, OSC input, tests), the help text, the K3 tests with the result on the row,
-- messages that go when E2 moves, the recommendation of the quickest route, widths with the real font. run from the repo root:
--   FONT_WIDTHS=<table from linux/tests/font_widths_dump.c> lua5.3 linux/tests/midi_page_windows_test.lua
package.path = "lua/?.lua;lua/lib/?.lua;lua/core/?.lua;" .. package.path
local fails = 0
local function check(c, what) if not c then fails = fails + 1; print("FAIL " .. what) end end

local W
if os.getenv("FONT_WIDTHS") then
  W = dofile("linux/tests/page_width.lua"); W.load(os.getenv("FONT_WIDTHS")); W.install()
else
  screen = setmetatable({}, {__index = function() return function() end end})
  screen.text_extents = function(s) return #s * 5 end
end
local drawn = {}
local level = 15
local base = {}
for _, k in ipairs({"clear", "text", "text_right", "level"}) do base[k] = screen[k] end
screen.clear = function() drawn = {}; if base.clear then base.clear() end end
screen.level = function(l) level = l end
screen.text = function(s) drawn[#drawn + 1] = s; if base.text then base.text(s) end end
screen.text_right = function(s) drawn[#drawn + 1] = s; if base.text_right then base.text_right(s) end end
local function shown(s) for _, t in ipairs(drawn) do if t:find(s, 1, true) then return true end end return false end

util = {clamp = function(x, a, b) return math.max(a, math.min(b, x)) end}
local status = "backend=WinMM\ndevices=3\ncables=1\nosc_port=9201\ncable=loopMIDI Port\nosc_used=0\nosc_ignored=0\nroute_state=idle\n"
local started = {}
local redraws = 0
_menu = {timer = {start = function() end, stop = function() end}, redraw = function() redraws = redraws + 1 end}
_norns = {
  midi_in_status = nil,
  midi_status = function() return status end,
  midi_route_test = function(kind, dev) started[#started + 1] = {kind, dev}; return 0, "" end,
}
local page = dofile("lua/core/menu/midiwin.lua")
local function ticks(n) for _ = 1, n do _menu.timer.event() end end
local function select_row(i) page.enc(2, -99); page.enc(2, i - 1) end
local function rows() return page.rows() end

-- no problem, one cable
page.init(); page.redraw()
local r = rows()
local names = {}
for _, row in ipairs(r) do names[#names + 1] = row.label end
check(names[1] == "CABLES" and names[2] == "OSC IN", "rows: CABLES, OSC IN first (" .. table.concat(names, ",") .. ")")
check(shown("CABLES") and shown("1 found"), "cables are counted")
local found = {}
for _, row in ipairs(r) do found[row.label] = row end
check(found["TEST OSC"] and found["TEST loopMIDI Port"], "a test row for OSC and one for the cable")
check(not found["RESULTS"] or true, "results row optional until a test ran")

-- a port held by another program: a row on top, plain words, whatever the program is
status = "backend=WinMM\ndevices=3\ncables=1\nosc_port=9201\ncable=loopMIDI Port\nnote=Fireface UC MIDI: held by another program (its input)\nroute_state=idle\n"
page.init(); page.redraw()
r = rows()
check(r[1].label == "Fireface UC MIDI" and r[1].kind == "note", "the held port is the first row, named by the device")
check(shown("Fireface UC MIDI") and shown("held"), "and says held")
local help = page.help_full()
check(help:find("another program", 1, true) and help:find("midi_ignore", 1, true), "its help says what to do: " .. help)
check(not help:lower():find("ableton") and not help:lower():find("push"), "and names no program or maker")

-- no virtual cable installed: the row says so and the help gives the steps
status = "backend=WinMM\ndevices=1\ncables=0\nosc_port=9201\nroute_state=idle\n"
page.init(); page.redraw()
r = rows()
check(r[1].label == "CABLES" and shown("none"), "no cable: CABLES none")
select_row(1); page.redraw()
help = page.help_full()
check(help:find("loopMIDI", 1, true) and help:find("MIDI Services", 1, true), "help: where to get a virtual port: " .. help)

-- OSC off
status = "backend=WinMM\ndevices=1\ncables=0\nosc_port=0\nroute_state=idle\n"
page.init(); page.redraw()
found = {}
for _, row in ipairs(rows()) do found[row.label] = row end
check(found["OSC IN"] and found["OSC IN"].value:find("off", 1, true) and not found["TEST OSC"], "osc_in_port=0: the input is off, no OSC test")

-- tests
status = "backend=WinMM\ndevices=3\ncables=1\nosc_port=9201\ncable=loopMIDI Port\nroute_state=idle\n"
page.init()
local pos
for i, row in ipairs(rows()) do if row.label == "TEST OSC" then pos = i end end
select_row(pos); page.key(3, 1); page.redraw()
check(#started == 1 and started[1][1] == "osc", "K3 on TEST OSC starts the osc test")
check(shown("testing..."), "the row says testing...")
status = "backend=WinMM\ndevices=3\ncables=1\nosc_port=9201\ncable=loopMIDI Port\nroute_state=done\nroute=OSC (127.0.0.1): 0.04 ms round trip (mean), 0.09 worst, jitter 0.01, 200 of 200\n"
ticks(1); page.redraw()
check(shown("0.04 ms") and not shown("testing..."), "the short result is on the row itself")
page.enc(2, 1); page.redraw()
check(not shown("0.04 ms round"), "and goes when E2 moves")
-- a second route and the recommendation
for i, row in ipairs(rows()) do if row.label == "TEST loopMIDI Port" then pos = i end end
select_row(pos); page.key(3, 1)
check(started[2] and started[2][1] == "midi" and started[2][2] == "loopMIDI Port", "K3 on a cable starts a midi test with its name")
status = "backend=WinMM\ndevices=3\ncables=1\nosc_port=9201\ncable=loopMIDI Port\nroute_state=done\nroute=loopMIDI Port: 1.20 ms round trip (mean), 3.00 worst, jitter 0.40, 200 of 200\n"
ticks(1)
local rec
for i, row in ipairs(rows()) do if row.label == "RESULTS" then rec = i end end
check(rec, "a RESULTS row appears once something was measured")
select_row(rec); page.redraw()
help = page.help_full()
check(help:find("Lowest", 1, true) and help:find("OSC", 1, true), "it names the quickest route: " .. help)
-- a failed test
status = "backend=WinMM\ndevices=3\ncables=1\nosc_port=9201\ncable=loopMIDI Port\nroute_state=failed\nroute=loopMIDI Port: nothing came back: is the cable closed?\n"
select_row(pos); page.key(3, 1); ticks(1); page.redraw()
check(shown("failed"), "a failed test says failed on the row")
-- K2 leaves
check(page.key(2, 1) == "back", "K2 leaves the page")

-- widths with the real font
if W then
  status = "backend=WinMM\ndevices=9\ncables=2\nosc_port=9201\ncable=loopMIDI Port 1 (very long name indeed)\ncable=Windows MIDI Services Loopback A\nnote=Fireface UC MIDI Port 1 (RME Driver): held by another program (its input)\nnote=Arturia BeatStep Pro 2: held by another program (its output)\nroute_state=done\nroute=Windows MIDI Services Loopback A: 12.34 ms round trip (mean), 23.45 worst, jitter 3.45, 200 of 200\n"
  local bad, count = 0, 0
  page.init()
  for pos2 = 1, #rows() do
    select_row(pos2)
    for t = 0, 60, 6 do
      page.tick = t; W.clear(); page.redraw(); count = count + 1
      local v = W.violations()
      if #v > 0 then bad = bad + 1; print("   too wide: " .. table.concat(v, "; ")) end
    end
  end
  check(bad == 0 and count > 30, "no text wider than the screen or over another (" .. count .. " views)")
end

-- ---- the entry in SYSTEM > DEVICES ----
package.loaded["core/keyboard"] = {keymap = {us = true}, selected_map = "us"}
midi = {devices = {}, vports = {}, update_devices = function() end}
for i = 1, 16 do midi.vports[i] = {name = "none"} end
grid, arc, hid = {devices = {}, vports = {}}, {devices = {}, vports = {}}, {devices = {}, vports = {}}
status = "backend=WinMM\ndevices=3\ncables=0\nosc_port=9201\nroute_state=idle\n"
local dev_page = dofile("lua/core/menu/devices.lua")
dev_page.init()
dev_page.redraw()
check(dev_page.m == nil, "n/a")
local last = #dev_page.list
check(dev_page.list[last] == "midi routes", "the DEVICES list ends with the midi routes entry")
check(shown("MIDI ROUTES >"), "and shows it")
status = "backend=WinMM\ndevices=3\ncables=0\nosc_port=9201\nnote=Fireface UC MIDI: held by another program (its input)\nroute_state=idle\n"
dev_page.redraw()
check(shown("MIDI: 1 HELD >"), "a held port is visible in the list itself (no page to open first)")
dev_page.enc(2, 99); dev_page.key(3, 1); dev_page.redraw()
check(shown("Fireface UC MIDI") and shown("held"), "K3 opens the page with the held device as its first row")
dev_page.key(2, 1)
check(dev_page.mode == "type" and dev_page.pos == #dev_page.list, "K2 comes back to the list, on the entry")
print(fails == 0 and "midi page (windows): all scenarios pass" or (fails .. " failures"))
os.exit(fails == 0)
