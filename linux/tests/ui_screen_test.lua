-- SYSTEM > SCREEN with presets, like THEME (lua/core/ui_settings.lua, lua/core/menu/ui.lua). run from the repo root:
--   NORNS_HARDWARE_KEYS=1 lua5.3 linux/tests/ui_screen_test.lua
-- rows PRESET, COLOUR (the HSB picker), BRIGHTNESS, CONTRAST, SAVE, DELETE (his own presets only); a preset is the screen COLOUR only (WHITE YELLOW PINK built in, his own one small file each in
-- screen-presets/); brightness and contrast keep their values when a preset is chosen; the old colour=custom plus custom=HEX of ui.conf still loads (as an unsaved look); damaged files are ignored with a
-- log line; every handler ends with a redraw; loading a preset never touches the box style or the THEME colours
package.path = "lua/?.lua;lua/core/?.lua;lua/lib/?.lua;" .. package.path
local tmp = os.tmpname()
os.remove(tmp)
os.execute("mkdir -p " .. tmp)
local real_open, real_remove, real_rename, real_execute = io.open, os.remove, os.rename, os.execute
local function map(p) return (p:gsub("^/home/we", tmp)) end
io.open = function(p, m) return real_open(map(p), m) end
os.remove = function(p) return real_remove(map(p)) end
os.rename = function(a, b) return real_rename(map(a), map(b)) end
os.execute = function(cmd) return real_execute((cmd:gsub("/home/we", tmp))) end
local real_print = print
local printed = {}
print = function(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end printed[#printed + 1] = table.concat(t, " ") end

local fails = 0
local function check(ok, what) if not ok then fails = fails + 1; real_print("FAIL " .. what) end end
local function slurp(p) local h = real_open(map(p)); if not h then return nil end local c = h:read("a"); h:close(); return c end
local function put(p, text) real_execute("mkdir -p '" .. map(p):match("^(.*)/[^/]*$") .. "'"); local h = real_open(map(p), "w"); h:write(text); h:close() end
local function logged(part) for _, l in ipairs(printed) do if l:find(part, 1, true) then return true end end return false end

-- the screen: what the last redraw drew
local texts, frame_levels = {}, {}
screen = setmetatable({}, {__index = function() return function() end end})
screen.clear = function() texts = {} end
screen.text = function(s) texts[#texts + 1] = tostring(s) end
screen.text_right = function(s) texts[#texts + 1] = tostring(s) end
screen.text_extents = function(s) return #tostring(s) * 5 end
local function shown(s) for _, t in ipairs(texts) do if t:find(s, 1, true) then return true end end return false end
local calls = {}
local box_calls = 0
_norns = {ui_look = function(b, r, g, bl, gamma) calls[#calls + 1] = {b, r, g, bl, gamma} end, box_look = function() box_calls = box_calls + 1 end,
  key = function() end, enc = function() end, show_control = function() end, toast = function() end}
local pushed = {}
local redraws = 0
local page
_menu = {mode = true, page = "UI", redraw = function() redraws = redraws + 1; page.redraw() end, set_page = function(p) pushed[#pushed + 1] = p end, set_mode = function() end,
  keycode = function() end, keychar = function() end}
_path = {keyboard_layout = "/nonexistent/keyboard.layout"}
util = {clamp = function(x, lo, hi) return math.max(lo, math.min(hi, x)) end,
  scandir = function(dir) local out = {} local p = io.popen("ls -p '" .. map(dir) .. "' 2>/dev/null") for l in p:lines() do out[#out + 1] = l end p:close() return out end}
package.loaded.util = util
norns = {none = function() end, menu = {status = function() return true end, get_key = function() return "k" end, get_enc = function() return "e" end,
  get_redraw = function() return "r" end, get_refresh = function() return "f" end, set = function() end, init = function() end}}
-- a text entry that records what it was asked, and a picker that records its options
local entry
package.loaded.textentry = {enter = function(cb, default, heading, hint, opts) entry = {cb = cb, default = default, heading = heading, hint = hint, opts = opts} end}
local picker = require 'core/menu/picker'
local picker_opts
picker.open = function(o) picker_opts = o end
local ctrl_down = false
package.loaded['core/keyboard'] = {ctrl = function() return ctrl_down end, shift = function() return false end}
local clip = {}
package.loaded['core/clipboard'] = {copy = function(t) clip.copied = t return true end, paste_colour = function(cb) clip.paste_cb = cb end}
local ui = require 'core/ui_settings'
ui.log = function(s) printed[#printed + 1] = "ui.conf: " .. s end
local box = require 'core/box_settings'
box.log = function() end
page = dofile("lua/core/menu/ui.lua")

local function fresh(conf)
  os.execute("rm -rf '" .. tmp .. "'/ui.conf '" .. tmp .. "'/screen-presets")
  if conf then put("/home/we/ui.conf", conf) end
  printed = {}
  ui.load()
  ui.reload_presets()
  calls, pushed, entry, picker_opts = {}, {}, nil, nil
  page.init()
  page.pos, page.top = 1, 1
  page.redraw()
end
local function press(n) local b = redraws; page.key(n, 1); check(redraws > b, "key " .. n .. " ended with a redraw") end
local function turn(n, d) local b = redraws; page.enc(n, d); check(redraws > b, "enc " .. n .. " " .. d .. " ended with a redraw") end
local function same_as_redraw(what) local a = table.concat(texts, "|"); page.redraw(); check(a == table.concat(texts, "|"), "the screen shows the state: " .. what) end
local function row(name) for i, r in ipairs(page.rows()) do if r == name then return i end end end

-- ---------------------------------------------------------------- the settings
fresh()
check(ui.state.preset == "WHITE" and ui.state.tint == "FFFFFF" and ui.label() == "WHITE", "defaults: the WHITE preset, tint FFFFFF (" .. tostring(ui.state.preset) .. ")")
local names = {}
for _, p in ipairs(ui.preset_list()) do names[#names + 1] = p.name end
check(table.concat(names, ",") == "WHITE,YELLOW,PINK", "the built-in presets in order: " .. table.concat(names, ","))
local function colour_of(n) for _, p in ipairs(ui.preset_list()) do if p.name == n then return p.colour end end end
check(colour_of("YELLOW") == "FFD000" and colour_of("PINK") == "FF80B8" and colour_of("WHITE") == "FFFFFF", "their colours")
-- a preset holds the colour only: brightness and contrast keep their values
ui.step_brightness(-3); ui.step_contrast(2)
check(ui.state.brightness == 0.7 and ui.state.contrast == 0.7, "setup: brightness 0.7, contrast 0.7")
calls = {}
check(ui.select_preset("YELLOW"), "select YELLOW")
check(ui.state.tint == "FFD000" and ui.state.preset == "YELLOW" and ui.state.brightness == 0.7 and ui.state.contrast == 0.7, "choosing a preset keeps brightness and contrast")
check(#calls == 1 and calls[1][1] == 0.7 and calls[1][2] == 255 and calls[1][3] == 208 and calls[1][4] == 0, "applied live to the screen with the unchanged brightness")
check(box_calls == 0, "a screen preset never touches the box look (no _norns.box_look call)")
check(slurp("/home/we/ui.conf") == "brightness=0.7\npreset=YELLOW\ntint=FFD000\ncontrast=0.7\nfile_dialog=0\n", "saved as current: " .. tostring(slurp("/home/we/ui.conf")))
local before = {box.state.style, box.state.colours.box, box.state.preset}
ui.select_preset("PINK")
check(box.state.style == before[1] and box.state.colours.box == before[2] and box.state.preset == before[3], "the box style and the THEME colours are as they were")
-- changed since
ui.select_preset("YELLOW")
check(ui.label() == "YELLOW" and not ui.is_modified(), "the preset as it is: no marker")
check(ui.set_custom("FF8800") and ui.state.tint == "FF8800" and ui.label() == "YELLOW~" and ui.is_modified(), "a colour from the picker: YELLOW~ (changed since)")
check(not ui.set_custom("000") and ui.state.tint == "FF8800", "black is refused")
-- preview shows a colour without storing it
calls = {}
check(ui.preview_custom("00FF00") and #calls == 1 and calls[1][3] == 255 and ui.state.tint == "FF8800", "a preview applies and stores nothing")
-- SAVE as a preset: the colour only
check(select(1, ui.save_preset("Amber")), "save Amber")
local f = slurp("/home/we/screen-presets/amber.screen")
check(f == "verdandi-screen=1\nname=Amber\ncolour=FF8800\n", "the file holds the colour only: " .. tostring(f))
check(ui.state.preset == "Amber" and ui.label() == "Amber" and not ui.is_modified(), "the saved preset is the one in use")
check(slurp("/home/we/ui.conf"):find("preset=Amber", 1, true) ~= nil, "and ui.conf says so")
local names2 = {}
for _, p in ipairs(ui.preset_list()) do names2[#names2 + 1] = p.name end
check(table.concat(names2, ",") == "WHITE,YELLOW,PINK,Amber", "his own come after the built-in ones: " .. table.concat(names2, ","))
-- exists: asks, overwrite writes
local ok, why, existing = ui.save_preset("amber")
check(ok == false and why == "exists" and existing == "Amber", "the same name (any case) asks first")
ui.set_custom("112233"); check(ui.save_preset("amber", true), "overwrite"); check(slurp("/home/we/screen-presets/amber.screen"):find("colour=112233", 1, true) ~= nil, "overwritten")
-- names
for _, bad in ipairs({"", "   ", ("x"):rep(19), "a/b", "a\\b", "a:b", "..", ".hidden", "a..b", "a\1b", "white", "Pink", "YELLOW", "custom", "\xc3\xa4", "-", "***"}) do
  local o, w = ui.save_preset(bad)
  check(o == false and type(w) == "string" and w ~= "exists", "refused name '" .. bad:gsub("%c", "?") .. "': " .. tostring(w))
end
-- delete: built-in never, own once, the colour stays
check(ui.delete_preset("WHITE") == false, "a built-in preset is protected")
check(ui.delete_preset("Amber") and slurp("/home/we/screen-presets/amber.screen") == nil, "his own preset is deleted")
check(ui.state.preset == "CUSTOM" and ui.label() == "CUSTOM" and ui.state.tint == "112233", "the colour stays on the screen and reads CUSTOM")
check(ui.delete_preset("nothing") == false, "an unknown name")
-- step_preset
ui.select_preset("WHITE"); ui.step_preset(1); check(ui.state.preset == "YELLOW", "E3 right: the next preset")
ui.step_preset(-1); ui.step_preset(-1); check(ui.state.preset == "WHITE", "stops at the first")
ui.step_preset(0); check(ui.state.preset == "WHITE", "0 does nothing")
ui.step_preset(9); check(ui.state.preset == "PINK", "stops at the last")
-- damaged files: ignored with one log line each
fresh()
put("/home/we/screen-presets/empty.screen", "")
put("/home/we/screen-presets/header.screen", "hello\nname=Header\ncolour=FF0000\n")
put("/home/we/screen-presets/newer.screen", "verdandi-screen=2\nname=Newer\ncolour=FF0000\n")
put("/home/we/screen-presets/nocolour.screen", "verdandi-screen=1\nname=Nocolour\n")
put("/home/we/screen-presets/badhex.screen", "verdandi-screen=1\nname=Badhex\ncolour=GG0000\n")
put("/home/we/screen-presets/black.screen", "verdandi-screen=1\nname=Black\ncolour=000000\n")
put("/home/we/screen-presets/mismatch.screen", "verdandi-screen=1\nname=Other\ncolour=FF0000\n")
put("/home/we/screen-presets/binary.screen", "verdandi-screen=1\nname=Binary\ncolour=FF0000\n\1\2\n")
put("/home/we/screen-presets/big.screen", "verdandi-screen=1\nname=Big\ncolour=FF0000\n" .. ("# x\n"):rep(1000))
put("/home/we/screen-presets/white.screen", "verdandi-screen=1\nname=White\ncolour=FF0000\n")
put("/home/we/screen-presets/good.screen", "verdandi-screen=1\nname=Good\ncolour=#0f0\n")
put("/home/we/screen-presets/notes.txt", "not a preset")
printed = {}
ui.reload_presets()
local own = {}
for _, p in ipairs(ui.preset_list()) do if not p.builtin then own[#own + 1] = p.name .. "=" .. p.colour end end
check(table.concat(own, ",") == "Good=00FF00", "only the good file is a preset: " .. table.concat(own, ","))
for _, part in ipairs({"empty.screen", "header.screen", "newer.screen", "nocolour.screen", "badhex.screen", "black.screen", "mismatch.screen", "binary.screen", "big.screen", "white.screen"}) do
  check(logged(part), "a log line for " .. part)
end
check(not logged("notes.txt"), "a file that is not a .screen file is not looked at")
-- more than 64
os.execute("rm -rf '" .. tmp .. "'/screen-presets")
for i = 1, 66 do put(string.format("/home/we/screen-presets/p%02d.screen", i), string.format("verdandi-screen=1\nname=p%02d\ncolour=FF0000\n", i)) end
printed = {}
ui.reload_presets()
local n_own = 0
for _, p in ipairs(ui.preset_list()) do if not p.builtin then n_own = n_own + 1 end end
check(n_own == 64 and logged("p65.screen"), "at most 64 of his own: " .. n_own)

-- ---------------------------------------------------------------- the old ui.conf
fresh("brightness=0.6\ncolour=custom\ncustom=ff8800\ngreys=0.7\n")
check(ui.state.tint == "FF8800" and ui.state.preset == "CUSTOM" and ui.label() == "CUSTOM", "colour=custom with its hex loads as the current colour, unsaved: " .. tostring(ui.state.tint) .. " " .. ui.label())
check(ui.state.contrast == 0.3 and ui.state.brightness == 0.6, "and the old greys key still converts (contrast 0.3), brightness is kept")
ui.apply()
check(calls[#calls][2] == 255 and calls[#calls][3] == 136 and calls[#calls][4] == 0, "the screen shows the old custom colour")
ui.save()
local rewritten = slurp("/home/we/ui.conf")
check(rewritten:find("preset=CUSTOM", 1, true) and rewritten:find("tint=FF8800", 1, true) and not rewritten:find("colour=", 1, true) and not rewritten:find("custom=", 1, true) and not rewritten:find("greys", 1, true), "saving writes the new keys: " .. rewritten:gsub("\n", " | "))
fresh("colour=yellow\n"); check(ui.state.preset == "YELLOW" and ui.state.tint == "FFD000", "colour=yellow is the YELLOW preset")
fresh("colour=pink\n"); check(ui.state.preset == "PINK" and ui.state.tint == "FF80B8", "colour=pink is the PINK preset")
fresh("colour=white\n"); check(ui.state.preset == "WHITE" and ui.state.tint == "FFFFFF", "colour=white")
fresh("colour=custom\n"); check(ui.state.preset == "WHITE" and logged("custom"), "colour=custom without a hex is white, with a log line")
fresh("colour=blue\n"); check(ui.state.preset == "WHITE" and logged("colour"), "an unknown colour is white, with a log line")
fresh("preset=PINK\ntint=FF80B8\ncolour=yellow\n"); check(ui.state.preset == "PINK", "the new keys win over the old ones")
fresh("tint=FF8800\n"); check(ui.state.tint == "FF8800" and ui.label() == "CUSTOM", "a tint without a known preset reads CUSTOM")
fresh("preset=Nowhere\ntint=123456\n"); check(ui.label() == "CUSTOM" and ui.state.tint == "123456", "a preset name that does not exist reads CUSTOM, the tint is kept")
fresh("tint=zzz\n"); check(ui.state.tint == "FFFFFF" and logged("tint"), "a damaged tint is white, with a log line")
put("/home/we/screen-presets/amber.screen", "verdandi-screen=1\nname=Amber\ncolour=FF8800\n")
fresh("preset=Amber\ntint=FF8800\n"); put("/home/we/screen-presets/amber.screen", "verdandi-screen=1\nname=Amber\ncolour=FF8800\n"); ui.reload_presets()
check(ui.label() == "Amber" and not ui.is_modified(), "a saved preset in use is found at start")

-- ---------------------------------------------------------------- the page
fresh()
check(table.concat(page.rows(), ",") == "PRESET,COLOUR,BRIGHTNESS,CONTRAST,SAVE", "the rows: " .. table.concat(page.rows(), ","))
check(shown("PRESET") and shown("WHITE") and shown("COLOUR") and shown("#FFFFFF") and shown("BRIGHTNESS") and shown("1.0"), "the rows are drawn with their values")
check(not shown("HEX") and not shown("GREYS"), "no separate HEX row")
-- E2 row, E3 value
turn(3, 1); check(ui.state.preset == "YELLOW" and #calls == 1, "E3 on PRESET: the next preset, live")
same_as_redraw("PRESET")
turn(2, 2); turn(3, -2); check(ui.state.brightness == 0.8 and #calls == 2, "E3 on BRIGHTNESS steps it and applies")
turn(2, 1); turn(3, 1); check(ui.state.contrast == 0.6, "E3 on CONTRAST steps it")
turn(3, 0); check(ui.state.contrast == 0.6, "delta 0 changes nothing")
page.key(3, 0); check(true, "(a release)")
-- brightness and contrast stay when a preset is chosen through the page
turn(2, -9); turn(3, 1); check(ui.state.preset == "PINK" and ui.state.brightness == 0.8 and ui.state.contrast == 0.6, "choosing PINK leaves 0.8 and 0.6")
-- the list
press(3); check(page.mode == "list", "K3 on PRESET opens the list"); page.redraw()
check(shown("WHITE") and shown("YELLOW") and shown("PINK") and shown("in use"), "the list shows the built-in presets and the one in use")
turn(2, -1); turn(2, -1); press(3); check(page.mode == "rows" and ui.state.preset == "WHITE", "E2 K3 in the list picks WHITE")
press(3); press(2); check(page.mode == "rows" and ui.state.preset == "WHITE", "K2 closes the list and changes nothing")
-- the colour row: the picker
turn(2, 1); press(3)
check(picker_opts ~= nil and picker_opts.label == "SCREEN COLOUR" and picker_opts.value == "FFFFFF" and picker_opts.return_page == "UI", "K3 on COLOUR opens the picker with the tint")
calls = {}; picker_opts.preview("00FF00"); check(#calls == 1 and calls[1][3] == 255 and ui.state.tint == "FFFFFF", "the picker's preview is live and stores nothing")
picker_opts.restore(); check(#calls == 2 and calls[2][2] == 255 and calls[2][3] == 255 and calls[2][4] == 255, "restore gives the old colour back")
picker_opts.ok("123456"); check(ui.state.tint == "123456" and page.msg == "saved #123456" and ui.label() == "WHITE~", "ok keeps it: saved #123456, WHITE~")
picker_opts.note("restored"); check(page.msg == "restored", "the picker's note is the page's message")
-- the colour row: Ctrl+C, Ctrl+V
page.redraw(); ctrl_down = true
check(page.keycode("C", 1) == true and clip.copied == "#123456" and page.msg == "copied #123456", "Ctrl+C copies the colour")
check(page.keycode("V", 1) == true and page.msg == "pasting..", "Ctrl+V asks the clipboard")
clip.paste_cb("AABBCC"); check(ui.state.tint == "AABBCC" and page.msg == "pasted #AABBCC", "the pasted colour is kept")
clip.paste_cb(nil, "nothing to paste"); check(page.msg == "nothing to paste", "a failed paste says why")
check(page.keycode("C", 0) == true and page.keycode("X", 1) == false, "a release is used and changes nothing; other keys are the menu's")
turn(2, 1); check(page.keycode("C", 1) == false, "Ctrl+C on another row is the menu's")
turn(2, -1); ctrl_down = false
check(page.keycode("C", 1) == false, "without Ctrl the keys are the menu's")
-- SAVE
fresh(); page.pos = row("SAVE"); press(3)
check(entry ~= nil and entry.heading:find("NAME", 1, true) and entry.opts and entry.opts.accept, "K3 on SAVE opens the name entry")
check(not entry.opts.accept(("x"):rep(19)) and entry.opts.accept("Amber") and not entry.opts.accept("a/b"), "the entry takes only what a name may hold")
ui.set_custom("445566"); entry.cb("Amber"); check(page.msg == "saved: Amber" and ui.label() == "Amber", "a name saves the preset")
check(table.concat(page.rows(), ",") == "PRESET,COLOUR,BRIGHTNESS,CONTRAST,SAVE,DELETE", "DELETE appears for his own preset")
page.pos = row("SAVE"); press(3); entry.cb("amber"); check(page.mode == "confirm", "an existing name asks before overwriting"); page.redraw(); check(shown("OVERWRITE Amber?"), "naming it")
press(2); check(page.mode == "rows" and slurp("/home/we/screen-presets/amber.screen"):find("445566", 1, true), "K2: no")
ui.set_custom("778899"); page.pos = row("SAVE"); press(3); entry.cb("amber"); press(3)
check(page.mode == "rows" and slurp("/home/we/screen-presets/amber.screen"):find("778899", 1, true), "K3: overwritten")
page.pos = row("SAVE"); press(3); entry.cb("white"); check(page.msg ~= nil and page.mode == "rows", "a built-in name is refused with a message: " .. tostring(page.msg))
page.pos = row("SAVE"); press(3); entry.cb(nil); check(page.mode == "rows", "cancelling the entry changes nothing")
-- DELETE
page.pos = row("DELETE"); press(3); check(page.mode == "confirm", "K3 on DELETE asks once"); page.redraw(); check(shown("DELETE Amber?"), "naming the preset")
press(2); check(slurp("/home/we/screen-presets/amber.screen") ~= nil and page.mode == "rows", "K2: kept")
press(3); press(3); check(slurp("/home/we/screen-presets/amber.screen") == nil and page.mode == "rows" and #page.rows() == 5, "K3 then K3 deletes it, DELETE is gone")
fresh(); check(row("DELETE") == nil, "no DELETE for a built-in preset")
-- the list marks his own
ui.set_custom("101010"); ui.save_preset("Mine"); page.pos = 1; press(3); page.redraw()
check(shown("MY PRESETS") and shown("* Mine"), "his own presets are marked: " .. table.concat(texts, " | "))
press(2)
-- every key and encoder ends with a redraw, whatever the mode (the checks are in press / turn); an error in a handler leaves the page whole
local real_set = ui.select_preset
ui.select_preset = function() error("boom") end
page.pos = 1; turn(3, 1); check(logged("boom") and page.mode == "rows", "an error in a handler is logged and the page is whole")
ui.select_preset = real_set
-- a screen preset never touched the box
check(box_calls == 0, "the whole session never called _norns.box_look")

print = real_print
os.execute("rm -rf '" .. tmp .. "'")
if fails == 0 then print("ui_screen_test: all passed") end
os.exit(fails == 0 and 0 or 1)
