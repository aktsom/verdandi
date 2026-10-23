-- SYSTEM > DEVICES > MIDI shows the status of the MIDI auto-connect (lua/core/menu/devices.lua). run from the repo root:
--   lua5.3 linux/tests/devices_midi_test.lua
package.path = "lua/lib/?.lua;" .. package.path
package.loaded["core/keyboard"] = {keymap = {us = true}, selected_map = "us"}
util = {clamp = function(x, lo, hi) return math.max(lo, math.min(hi, x)) end}
midi = {devices = {}, vports = {}, update_devices = function() end}
for i = 1, 16 do midi.vports[i] = {name = "none"} end
midi.vports[1].name = "Verdandi JACK in"
grid, arc, hid = {devices = {}, vports = {}}, {devices = {}, vports = {}}, {devices = {}, vports = {}}
local texts = {}
screen = {clear = function() texts = {} end, level = function() end, move = function() end,
  update = function() end, text = function(s) table.insert(texts, s) end, text_right = function(s) table.insert(texts, s) end}
_menu = {redraw = function() end, set_page = function() end}
local function shown(s) for _, t in ipairs(texts) do if t:find(s, 1, true) then return true end end return false end
local fails = 0
local function check(ok, what) if not ok then fails = fails + 1; print("FAIL", what) end end

local status = {false, 0, ""}
_norns = {midi_in_status = function() return status[1], status[2], status[3] end}
local m = dofile("lua/core/menu/devices.lua")
m.init()
m.key(3, 1) -- the first entry of the list: midi
m.redraw()
check(not shown("LINK"), "off: no status line")

status = {true, 2, "Fake DAW:out, Late DAW:out"}
m.redraw()
check(shown("AUTO-LINK"), "on: a status line")
check(shown("2"), "on: the number of linked ports")

status = {true, 0, ""}
m.redraw()
check(shown("AUTO-LINK") and shown("none yet"), "on, nothing linked: says so")

-- not on Linux: no function, no line, no error
_norns = {}
m.redraw()
check(not shown("LINK"), "no midi_in_status: nothing")

print(fails == 0 and "devices midi status: all scenarios pass" or (fails .. " failures"))
os.exit(fails == 0)
