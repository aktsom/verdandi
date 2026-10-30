-- SYSTEM > UI on Linux (lua/core/ui_settings.lua and lua/core/menu/ui.lua), docs/port/ui-settings-plan.md. run from the repo root:
--   NORNS_HARDWARE_KEYS=1 lua5.3 linux/tests/ui_settings_test.lua
-- the settings (parse, save, load, damaged file), hex parsing, the page (E2 row, E3 value, K3 on HEX), the text entry for the hex code with the
-- real textentry and keyboard modules, and the page being in SYSTEM's list on a computer only
package.path = "lua/?.lua;lua/core/?.lua;lua/lib/?.lua;" .. package.path
local tmp = os.tmpname()
os.remove(tmp)
os.execute("mkdir -p " .. tmp)
local real_open, real_remove, real_rename = io.open, os.remove, os.rename
local function map(p) return (p:gsub("^/home/we", tmp)) end
io.open = function(p, m) return real_open(map(p), m) end
os.remove = function(p) return real_remove(map(p)) end
os.rename = function(a, b) return real_rename(map(a), map(b)) end

local fails = 0
local function check(ok, what) if not ok then fails = fails + 1; print("FAIL " .. what) end end
local function slurp(p) local h = real_open(map(p)); if not h then return nil end local c = h:read("a"); h:close(); return c end
local function put(p, text) local h = real_open(map(p), "w"); h:write(text); h:close() end

-- the environment of a menu page
local texts = {}
local levels = {}
screen = {
  clear = function() texts = {}; levels = {} end, level = function(l) levels[#levels + 1] = l end, move = function() end, update = function() end, ping = function() end,
  text = function(s) texts[#texts + 1] = s end, text_right = function(s) texts[#texts + 1] = s end,
  rect = function() end, fill = function() end, text_extents = function(s) return #s * 5 end,
}
local function shown(s) for _, t in ipairs(texts) do if t:find(s, 1, true) then return true end end return false end
local calls = {}
_norns = {
  ui_look = function(b, r, g, bl, gamma) calls[#calls + 1] = {b, r, g, bl, gamma} end,
  key = function() end, enc = function() end, show_control = function() end,
}
local pushed = {}
_menu = {mode = true, redraw = function() end, set_page = function(p) pushed[#pushed + 1] = p end, keycode = function() end, keychar = function() end, set_mode = function() end}
_path = {keyboard_layout = "/nonexistent/keyboard.layout"}
util = {clamp = function(x, lo, hi) return math.max(lo, math.min(hi, x)) end}
package.loaded.util = util
-- the menu's own switch that textentry reads: the menu is open, handlers are kept here
local menu_set
norns = {none = function() end, menu = {
  status = function() return true end, get_key = function() return "k" end, get_enc = function() return "e" end,
  get_redraw = function() return "r" end, get_refresh = function() return "f" end,
  set = function(e, k, r, f) menu_set = {e, k, r, f} end, init = function() end}}

require 'core/keyboard'
local te_kbd = require 'lib/textentry_kbd'
local textentry = require 'textentry'
local ui = require 'core/ui_settings'
local logged = {}
ui.log = function(s) logged[#logged + 1] = s end
local function logs(s) for _, l in ipairs(logged) do if l:find(s, 1, true) then return true end end return false end

-- ---- hex parsing ----
local function hex(t) local r, g, b = ui.parse_hex(t); return r and string.format("%02X%02X%02X", r, g, b) or nil end
check(hex("fff") == "FFFFFF" and hex("FFF") == "FFFFFF", "fff")
check(hex("#fa0") == "FFAA00", "#fa0")
check(hex("ff8800") == "FF8800" and hex("#FF8800") == "FF8800" and hex("  #ff8800 ") == "FF8800", "ff8800 with and without # and blanks")
check(hex("20C0A0") == "20C0A0", "20C0A0 (parse_hex gives the typed colour, not the normalised one)")
for _, bad in ipairs({"", "#", "1", "12", "1234", "12345", "1234567", "ggg", "#12345g", "0x123456", "red", "12 34", "#fff#"}) do
  local r, msg = ui.parse_hex(bad)
  check(r == nil and type(msg) == "string" and msg:find("3 or 6", 1, true), "rejected: '" .. bad .. "' -> " .. tostring(msg))
end
do local r, msg = ui.parse_hex("000"); check(r == nil and msg:find("black", 1, true), "000 is black: " .. tostring(msg)) end
do local r, msg = ui.parse_hex("#000000"); check(r == nil and msg:find("black", 1, true), "000000 is black") end
check(ui.hex_hint("") == "" and ui.hex_hint("#") == "", "an empty text gives no warning")
check(ui.hex_hint("#f") ~= "" and ui.hex_hint("ff80") ~= "", "a prefix of a code says '3 or 6 digits' until it is one")
check(ui.hex_hint("ff8800") == "" and ui.hex_hint("#fa0") == "", "a valid code gives no warning")
check(ui.hex_hint("ggg") ~= "" and ui.hex_hint("1234567") ~= "", "an impossible text warns")

-- ---- defaults, save, load ----
os.remove("/home/we/ui.conf")
local s = ui.load()
check(s.brightness == 1.0 and s.colour == "white" and s.contrast == 0.5 and s.custom == nil, "defaults: brightness 1, white, contrast 0.5")
check(logs("not found"), "a missing file is logged")
check(slurp("/home/we/ui.conf") == nil, "a missing file is not created by loading")

ui.step_brightness(-1)
check(math.abs(s.brightness - 0.9) < 1e-9, "one step down is 0.9")
for _ = 1, 20 do ui.step_brightness(-1) end
check(s.brightness == 0.1, "brightness stops at 0.1")
for _ = 1, 20 do ui.step_brightness(1) end
check(s.brightness == 1.0, "brightness stops at 1")
for _ = 1, 3 do ui.step_contrast(1) end
check(s.contrast == 0.8, "contrast 0.5 up three steps is 0.8: " .. tostring(s.contrast))
for _ = 1, 10 do ui.step_contrast(1) end
check(s.contrast == 1.0, "contrast stops at 1.0")
for _ = 1, 20 do ui.step_contrast(-1) end
check(s.contrast == 0.0, "contrast stops at 0 (the old linear mapping)")
local seen_c = {}
for _ = 1, 10 do ui.step_contrast(1); seen_c[#seen_c + 1] = ui.format_contrast(s.contrast) end
check(table.concat(seen_c, " ") == "0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0", "the ten steps up from 0: " .. table.concat(seen_c, " "))
s.contrast = 0.5

-- the displayed value to the gamma exponent: eleven values, 0 = linear, 0.5 = the old default 0.5, 1 = 0.4 (docs/port/ui-settings-plan.md 2.2)
local GAMMA = {[0.0] = 1.00, [0.1] = 0.90, [0.2] = 0.80, [0.3] = 0.70, [0.4] = 0.60, [0.5] = 0.50, [0.6] = 0.48, [0.7] = 0.46, [0.8] = 0.44, [0.9] = 0.42, [1.0] = 0.40}
for i = 0, 10 do
  local c = i / 10
  check(math.abs(ui.gamma_of(c) - GAMMA[c]) < 1e-9, string.format("contrast %.1f gives gamma %.2f, is %s", c, GAMMA[c], tostring(ui.gamma_of(c))))
end
-- the old greys key (a gamma) converts to the nearest contrast value
local OLD = {[1.0] = 0.0, [0.9] = 0.1, [0.8] = 0.2, [0.7] = 0.3, [0.6] = 0.4, [0.5] = 0.5, [0.4] = 1.0}
for g, c in pairs(OLD) do
  check(math.abs(ui.contrast_from_gamma(g) - c) < 1e-9, string.format("old greys=%.1f is contrast %.1f, is %s", g, c, tostring(ui.contrast_from_gamma(g))))
end
check(math.abs(ui.contrast_from_gamma(0.45) - 0.8) < 1e-9, "old greys=0.45 (by hand) is contrast 0.8")
check(ui.format_contrast(0.30000000000000004) == "0.3" and ui.format_contrast(0) == "0.0" and ui.format_contrast(1) == "1.0", "no float noise in the shown contrast")
check(ui.format_brightness(0.30000000000000004) == "0.3" and ui.format_brightness(1) == "1.0", "no float noise in the shown value")

-- steps are whole tenths all the way: 0.1 .. 1.0
local seen = {}
ui.state.brightness = 1.0
for _ = 1, 9 do ui.step_brightness(-1); seen[#seen + 1] = ui.format_brightness(s.brightness) end
check(table.concat(seen, " ") == "0.9 0.8 0.7 0.6 0.5 0.4 0.3 0.2 0.1", "the nine steps: " .. table.concat(seen, " "))

-- the colour: WHITE YELLOW PINK, CUSTOM only once a valid hex has been entered
ui.state.colour = "white"
ui.step_colour(1); check(s.colour == "yellow", "E3 once: yellow")
ui.step_colour(1); check(s.colour == "pink", "E3 twice: pink")
ui.step_colour(1); check(s.colour == "pink", "no CUSTOM before a hex was entered")
local ok = ui.set_custom("#ff8800")
check(ok and s.colour == "custom" and s.custom == "FF8800", "a valid hex selects CUSTOM")
local r, g, b = ui.tint()
check(r == 255 and g == 136 and b == 0, "the tint of custom ff8800")
ui.state.colour = "pink"; r, g, b = ui.tint()
check(r == 255 and g == 128 and b == 184, "pink is FF80B8")
ui.state.colour = "yellow"; r, g, b = ui.tint()
check(r == 255 and g == 208 and b == 0, "yellow is FFD000")
-- a bad hex keeps the previous colour
local before = s.colour
local ok2, msg = ui.set_custom("12")
check(not ok2 and type(msg) == "string" and s.colour == before and s.custom == "FF8800", "a bad hex changes nothing and says why")

-- save: exactly the four keys, in order, read back by a second load
ui.state.brightness, ui.state.colour, ui.state.contrast = 0.7, "custom", 0.6
ui.save()
local text = slurp("/home/we/ui.conf")
check(text == "brightness=0.7\ncolour=custom\ncustom=FF8800\ncontrast=0.6\nfile_dialog=0\n", "the file: " .. tostring(text))
check(slurp("/home/we/ui.conf.tmp") == nil, "no temporary file is left")
calls = {}
package.loaded["core/ui_settings"] = nil
local ui2 = dofile("lua/core/ui_settings.lua")
package.loaded["core/ui_settings"] = ui2 -- the page requires this instance
ui2.log = function(s) logged[#logged + 1] = s end
ui2.load_and_apply()
check(#calls == 1 and calls[1][1] == 0.7 and calls[1][2] == 255 and calls[1][3] == 136 and calls[1][4] == 0 and math.abs(calls[1][5] - 0.48) < 1e-9, "a second start applies the saved look: " .. (calls[1] and table.concat(calls[1], " ") or "nothing"))
ui = ui2

-- the defaults at the first start are applied too (contrast 0.5 = gamma 0.5)
os.remove("/home/we/ui.conf")
calls = {}
ui.load_and_apply()
check(#calls == 1 and calls[1][1] == 1.0 and calls[1][2] == 255 and calls[1][5] == 0.5, "no file: white, 1, contrast 0.5 (gamma 0.5) applied")

-- ---- a damaged file: per key, nothing throws, one log line each, unknown keys survive a rewrite ----
local function load_text(t)
  logged = {}
  put("/home/we/ui.conf", t)
  local ok, st = pcall(ui.load)
  check(ok, "load threw: " .. tostring(st))
  return ok and st or {}
end
local st = load_text("brightness=abc\ncolour=purple\ncustom=12\ncontrast=x\n")
check(st.brightness == 1.0 and st.colour == "white" and st.contrast == 0.5 and st.custom == nil, "every bad key falls back to its own default")
check(logs("brightness") and logs("colour") and logs("custom") and logs("contrast"), "one log line for each bad key")
st = load_text("brightness=5\ncontrast=3\n")
check(st.brightness == 1.0 and st.contrast == 0.5 and logs("contrast"), "brightness 5 is clamped to 1; contrast 3 is out of range: the default 0.5 with a log line")
st = load_text("brightness=0\ncontrast=-0.1\n")
check(st.brightness == 0.1 and st.contrast == 0.5 and logs("contrast"), "brightness 0 -> 0.1; contrast -0.1 is out of range: 0.5")
st = load_text("contrast=0\n")
check(st.contrast == 0.0 and not logs("contrast"), "contrast=0 is valid (linear)")
st = load_text("contrast=0.73\n")
check(st.contrast == 0.7, "contrast 0.73 snaps to a tenth: " .. tostring(st.contrast))
-- an old ui.conf with greys= (a gamma) converts; contrast wins when both are there
st = load_text("brightness=0.6\ncolour=yellow\ngreys=0.7\n")
check(st.contrast == 0.3 and st.brightness == 0.6 and st.colour == "yellow" and logs("greys"), "old greys=0.7 becomes contrast 0.3, the rest is kept, a log line says so")
st = load_text("greys=1.0\n")
check(st.contrast == 0.0, "old greys=1.0 (linear) is contrast 0")
st = load_text("greys=0.4\n")
check(st.contrast == 1.0, "old greys=0.4 is contrast 1")
st = load_text("greys=0.5\n")
check(st.contrast == 0.5, "old greys=0.5 is contrast 0.5")
st = load_text("greys=0.7\ncontrast=0.9\n")
check(st.contrast == 0.9, "contrast wins over the old greys key")
st = load_text("greys=abc\n")
check(st.contrast == 0.5 and logs("greys"), "a damaged old greys value is the default")
load_text("greys=0.7\n")
ui.save()
local rewritten = slurp("/home/we/ui.conf") or ""
check(rewritten:find("contrast=0.3", 1, true) and not rewritten:find("greys", 1, true), "saving writes contrast and drops the old key: " .. rewritten:gsub("\n", " "))
st = load_text("brightness=0.75\n")
check(st.brightness == 0.8 or st.brightness == 0.7, "0.75 snaps to a tenth")
st = load_text("colour=custom\n")
check(st.colour == "white" and logs("custom"), "colour=custom without a custom hex is white")
st = load_text("color=yellow\ncolour=pink\n")
check(st.colour == "pink", "color is an accepted spelling, the last one wins")
st = load_text("")
check(st.brightness == 1.0 and st.colour == "white" and st.contrast == 0.5, "an empty file is the defaults")
st = load_text("\0\1\2 junk \255\n===\nbrightness\n")
check(st.brightness == 1.0 and st.colour == "white", "binary junk and lines without = are ignored")
st = load_text("foo=bar\nbrightness=0.5\nnot a line\n")
check(st.brightness == 0.5 and logs("foo"), "an unknown key is ignored with a log line")
ui.save()
check((slurp("/home/we/ui.conf") or ""):find("foo=bar", 1, true) ~= nil, "unknown keys survive a rewrite")
check(slurp("/home/we/ui.conf"):find("not a line", 1, true) == nil, "junk lines without = are dropped on rewrite")

-- ---- the page ----
os.remove("/home/we/ui.conf")
ui.load()
local page = dofile("lua/core/menu/ui.lua")
page.init()
page.redraw()
check(shown("BRIGHTNESS") and shown("COLOUR") and shown("CONTRAST") and shown("HEX") and not shown("GREYS"), "the four rows are shown, the third is CONTRAST")
check(shown("1.0") and shown("WHITE") and shown("0.5"), "the values: 1.0, WHITE, 0.5")
calls = {}
page.enc(3, -1)
check(ui.state.brightness == 0.9 and #calls == 1 and calls[1][1] == 0.9, "E3 on BRIGHTNESS: 0.9, applied at once")
check(slurp("/home/we/ui.conf") and slurp("/home/we/ui.conf"):find("brightness=0.9", 1, true), "and saved at once")
page.enc(2, 1); page.enc(3, 1)
check(ui.state.colour == "yellow" and #calls == 2 and calls[2][2] == 255 and calls[2][3] == 208 and calls[2][4] == 0, "E2 then E3 on COLOUR: yellow applied")
page.enc(2, 1); page.enc(3, 1)
check(ui.state.contrast == 0.6 and math.abs(calls[3][5] - 0.48) < 1e-9, "E3 on CONTRAST: 0.6 applied (gamma 0.48)")
page.redraw(); check(shown("0.6") and shown("YELLOW"), "the page shows the new values")
page.key(2, 1); check(pushed[#pushed] == "SYSTEM", "K2 goes back to SYSTEM")

-- ---- the text entry for the hex code, with the real textentry and keyboard ----
local function code(name) for k, v in pairs(keyboard.codes) do if v == name then return k end end error("no code " .. name) end
local function tap(name) keyboard.process(1, code(name), 1); keyboard.process(1, code(name), 0) end
local function typed(str)
  for ch in str:gmatch(".") do
    if ch == "#" then
      keyboard.process(1, code("LEFTSHIFT"), 1); tap("3"); keyboard.process(1, code("LEFTSHIFT"), 0)
    else tap(ch:upper() == ch and ch:match("%a") and ch or ch:upper()) end
  end
end
keyboard.clear()
page.init()
page.enc(2, 1); page.enc(2, 1); page.enc(2, 1) -- HEX row (4th)
calls = {}
-- K3 on HEX opens the colour picker; its HEX row (K3) opens the text entry. K3 on another row of the picker keeps the colour, K2 gives the old one back
local picker = require 'core/menu/picker'
local function open_entry()
  page.key(3, 1)
  picker.init() -- what the menu's set_page does
  picker.enc(2, 3)
  picker.key(3, 1)
end
local function keep() picker.enc(2, -3) picker.key(3, 1) end
open_entry()
check(te_kbd.char ~= nil and te_kbd.code ~= nil, "K3 on HEX, then the picker's HEX row, opens the text entry (the keyboard handlers are set)")
check(textentry.heading:find("HEX", 1, true) ~= nil, "the heading says HEX: " .. tostring(textentry.heading))
check(textentry.txt == "#408080", "no custom colour yet: the picker is at the middle and the entry starts with it: " .. tostring(textentry.txt))
local presses = {}
_norns.key = function(n, z) presses[#presses + 1] = n .. "=" .. z end
typed("12")
check(textentry.txt == "12", "typing 1 and 2 in the entry builds the text: '" .. tostring(textentry.txt) .. "'")
check(#presses == 0, "1 and 2 typed in the entry do not press K1 and K2")
check(textentry.warn ~= nil and textentry.warn ~= "", "'12' warns while typing")
tap("BACKSPACE"); tap("BACKSPACE")
check(textentry.txt == "" and #presses == 0, "backspace deletes in the entry and is not K2")
typed("ff8800")
check(textentry.txt == "FF8800" or textentry.txt == "ff8800", "typed ff8800: '" .. tostring(textentry.txt) .. "'")
check(textentry.warn == nil or textentry.warn == "", "a valid code has no warning")
tap("ENTER")
check(ui.state.custom == nil, "Enter in the entry only shows the colour: nothing is stored until the picker keeps it")
check(#calls >= 1 and calls[#calls][2] == 255 and calls[#calls][3] == 136 and calls[#calls][4] == 0, "the colour was applied to the screen at once")
keep()
check(ui.state.custom == "FF8800" and ui.state.colour == "custom", "K3 in the picker keeps it: CUSTOM with FF8800")
check(#presses == 0, "Enter in the entry is not K3")
check(te_kbd.char == nil and te_kbd.code == nil, "the entry is closed: the keyboard handlers are gone")
-- a bad code: the page says so, the colour stays
page.redraw()
open_entry()
tap("BACKSPACE"); tap("BACKSPACE"); tap("BACKSPACE"); tap("BACKSPACE"); tap("BACKSPACE"); tap("BACKSPACE")
typed("12")
tap("ENTER")
check(picker.msg ~= nil and picker.msg:find("bad hex", 1, true), "a bad hex: the picker says so")
check(ui.state.custom == "FF8800" and ui.state.colour == "custom", "a bad hex keeps the previous colour")
picker.key(2, 1) -- K2: the old colour back
-- Escape cancels
page.init()
open_entry()
typed("00ff00")
tap("ESC")
check(ui.state.custom == "FF8800", "Esc cancels: nothing changed")
check(te_kbd.char == nil, "and the entry is closed")
picker.key(2, 1)
-- the '#' typed with shift is accepted too
open_entry()
for _ = 1, 8 do tap("BACKSPACE") end
typed("#0f0")
check(textentry.txt:upper() == "#0F0" or textentry.txt == "#0f0", "# typed with shift: '" .. tostring(textentry.txt) .. "'")
tap("ENTER")
keep()
check(ui.state.custom == "00FF00", "#0f0 is 00FF00: " .. tostring(ui.state.custom))

-- ---- the page is in SYSTEM's list on a computer only ----
local getenv = os.getenv
local function system_with(platform)
  os.getenv = function(k) if k == "NORNS_PLATFORM" then return platform end return getenv(k) end
  local m = dofile("lua/core/menu/system.lua")
  os.getenv = getenv
  return table.concat(m.pages, ","), table.concat(m.list, "|")
end
local pages = system_with("linux")
check(pages == "DEVICES,AUDIO,MODS,UI,BOX,MIDIMAP,CLEANUP,RESET,RESTART", "SYSTEM on a computer keeps the page ids: " .. pages)
local _, list = system_with("linux")
check(list:find("SCREEN >", 1, true) ~= nil and not list:find("UI >", 1, true), "the list shows 'SCREEN >' (the visible name of the page UI)")
pages = system_with(nil)
check(pages == "DEVICES,WIFI,MODS,SETTINGS,RESTART,UPDATE" and not pages:find("UI", 1, true), "SYSTEM on a device is as before and has no UI: " .. pages)
-- without _norns.ui_look nothing is applied or written
os.remove("/home/we/ui.conf")
_norns.ui_look = nil
calls = {}
package.loaded["core/ui_settings"] = nil
local ui3 = dofile("lua/core/ui_settings.lua")
package.loaded["core/ui_settings"] = ui3
ui3.log = function() end
ui3.load_and_apply()
check(#calls == 0 and slurp("/home/we/ui.conf") == nil, "without _norns.ui_look: nothing applied, nothing written")
-- menu.lua registers the page only on a computer
local menu_src = io.open("lua/core/menu.lua"):read("a")
check(menu_src:find("m%[\"UI\"%]") ~= nil, "menu.lua registers m[\"UI\"]")
check(menu_src:find("ui_settings", 1, true) ~= nil, "menu.lua loads the settings at start")

os.execute("rm -rf " .. tmp)
if fails > 0 then print("ui_settings_test: " .. fails .. " failed") os.exit(1) end
print("ui_settings_test: all passed")
