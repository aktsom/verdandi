-- the arc keys 5/6 T/Y G/H B/N = encoder 1 to 4 left/right (docs/port/arc-plan.md 3.3, tier 2: the norns window) through the real keyboard module (hardware keys on, as the launcher sets them). run from the repo root:
--   NORNS_PLATFORM=linux NORNS_HARDWARE_KEYS=1 lua5.3 linux/tests/arc_keys_test.lua
-- one press 16 ticks (Shift 4), a repeat repeats, a release is nothing; inactive in the menu, with a text entry open, when a script reads the keyboard, with the arc closed, with ARC KEYS off; the keys of the existing
-- mapping and every other key are not touched
package.path = "lua/?.lua;lua/core/?.lua;lua/lib/?.lua;" .. package.path
local fails = 0
local function check(ok, what) if not ok then fails = fails + 1; print("FAIL " .. what) end end
local function eq(a, b, what) check(a == b, what .. ": got " .. tostring(a) .. ", wanted " .. tostring(b)) end

screen = setmetatable({text_extents = function(t) return #tostring(t) * 5 end}, {__index = function() return function() end end})
local log = {}
local ARC_OPEN = true
_norns = {
  key = function(n, z) log[#log + 1] = "key:" .. n .. ":" .. z end,
  enc = function(n, d) log[#log + 1] = "enc:" .. n .. ":" .. d end,
  show_control = function() end,
  arc_turn = function(n, t) log[#log + 1] = "arc:" .. n .. ":" .. t; return ARC_OPEN end,
}
local MODE = false -- _menu.mode
_menu = {mode = MODE, redraw = function() end, set_page = function() end, set_mode = function() end, goto_panel = function() end, keycode = function() end, keychar = function() end}
_path = {keyboard_layout = "/nonexistent/keyboard.layout"}
util = {clamp = function(x, lo, hi) return math.max(lo, math.min(hi, x)) end}
package.loaded.util = util
local arc_keys, ramp = true, false
norns = {none = function() end, midimap = {arc_keys_on = function() return arc_keys end, arc_keys_ramp = function() return ramp end}}
require 'core/keyboard'
local te_kbd = require 'lib/textentry_kbd'
local function code(name) for k, v in pairs(keyboard.codes) do if v == name then return k end end error("no code " .. name) end
local function send(name, value) keyboard.process(1, code(name), value) end
local function run(fn) log = {}; fn(); return table.concat(log, " ") end
local function reset()
  keyboard.clear()
  log = {}
  _menu.mode = false
  ARC_OPEN, arc_keys, ramp = true, true, false
  keyboard.code, keyboard.char = nil, nil
  te_kbd.code, te_kbd.char = nil, nil
  keyboard.hardware_keys = true
end
local noop = function() end

local KEYS = {["5"] = {1, -1}, ["6"] = {1, 1}, T = {2, -1}, Y = {2, 1}, G = {3, -1}, H = {3, 1}, B = {4, -1}, N = {4, 1}}
local order = {"5", "6", "T", "Y", "G", "H", "B", "N"}

-- ---- every key: a press, a repeat, a release
for _, k in ipairs(order) do
  reset()
  local n, d = KEYS[k][1], KEYS[k][2]
  eq(run(function() send(k, 1) end), "arc:" .. n .. ":" .. d * 16, k .. ": a press is 16 ticks to ring " .. n)
  eq(run(function() send(k, 2) end), "arc:" .. n .. ":" .. d * 16, k .. ": a repeat is 16 ticks again")
  eq(run(function() send(k, 0) end), "", k .. ": a release is nothing (no step, no key, no call)")
  eq(run(function() send(k, 2) end), "", k .. ": a repeat after the release is nothing")
end
-- Shift: a quarter
reset()
send("LEFTSHIFT", 1)
eq(run(function() send("6", 1) end), "arc:1:4", "Shift+6 is 4 ticks"); eq(run(function() send("6", 2) end), "arc:1:4", "a shifted repeat is 4 ticks"); send("6", 0)
eq(run(function() send("T", 1) end), "arc:2:-4", "Shift+T is -4"); send("T", 0)
send("LEFTSHIFT", 0)
eq(run(function() send("6", 1) end), "arc:1:16", "without Shift 16 again"); send("6", 0)
-- a press with Shift, released after Shift: nothing extra; Shift pressed during a hold changes the next repeat
reset()
send("5", 1); send("LEFTSHIFT", 1)
eq(run(function() send("5", 2) end), "arc:1:-4", "Shift pressed during a hold makes the next repeat finer"); send("5", 0); send("LEFTSHIFT", 0)
-- two keys at once
reset()
send("5", 1); send("Y", 1)
eq(run(function() send("5", 2); send("Y", 2) end), "arc:1:-16 arc:2:16", "two held keys repeat independently"); send("5", 0); send("Y", 0)
eq(run(function() send("5", 2); send("Y", 2) end), "", "and stop when released")
-- the ramp (off by default)
reset(); ramp = true
local seq = {}
send("N", 1)
for k = 1, 30 do log = {}; send("N", 2); seq[k] = log[1] end
send("N", 0)
eq(seq[1], "arc:4:16", "ramp: the first repeat is 16"); eq(seq[9], "arc:4:16", "ramp: 9 repeats still 16"); eq(seq[10], "arc:4:32", "ramp: the 10th repeat doubles")
eq(seq[24], "arc:4:32", "ramp: 24"); eq(seq[25], "arc:4:64", "ramp: the 25th is four times"); eq(seq[30], "arc:4:64", "ramp: stays")
reset()
send("N", 1); for k = 1, 30 do send("N", 2) end
eq(run(function() send("N", 2) end), "arc:4:16", "no ramp unless asked: still 16 after 30 repeats"); send("N", 0)
-- ---- when the keys are not taken
local function inactive(why, setup)
  reset(); setup()
  eq(run(function() for _, k in ipairs(order) do send(k, 1); send(k, 2); send(k, 0) end end), "", why)
end
inactive("the menu is open: the keys are the menu's", function() _menu.mode = true end)
inactive("a text entry is open", function() te_kbd.code = noop; te_kbd.char = noop end)
inactive("the script reads keyboard.code", function() keyboard.code = function() end end)
inactive("the script reads keyboard.char", function() keyboard.char = function() end end)
inactive("ARC KEYS is off", function() arc_keys = false end)
inactive("hardware keys are off (a Mac or a plain keyboard)", function() keyboard.hardware_keys = false end)
-- the arc window is closed: the call says so, and the key is not taken (no hold is remembered, nothing else happens)
reset(); ARC_OPEN = false
eq(run(function() send("5", 1) end), "arc:1:-16", "the arc is closed: the call is made and refused"); eq(run(function() send("5", 2); send("5", 0) end), "", "and nothing follows: no repeat, no release")
-- a script's own keyboard handler gets the keys when it reads them
reset(); local got = {}
keyboard.code = function(c, v) got[#got + 1] = c .. v end
send("5", 1); send("5", 0); send("H", 1); send("H", 0)
eq(table.concat(got, ","), "51,50,H1,H0", "a script that reads the keyboard gets 5 and H as before")
eq(#log, 0, "and the arc is not turned")
-- a hold begun in the script's world finishes there: the menu opened during a hold does not take the repeat or the release from the press
reset()
send("6", 1); _menu.mode = true
eq(run(function() send("6", 2) end), "arc:1:16", "a repeat goes where the press went (the hold keeps its meaning)"); eq(run(function() send("6", 0) end), "", "the release steps nothing")
-- an arc closed during a hold: no error
reset(); send("Y", 1); ARC_OPEN = false
eq(run(function() send("Y", 2) end), "arc:2:16", "a repeat after the arc closed makes the call and the call refuses"); send("Y", 0)

-- ---- a real text entry (the real textentry module): while ANY entry is open the arc keys take nothing, with the arc window open or closed and ARC KEYS on or off (the MIDI MAP number and
-- preset name entries, THEME, SCREEN, the picker, the tape name); the digits 5 and 6 and the letters T Y G H B N are typed into it; when it is closed the arc keys work again
norns.menu = {status = function() return true end, get_key = function() return "k" end, get_enc = function() return "e" end, get_redraw = function() return "r" end,
  get_refresh = function() return "f" end, set = function() end, init = function() end}
local textentry = require 'textentry'
for _, open in ipairs({true, false}) do
  for _, on in ipairs({true, false}) do
    reset(); ARC_OPEN, arc_keys = open, on
    local done
    textentry.enter(function(txt) done = txt end, "", "NAME:", nil, {accept = function(t) return #t <= 20 end})
    check(textentry.active, "the entry is open")
    local calls = run(function() for _, k in ipairs(order) do send(k, 1); send(k, 0) end end)
    eq(calls, "", "an entry is open (arc " .. (open and "open" or "closed") .. ", ARC KEYS " .. (on and "on" or "off") .. "): the arc keys take nothing, not even a call")
    eq(#(textentry.txt or ""), 8, "and all eight keys were typed into the entry (5 6 T Y G H B N)")
    check((textentry.txt or ""):find("5", 1, true) and (textentry.txt or ""):find("6", 1, true), "including the digits 5 and 6")
    -- the keys of the existing hardware mapping are the entry's too: no K1-K3 and no E1-E3 while it is open (1 2 3 Q W A S Z X)
    local before_txt = #(textentry.txt or "")
    eq(run(function() for _, k in ipairs({"1", "2", "3", "Q", "W", "A", "S", "Z", "X"}) do send(k, 1); send(k, 0) end end), "", "an entry is open: 1 2 3 Q W A S Z X are not K1-K3 or E1-E3")
    eq(#(textentry.txt or "") - before_txt, math.min(9, 20 - before_txt), "and they are typed")
    textentry.txt = string.sub(textentry.txt, 1, 8)
    -- digits
    for _, d in ipairs({"0", "1", "2", "3", "4", "7", "8", "9"}) do send(d, 1); send(d, 0) end
    eq(#(textentry.txt or ""), 16, "the other digits too")
    -- a key held while the entry opens: its repeat and release must not turn the arc
    textentry.exit()
    reset(); ARC_OPEN, arc_keys = open, on
    send("6", 1)
    textentry.enter(function() end, "", "NAME:")
    eq(run(function() send("6", 2); send("6", 0) end), "", "a key held while an entry opens: its repeat does not turn the arc")
    textentry.exit()
    reset(); ARC_OPEN, arc_keys = open, on
    if open and on then eq(run(function() send("5", 1); send("5", 0) end), "arc:1:-16", "after the entry the arc keys work again") end
  end
end
-- ---- the existing mapping is unchanged, and no other key turns the arc
reset()
local expect = {["1"] = "key:1:1", ["2"] = "key:2:1", ["3"] = "key:3:1", ENTER = "key:3:1", SPACE = "key:3:1", ESC = "key:2:1", BACKSPACE = "key:2:1",
  Q = "enc:1:-1", W = "enc:1:1", A = "enc:2:-1", S = "enc:2:1", Z = "enc:3:-1", X = "enc:3:1", UP = "enc:2:-1", DOWN = "enc:2:1", LEFT = "enc:3:-1", RIGHT = "enc:3:1"}
for k, want in pairs(expect) do
  reset()
  eq(run(function() send(k, 1) end), want, k .. " does what it did"); send(k, 0)
end
reset()
local others = {}
for _, v in pairs(keyboard.codes) do
  if not KEYS[v] and not expect[v] and v ~= "LEFTSHIFT" and v ~= "RIGHTSHIFT" then others[#others + 1] = v end
end
table.sort(others)
local called = 0
for _, k in ipairs(others) do
  log = {}
  send(k, 1); send(k, 2); send(k, 0)
  for _, l in ipairs(log) do if l:match("^arc:") then called = called + 1 end end
end
eq(called, 0, "no other key (" .. #others .. " of them, every F-key, every other letter and digit) turns the arc")
-- Ctrl and Alt do not turn it either (shortcuts are not arc keys)
reset(); send("LEFTCTRL", 1)
eq(run(function() send("5", 1) end), "", "Ctrl+5 is not an arc key"); send("5", 0); send("LEFTCTRL", 0)
reset(); send("LEFTALT", 1)
eq(run(function() send("T", 1) end), "", "Alt+T is not an arc key"); send("T", 0); send("LEFTALT", 0)
-- a build without the arc call (the Mac, an old build): nothing, no error
reset(); _norns.arc_turn = nil
eq(run(function() for _, k in ipairs(order) do send(k, 1); send(k, 0) end end), "", "no arc call: the keys do nothing")
if fails == 0 then print("arc keys: all passed") end
os.exit(fails == 0 and 0 or 1)
