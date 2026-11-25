-- SYSTEM > DEVICES says when a MIDI port is skipped because another program holds it (M37, docs/port/phase-m37.md): the list entry "midi: 1 busy" and "BUSY: <name>" on the title row
-- of the MIDI list; nothing when no port is skipped, and no error on a build that has no _norns.midi_skipped (the device, macOS). run from the repo root:
--   lua5.3 linux/tests/devices_midi_busy_test.lua
package.path = "lua/lib/?.lua;" .. package.path
package.loaded["core/keyboard"] = {keymap = {us = true}, selected_map = "us"}
util = {clamp = function(x, lo, hi) return math.max(lo, math.min(hi, x)) end}
midi = {devices = {}, vports = {}, update_devices = function() end}
for i = 1, 16 do midi.vports[i] = {name = "none"} end
midi.vports[1].name = "virtual"
grid, arc, hid = {devices = {}, vports = {}}, {devices = {}, vports = {}}, {devices = {}, vports = {}}
local texts = {}
screen = {clear = function() texts = {} end, level = function() end, move = function() end,
  update = function() end, text_extents = function(s) return #s * 5 end, text = function(s) table.insert(texts, s) end, text_right = function(s) table.insert(texts, s) end}
_menu = {redraw = function() end, set_page = function() end}
local function shown(s) for _, t in ipairs(texts) do if t:find(s, 1, true) then return true end end return false end
local fails = 0
local function check(ok, what) if not ok then fails = fails + 1; print("FAIL", what) end end

local skipped = {0, ""}
_norns = {midi_skipped = function() return skipped[1], skipped[2] end}
local m = dofile("lua/core/menu/devices.lua")
m.init()
m.redraw()
check(shown("MIDI >"), "no port skipped: the list entry is plain")
check(not shown("busy") and not shown("BUSY"), "no port skipped: no word about it")

skipped = {1, "mio: busy: another program has it open (its input)\n"}
m.redraw()
check(shown("MIDI: 1 BUSY >"), "one port skipped: the list entry says so (without opening the page)")
m.key(3, 1) -- the first entry: the MIDI list
m.redraw()
check(shown("BUSY: mio"), "the MIDI list says which device is skipped")
check(shown("MIDI"), "and keeps its title")

skipped = {2, "mio 1: busy: another program has it open (its input)\nmio 2: busy: another program has it open (its output)\n"}
m.redraw()
check(shown("BUSY: mio 1, mio 2"), "two ports: both named")

skipped = {0, ""}
m.redraw()
check(not shown("BUSY"), "the port is free and added: the note is gone by itself")

-- a build without the function (the device, macOS, Windows): nothing, no error
_norns = {}
m.redraw()
check(not shown("BUSY"), "no midi_skipped: nothing")
m.key(2, 1)
m.redraw()
check(shown("MIDI >") or shown("MIDI"), "and the page still draws")

print(fails == 0 and "devices midi busy: all scenarios pass" or (fails .. " failures"))
os.exit(fails == 0)
