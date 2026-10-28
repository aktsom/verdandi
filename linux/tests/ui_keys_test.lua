-- SYSTEM > UI with the computer keyboard (docs/port/KNOWN-ISSUES.md item 16): every key goes through the real keyboard module (hardware keys on, as the launcher
-- sets them) and the real menu key bindings (_menu.keycode of lua/core/menu.lua, cut out of the file) to the page, as in the window. run from the repo root:
--   NORNS_HARDWARE_KEYS=1 lua5.3 linux/tests/ui_keys_test.lua [table]      ("table" prints what every event does to every row)
-- the rules: one press = one step in the right direction (a repeat of the key, value 2, is two steps like on the other pages: they add the delta), releasing
-- changes nothing, UP and DOWN move between rows, LEFT and RIGHT are K2 and K3 as on every page, the hex entry still works and takes the keys only while open
package.path = "lua/?.lua;lua/core/?.lua;lua/lib/?.lua;" .. package.path
local tmp = os.tmpname()
os.remove(tmp)
os.execute("mkdir -p " .. tmp)
local real_open, real_remove, real_rename = io.open, os.remove, os.rename
local function map(p) return (p:gsub("^/home/we", tmp)) end
io.open = function(p, m) return real_open(map(p), m) end
os.remove = function(p) return real_remove(map(p)) end
os.rename = function(a, b) return real_rename(map(a), map(b)) end
local show_table = arg and arg[1] == "table"

local fails = 0
local function check(ok, what) if not ok then fails = fails + 1; print("FAIL " .. what) end end

screen = {clear = function() end, level = function() end, move = function() end, update = function() end, ping = function() end,
  text = function() end, text_right = function() end, rect = function() end, fill = function() end, text_extents = function(s) return #s * 5 end}
local looks = {}
local pressed = {}
local page
_norns = {
  ui_look = function(b, r, g, bl, gamma) looks[#looks + 1] = {b, r, g, bl, gamma} end,
  key = function(n, z) pressed[#pressed + 1] = n .. "=" .. z; page.key(n, z) end,
  enc = function(n, d) page.enc(n, d) end,
  show_control = function() end,
}
local pushed = {}
_menu = {mode = true, redraw = function() end, set_page = function(p) pushed[#pushed + 1] = p end, set_mode = function() end, goto_panel = function() end}
_path = {keyboard_layout = "/nonexistent/keyboard.layout"}
util = {clamp = function(x, lo, hi) return math.max(lo, math.min(hi, x)) end}
package.loaded.util = util
norns = {none = function() end, menu = {status = function() return true end, get_key = function() end, get_enc = function() end, get_redraw = function() end,
  get_refresh = function() end, set = function() end, init = function() end}}
require 'core/keyboard'
local te_kbd = require 'lib/textentry_kbd'
local textentry = require 'textentry'
local ui = require 'core/ui_settings'
ui.log = function() end
page = dofile("lua/core/menu/ui.lua")

-- the menu's own key bindings, as menu.lua defines them
local src = io.open("lua/core/menu.lua"):read("a")
local block = src:match("(%-%- global menu keys\nfunction _menu%.keycode.-)\nfunction _menu%.keychar")
assert(block, "_menu.keycode not found in lua/core/menu.lua")
load(block)()
_menu.penc = function(n, d) page.enc(n, d) end
_menu.key = function(n, z) page.key(n, z) end
_menu.keyboardcode = page.keycode
function _menu.keychar(c) if _menu.keyboardchar then _menu.keyboardchar(c) end end

local function code(name) for k, v in pairs(keyboard.codes) do if v == name then return k end end error("no code " .. name) end
local function send(name, value) keyboard.process(1, code(name), value) end
local ROWS = {"BRIGHTNESS", "COLOUR", "GREYS", "HEX"}
local function snapshot() local s = ui.state; return string.format("row %s  brightness %s  colour %s  greys %s", ROWS[page.pos], ui.format_brightness(s.brightness), s.colour, ui.format_greys(s.greys)) end
local function reset(row)
  if te_kbd.code then send("ESC", 1); send("ESC", 0) end -- an entry left open by the previous case
  os.remove("/home/we/ui.conf")
  page.init()
  ui.state.brightness, ui.state.colour, ui.state.greys, ui.state.custom = 0.5, "yellow", 0.7, "FF8800"
  page.pos = row
  keyboard.clear()
  pressed, pushed, looks = {}, {}, {}
end
local function vals() local s = ui.state; return {s.brightness, s.colour, s.greys} end
local function same(a, b) return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] end

local function step_of(row, name)
  -- the value keys that reach E3 on the page: EQUAL and MINUS (menu.lua), X and Z (hardware keys E3 right and left); A and S are E2, Q and W are E1
  if name == "EQUAL" or name == "X" then return 1 end
  if name == "MINUS" or name == "Z" then return -1 end
  return 0
end

local tablelines = {}
for _, row in ipairs({1, 2, 3, 4}) do
  for _, name in ipairs({"EQUAL", "MINUS", "X", "Z", "UP", "DOWN", "LEFT", "RIGHT", "W", "A"}) do
    reset(row)
    local line = {string.format("%-10s %-5s", ROWS[row], name)}
    local before = vals()
    local pos0 = page.pos
    send(name, 1)
    local after_down = vals()
    local pos_down = page.pos
    line[#line + 1] = "down: " .. snapshot()
    send(name, 2); send(name, 2)
    local after_rep = vals()
    line[#line + 1] = "2 repeats: " .. snapshot()
    local pos_rep = page.pos
    send(name, 0)
    local after_up = vals()
    line[#line + 1] = "up: " .. snapshot()
    tablelines[#tablelines + 1] = table.concat(line, "  |  ")
    local want = step_of(row, name)
    if row <= 3 and want ~= 0 then
      local tag = ROWS[row] .. " " .. name
      -- one step in the right direction on the press; the value moved, and by exactly one step
      check(not same(before, after_down), tag .. ": the press changes the value")
      -- the release changes nothing
      check(same(after_rep, after_up), tag .. ": releasing changes nothing (" .. tostring(after_rep[1]) .. "/" .. tostring(after_rep[2]) .. "/" .. tostring(after_rep[3]) .. " -> " .. tostring(after_up[1]) .. "/" .. tostring(after_up[2]) .. "/" .. tostring(after_up[3]) .. ")")
      if row == 1 then
        check(after_down[1] == (want > 0 and 0.6 or 0.4), tag .. ": brightness 0.5 goes one step to " .. tostring(want > 0 and 0.6 or 0.4) .. ", is " .. tostring(after_down[1]))
      elseif row == 2 then
        check(after_down[2] == (want > 0 and "pink" or "white"), tag .. ": colour yellow goes one step, is " .. tostring(after_down[2]))
      else
        check(after_down[3] == (want > 0 and 0.8 or 0.6), tag .. ": greys 0.7 goes one step to " .. tostring(want > 0 and 0.8 or 0.6) .. ", is " .. tostring(after_down[3]))
      end
    end
    if name == "UP" or name == "DOWN" then
      check(same(before, after_up), ROWS[row] .. " " .. name .. ": moving between rows changes no value")
      local d = name == "DOWN" and 1 or -1
      check(pos_down == math.max(1, math.min(4, pos0 + d)), ROWS[row] .. " " .. name .. ": one press moves one row (" .. pos0 .. " -> " .. pos_down .. ")")
    end
    if row <= 3 and (name == "UP" or name == "DOWN" or name == "LEFT" or name == "RIGHT" or name == "W" or name == "A") then
      check(same(before, after_up), ROWS[row] .. " " .. name .. ": this key changes no value of the page")
    end
    if name == "LEFT" then
      check(pushed[#pushed] == "SYSTEM", ROWS[row] .. " LEFT is K2: back to SYSTEM")
    end
    if name == "RIGHT" and row ~= 4 then
      check(te_kbd.char == nil, ROWS[row] .. " RIGHT (K3) does not open the hex entry")
    end
  end
end
if show_table then for _, l in ipairs(tablelines) do print(l) end end

-- the hex entry: K3 on HEX opens it, takes the keys, closes; when closed it takes none
reset(4)
check(te_kbd.char == nil and te_kbd.code == nil, "no key interception while the HEX row is not open")
send("1", 1); send("1", 0)
check(pressed[1] == "1=1" and pressed[2] == "1=0", "K1 from the keyboard works while the entry is closed: " .. table.concat(pressed, " "))
pressed = {}
send("RIGHT", 1); send("RIGHT", 0)
check(te_kbd.char ~= nil, "K3 (RIGHT) on HEX opens the entry")
send("1", 1); send("1", 0)
check(textentry.txt:sub(-1) == "1", "a typed 1 goes into the entry")
for _ = 1, 20 do send("BACKSPACE", 1); send("BACKSPACE", 0) end
for _, ch in ipairs({"0", "0", "F", "F", "0", "0"}) do send(ch, 1); send(ch, 0) end
send("ENTER", 1); send("ENTER", 0)
check(ui.state.custom == "00FF00" and ui.state.colour == "custom", "Enter accepts 00ff00: " .. tostring(ui.state.custom))
check(te_kbd.char == nil and te_kbd.code == nil, "the entry is closed again: the keys are free")
-- a release applies and writes nothing at all (delta 0), a press does
page.pos = 1
local n0 = #looks
local conf0 = io.open("/home/we/ui.conf"):read("a")
send("EQUAL", 0)
check(#looks == n0 and io.open("/home/we/ui.conf"):read("a") == conf0, "the release of a key sends nothing to the screen and writes nothing")
send("EQUAL", 1); send("EQUAL", 0)
check(#looks == n0 + 1, "a press sends exactly one look to the screen (and its release none): " .. (#looks - n0))
-- holding a key: every repeat goes the same way, none goes back (monotonic), the release leaves the last value
ui.state.brightness = 0.1
local last = 0.1
local ok_mono = true
send("EQUAL", 1)
for _ = 1, 6 do send("EQUAL", 2); if ui.state.brightness < last then ok_mono = false end last = ui.state.brightness end
send("EQUAL", 0)
check(ok_mono and ui.state.brightness == 1.0, "holding = at every repeat up, never back, release keeps it: " .. tostring(ui.state.brightness))

os.execute("rm -rf " .. tmp)
if fails > 0 then print("ui_keys_test: " .. fails .. " failed") os.exit(1) end
print("ui_keys_test: all passed")
