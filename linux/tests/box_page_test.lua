-- SYSTEM > BOX (lua/core/menu/box.lua, docs/port/box-style-plan.md 2.6, 2.7, test 6): the rows, E2 / E3 / K3 / K2, the hex rows through the text entry, STYLE, PRESET with its list and the markers,
-- SAVE (name validation, overwrite only after K3 on the question), DELETE (only for his own look, one confirmation, built-in protected), scrolling with a long list and cutting a long name, and the
-- page being in SYSTEM's list below UI on a computer. run from the repo root:  lua5.3 linux/tests/box_page_test.lua
package.path = "lua/?.lua;lua/core/?.lua;lua/lib/?.lua;" .. package.path
local tmp = os.tmpname()
os.remove(tmp)
os.execute("mkdir -p " .. tmp)
local real_open, real_remove, real_rename = io.open, os.remove, os.rename
local function map(p) return (p:gsub("^/home/we", tmp)) end
io.open = function(p, m) return real_open(map(p), m) end
os.remove = function(p) return real_remove(map(p)) end
os.rename = function(a, b) return real_rename(map(a), map(b)) end
local real_execute = os.execute
os.execute = function(cmd) return real_execute((cmd:gsub("/home/we", tmp))) end

local fails = 0
local function check(ok, what) if not ok then fails = fails + 1; print("FAIL " .. what) end end
local function slurp(p) local h = real_open(map(p)); if not h then return nil end local c = h:read("a"); h:close(); return c end
local function exists(p) local h = real_open(map(p)); if h then h:close() return true end return false end

-- the menu environment: the screen records the text of one redraw with its row and level
local lines, calls = {}, 0
local cur_y, cur_level = 0, 15
screen = setmetatable({}, {__index = function() return function() end end})
screen.clear = function() lines = {} end
screen.level = function(l) cur_level = l end
screen.move = function(x, y) cur_y = y end
screen.text = function(s) lines[#lines + 1] = {s = s, y = cur_y, level = cur_level, right = false} end
screen.text_right = function(s) lines[#lines + 1] = {s = s, y = cur_y, level = cur_level, right = true} end
screen.text_extents = function(s) return #s * 5 end
screen.update = function() calls = calls + 1 end
local pushed = {}
_menu = {redraw = function() end, set_page = function(p) pushed[#pushed + 1] = p end}
norns = {none = function() end}
norns.menu = {status = function() return true end, get_key = function() return norns.menu.key end, set = function(e, k) norns.menu.key = k end}
util = {
  clamp = function(x, lo, hi) return math.max(lo, math.min(hi, x)) end,
  scandir = function(dir) local out = {} local p = io.popen("ls -p '" .. map(dir) .. "' 2>/dev/null") for l in p:lines() do out[#out + 1] = l end p:close() return out end,
}
package.loaded.util = util
local entry, opened
package.loaded.textentry = {enter = function(cb, default, title, hint, opts) entry = {cb = cb, default = default, title = title, hint = hint, accept = opts and opts.accept} end}
local sent
_norns = {box_look = function(...) sent = {...} end}
_path = {keyboard_layout = "/nonexistent/keyboard.layout"}
package.loaded['core/menu/picker'] = {open = function(o) opened = o end, take_returning = function() return false end}
local box = require 'core/box_settings'
local logs = {}
box.log = function(s) logs[#logs + 1] = s end
local page = dofile("lua/core/menu/box.lua")
norns.menu.key = page.key

local function shown(s) for _, l in ipairs(lines) do if l.s:find(s, 1, true) then return l end end return nil end
local function row_names() local r = page.rows() local out = {} for _, n in ipairs(r) do out[#out + 1] = n end return table.concat(out, ",") end
local function start()
  os.execute("rm -rf '" .. tmp .. "'/box.conf '" .. tmp .. "'/box-presets")
  box.load()
  page.init()
  page.redraw()
end
local function goto_row(name)
  for i, n in ipairs(page.rows()) do if n == name then page.pos = i end end
  page.redraw()
end
local function press(n) page.key(n, 1); page.key(n, 0); page.redraw() end

-- ---- the rows ----
start()
check(row_names() == "STYLE,PRESET,BOX,KEYS,ENCODERS,BUTTONS,FONT,SAVE", "the rows: " .. row_names())
check(shown("STYLE") and shown("ALUMINIUM"), "STYLE shows ALUMINIUM by default")
check(shown("PRESET") and shown("MAC"), "PRESET shows the default look MAC")
check(shown("#D1D4D8"), "BOX shows its hex")
local visible = 0
for _, l in ipairs(lines) do if not l.right and l.y < 60 then visible = visible + 1 end end
check(visible == 6, "six rows are visible at a time (" .. visible .. ")")
check(shown("E2 row") ~= nil, "the hint line")
check(shown("STYLE").level == 15 and shown("PRESET").level < 15, "the chosen row is the bright one")
page.enc(2, 1)
page.redraw()
check(shown("PRESET").level == 15, "E2 moves to PRESET")
page.enc(2, -5)
check(page.pos == 1, "E2 stops at the top")
page.enc(2, 50)
check(page.pos == 8, "E2 stops at the bottom: SAVE")
page.redraw()
check(shown("SAVE") and not shown("STYLE"), "the list scrolls with the cursor: SAVE is on the screen, STYLE is not")

-- ---- STYLE ----
start()
page.enc(3, 1)
check(box.state.style == "pixel" and box.state.preset == "MAC" and box.state.colours.box == "D1D4D8", "E3 on STYLE: pixel, the colours are not touched")
check(sent and sent[1] == 1, "applied at once")
page.redraw()
check(shown("PIXEL"), "STYLE shows PIXEL")
page.enc(3, -1)
check(box.state.style == "aluminium", "E3 back: aluminium")
page.enc(3, 0)
check(box.state.style == "aluminium", "a delta of 0 changes nothing")

-- ---- PRESET: E3 steps, K3 opens the list ----
start()
box.select_look("DARK")
goto_row("PRESET")
page.enc(3, 1)
check(box.state.preset == "LIGHT" and box.state.style == "aluminium", "E3 on PRESET: the next look, the style stays")
page.redraw()
check(shown("LIGHT"), "the row shows LIGHT")
box.set_part("box", "112233")
page.redraw()
check(shown("LIGHT~"), "a changed colour: LIGHT~")
press(3)
check(page.mode == "list", "K3 on PRESET opens the list")
check(shown("DARK") and shown("LIGHT") and shown("COLOUR") and shown("MAC"), "the list has the four built-in looks")
check(not shown("MY PRESETS"), "no separator while he has no look of his own")
press(2)
check(page.mode == "rows" and #pushed == 0, "K2 in the list goes back to the rows (not out of the page)")
-- his own looks: the marker and the separator
box.select_look("COLOUR")
box.save_look("Barn door")
box.save_look("Sunday")
page.init()
goto_row("PRESET")
press(3)
check(shown("- MY PRESETS -") and shown("* Barn door") and shown("* Sunday"), "his looks come after a separator, each with a star")
check(not shown("* DARK") and not shown("* LIGHT"), "the built-in looks carry no star")
check(shown("in use") ~= nil, "the look in use is marked")
check(shown("* Sunday").y > shown("MAC").y, "his looks are listed after the built-in ones")
page.enc(2, 10)
page.redraw()
check(shown("* Sunday").level == 15, "E2 moves down to the last look (the separator is skipped)")
press(3)
check(page.mode == "rows" and box.state.preset == "Sunday", "K3 uses the look and returns to the rows")
check(shown("* Sunday") ~= nil, "the PRESET row says * Sunday for his own look")

-- ---- hex rows: K3 opens the colour picker (the text entry is reached from inside it: core/menu/picker.lua, linux/tests/picker_test.lua) ----
start()
goto_row("KEYS")
press(3)
check(opened and opened.label == "THEME KEYS" and opened.value == "404246" and opened.return_page == "BOX", "K3 on a colour opens the picker with the label, the current hex and the page to return to")
local conf_before = slurp("/home/we/box.conf")
opened.preview("E8A317")
check(sent and sent[3] == "E8A317", "the picker's preview reaches the window at once")
check(box.state.colours.keys == "404246" and slurp("/home/we/box.conf") == conf_before, "a preview stores and writes nothing")
opened.restore()
check(sent[3] == "404246", "restore gives the stored colour back to the window")
opened.ok("E8A317")
page.redraw()
check(box.state.colours.keys == "E8A317" and shown("#E8A317"), "ok keeps the colour and the row shows it")
check(slurp("/home/we/box.conf"):find("keys=E8A317", 1, true), "and saves it once")
goto_row("BUTTONS")
press(3)
opened.ok("303030")
goto_row("FONT")
press(3)
opened.ok("323232")
page.redraw()
check(box.state.colours.font == "323232" and shown("low contrast"), "a hard to read pair is accepted with a message")
for _, part in ipairs({"BOX", "ENCODERS", "BUTTONS", "FONT"}) do
  goto_row(part)
  opened = nil
  press(3)
  check(opened and opened.label == "THEME " .. part and opened.value:match("^%x%x%x%x%x%x$"), part .. ": K3 opens the picker")
end

-- ---- SAVE ----
start()
goto_row("SAVE")
box.select_look("COLOUR")
press(3)
check(entry and entry.title == "NAME FOR THIS LOOK:", "K3 on SAVE asks for a name with the text entry")
entry.cb("Barn door")
page.redraw()
check(exists("/home/we/box-presets/barn-door.box") and box.state.preset == "Barn door", "a valid name saves the look")
check(shown("saved") ~= nil or shown("Barn door") ~= nil, "the page says so")
check(row_names():find("DELETE", 1, true), "DELETE appears now that his own look is in use")
-- invalid names: a message, nothing written
goto_row("SAVE")
press(3)
entry.cb("a/b")
page.redraw()
check(shown("path characters"), "a name with a path character is refused with the reason")
press(3)
entry.cb("DARK")
page.redraw()
check(shown("built-in"), "a built-in name is refused")
press(3)
entry.cb(string.rep("x", 19))
page.redraw()
check(shown("18 characters"), "a name over 18 characters is refused")
local files = io.popen("ls '" .. tmp .. "/box-presets'"):read("a")
check(files == "barn-door.box\n", "nothing else was written: " .. files:gsub("\n", " "))
press(3)
entry.cb(nil)
check(files == io.popen("ls '" .. tmp .. "/box-presets'"):read("a"), "cancelling the entry writes nothing")
-- overwrite: asks first
box.set_part("keys", "112233")
goto_row("SAVE")
press(3)
entry.cb("BARN DOOR")
page.redraw()
check(page.mode == "confirm" and shown("OVERWRITE") and shown("Barn door"), "an existing name asks: OVERWRITE Barn door?")
check(slurp("/home/we/box-presets/barn-door.box"):find("keys=F2B63D", 1, true), "nothing is written before the answer")
press(2)
check(page.mode == "rows" and slurp("/home/we/box-presets/barn-door.box"):find("keys=F2B63D", 1, true), "K2 = no: the file is as it was")
goto_row("SAVE")
press(3)
entry.cb("BARN DOOR")
press(3)
check(page.mode == "rows" and slurp("/home/we/box-presets/barn-door.box"):find("keys=112233", 1, true), "K3 = yes: the file is written")

-- ---- DELETE ----
start()
box.select_look("COLOUR")
box.save_look("Gone soon")
page.init()
page.redraw()
check(row_names():find("DELETE", 1, true), "DELETE is a row while his own look is in use")
goto_row("DELETE")
check(shown("DELETE") and shown("Gone soon"), "the row names the look")
press(3)
check(page.mode == "confirm" and shown("DELETE Gone soon"), "K3 asks once: DELETE Gone soon?")
check(exists("/home/we/box-presets/gone-soon.box"), "nothing is deleted before the answer")
press(2)
check(page.mode == "rows" and exists("/home/we/box-presets/gone-soon.box"), "K2 = no")
goto_row("DELETE")
press(3)
press(3)
check(not exists("/home/we/box-presets/gone-soon.box"), "K3 = yes deletes the file")
check(not row_names():find("DELETE", 1, true) and box.label() == "CUSTOM", "the row is gone, the colours stay, the label reads CUSTOM")
box.select_look("DARK")
page.redraw()
check(not row_names():find("DELETE", 1, true), "a built-in look has no DELETE row")
check(not (function() local ok = box.delete_look("DARK") return ok end)(), "and cannot be deleted by any other way")

-- ---- a long list and a long name ----
start()
for i = 1, 12 do box.save_look(string.format("Look %02d", i)) end
box.save_look("Eighteen chars long")
box.save_look(string.rep("W", 18))
page.init()
goto_row("PRESET")
press(3)
local count = 0
for _, l in ipairs(lines) do if not l.right and l.y < 60 then count = count + 1 end end
check(count <= 6, "the list shows at most six rows (" .. count .. ")")
page.enc(2, 18)
page.redraw()
local sel
for _, l in ipairs(lines) do if l.level == 15 then sel = l end end
check(sel ~= nil and sel.y < 60, "the chosen row of a long list is always on the screen")
for _, l in ipairs(lines) do
  if not l.right then check(#l.s * 5 <= 128, "no line is wider than the screen: '" .. l.s .. "'") end
end
local wide = false
for _, l in ipairs(lines) do if l.s:find("WWWW", 1, true) then wide = l end end
check(wide and (wide.s:find("..", 1, true) or #wide.s * 5 <= 128 - 35), "a long name is cut with .. or fits next to 'in use'")
page.redraw()

-- ---- K2 leaves the page; the page is in SYSTEM's list below UI, on a computer ----
start()
pushed = {}
press(2)
check(pushed[1] == "SYSTEM", "K2 goes back to SYSTEM")
local sys = slurp_sys or assert(real_open("lua/core/menu/system.lua")):read("a")
check(sys:find('"SCREEN >", "THEME >"', 1, true), "SYSTEM's list has THEME below SCREEN (the visible names of the pages UI and BOX)")
check(sys:find('"UI", "BOX"', 1, true), "SYSTEM's pages keep the ids UI and BOX")
local mn = io.open("lua/core/menu.lua"):read("a")
check(mn:find('m["SCREEN"] = m["UI"]', 1, true) and mn:find('m["THEME"] = m["BOX"]', 1, true), "the page ids SCREEN and THEME are accepted as well")
local menu = assert(real_open("lua/core/menu.lua")):read("a")
check(menu:find("core/menu/box", 1, true) and menu:find("core/box_settings", 1, true), "menu.lua loads the page and the settings on a computer")

os.execute("rm -rf '" .. tmp .. "'")
if fails > 0 then print("box_page_test: " .. fails .. " failed") os.exit(1) end
print("box_page_test: all passed")
