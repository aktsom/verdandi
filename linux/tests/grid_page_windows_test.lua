-- SYSTEM > DEVICES > GRID PORTS on Windows (lua/core/menu/gridwin.lua): the owner's two grids by name, size and serial, a port that another program holds, a monome that did not answer, a generic FTDI port that was
-- left alone, the entry in the DEVICES list, widths with the real font.   FONT_WIDTHS=<table> lua5.3 linux/tests/grid_page_windows_test.lua
package.path = "lua/?.lua;lua/lib/?.lua;lua/core/?.lua;" .. package.path
local fails = 0
local function check(c, w) if not c then fails = fails + 1; print("FAIL " .. w) end end
local W
if os.getenv("FONT_WIDTHS") then W = dofile("linux/tests/page_width.lua"); W.load(os.getenv("FONT_WIDTHS")); W.install()
else screen = setmetatable({}, {__index = function() return function() end end}); screen.text_extents = function(s) return #s * 5 end end
local drawn = {}
local base = {}
for _, k in ipairs({"clear", "text", "text_right"}) do base[k] = screen[k] end
screen.clear = function() drawn = {}; if base.clear then base.clear() end end
screen.text = function(s) drawn[#drawn + 1] = s; if base.text then base.text(s) end end
screen.text_right = function(s) drawn[#drawn + 1] = s; if base.text_right then base.text_right(s) end end
local function shown(s) for _, t in ipairs(drawn) do if t:find(s, 1, true) then return true end end return false end
util = {clamp = function(x, a, b) return math.max(a, math.min(b, x)) end}
local status = ""
_menu = {timer = {start = function() end, stop = function() end}, redraw = function() end}
_norns = {grid_status = function() return status end, midi_status = function() return "backend=WinMM\ndevices=0\ncables=0\nosc_port=9201\nroute_state=idle\n" end}
local page = dofile("lua/core/menu/gridwin.lua")
local function select_row(i) page.enc(2, -99); page.enc(2, i - 1) end

status = "grid=COM6\tm1234567\tmonome 128\t16\t8\ngrid=COM4\tM0000163\tmonome 256\t16\t16\nother=COM9: USB Serial Port: a serial port with the generic FTDI id and the serial GPS0001: not a monome, not opened (add the serial to monome_serial= in audio.conf if it is one)\n"
page.init(); page.redraw()
check(shown("monome 128") and shown("monome 256") and shown("COM6"), "both grids by name and port")
select_row(1); page.redraw()
local h = page.help_full()
check(h:find("16x8", 1, true) and h:find("m1234567", 1, true) and h:find("COM6", 1, true), "the help of the 128: size, serial, port: " .. h)
select_row(2)
h = page.help_full()
check(h:find("16x16", 1, true) and h:find("M0000163", 1, true), "the help of the 256: " .. h)
local r = page.rows()
check(r[#r].label == "COM9" and r[#r].value == "not a monome" and r[#r].help:find("not opened", 1, true), "the other FTDI port is listed as not a monome, not opened")
check(r[3].label == "GRIDS" and r[3].value == "2 found", "GRIDS 2 found")

-- a held port and a monome that did not answer: first rows
status = "grid=COM4\tM0000163\tmonome 256\t16\t16\nnote=COM6: another program has this port open (serialosc? a serial terminal? another app that talks to the grid?). Close it there; Verdandi opens the grid when the port is free\nnote=COM21: a monome is on this port but did not answer (m1111111). Unplug it and plug it in again; it is tried again every few seconds\n"
page.init(); page.redraw()
r = page.rows()
check(r[1].kind == "note" and r[1].label == "COM6" and r[2].label == "COM21" and r[3].label == "monome 256", "problems come first")
check(page.help_full():find("another program has this port open", 1, true) and page.help_full():find("serialosc", 1, true), "held: plain words")
select_row(2)
check(page.help_full():find("did not answer", 1, true) and page.help_full():find("plug it in again", 1, true), "no answer: plain words")
check(not page.help_full():lower():find("ableton"), "no program named by guess")
-- none
status = ""
page.init(); page.redraw()
check(shown("none") and page.help_full():find("Plug it in", 1, true), "no grid: says so and what to do")
check(page.key(2, 1) == "back", "K2 leaves")

-- the DEVICES list
package.loaded["core/keyboard"] = {keymap = {us = true}, selected_map = "us"}
midi = {devices = {}, vports = {}, update_devices = function() end}
for i = 1, 16 do midi.vports[i] = {name = "none"} end
grid, arc, hid = {devices = {}, vports = {}}, {devices = {}, vports = {}}, {devices = {}, vports = {}}
status = ""
local dev = dofile("lua/core/menu/devices.lua")
dev.init(); dev.redraw()
check(dev.list[#dev.list - 1] == "grid ports" and dev.list[#dev.list] == "midi routes", "the DEVICES list ends with grid ports and midi routes")
check(shown("GRID PORTS >"), "and shows it")
status = "note=COM6: another program has this port open\n"
dev.redraw()
check(shown("GRID: 1 PROBLEM >"), "a problem is visible in the list itself")
dev.enc(2, 99); dev.enc(2, -1); dev.key(3, 1); dev.redraw()
check(dev.mode == "wingrid" and shown("COM6"), "K3 opens the grid page")
dev.key(2, 1)
check(dev.mode == "type" and dev.list[dev.pos] == "grid ports", "K2 comes back to the entry")

if W then
  status = "grid=COM6\tm1234567\tmonome 128 (a very long name for a grid)\t16\t8\ngrid=COM12\tM0000163\tmonome 256\t16\t16\nnote=COM21: a monome is on this port but did not answer (m1111111). Unplug it and plug it in again; it is tried again every few seconds\nother=COM100: Standard Serial over Bluetooth link: a serial port that is not a monome, not opened\n"
  page.init()
  local bad, count = 0, 0
  for pos = 1, #page.rows() do
    select_row(pos)
    for t = 0, 60, 6 do page.tick = t; W.clear(); page.redraw(); count = count + 1; local v = W.violations(); if #v > 0 then bad = bad + 1; print("   too wide: " .. table.concat(v, "; ")) end end
  end
  check(bad == 0 and count > 20, "no text wider than the screen or over another (" .. count .. " views)")
end
print(fails == 0 and "grid page (windows): all scenarios pass" or (fails .. " failures"))
os.exit(fails == 0)
