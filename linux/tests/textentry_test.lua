-- the text entry (lua/lib/textentry.lua) as the hex rows of SYSTEM > BOX and SYSTEM > UI use it, and the pages' control after it closes (docs/port/box-style-plan.md, fixes after the owner's test). run from the repo root:
--   NORNS_PLATFORM=1 lua5.3 linux/tests/textentry_test.lua
-- 1. the pile-up: typing past the sixth digit drew the extra characters over the old text and the hint (the hint is right aligned on the same line as the text); now a hex entry accepts at most 6 hex digits
--    (and an optional #), refuses anything else with a short visible hint, redraws cleanly (the screen is cleared and the text of a long entry is cut at the left, never wider than the screen),
--    and the first typed character replaces the code that was shown. other uses of the entry (names) get the same clean layout; the device (no NORNS_PLATFORM) is exactly as before
-- 2. the page stuck: after EVERY way of closing the entry (Return, Esc, OK, K2, with an over-long input, closed twice, opened twice) the page owns the keys again, the keyboard hooks of the entry are
--    off, and E2 / K2 / E3 / K3 work; a second enter while one is open is ignored (it used to save the entry's own handlers as the ones to restore)
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

-- the screen: what one redraw draws (the screen is cleared first), with x, y and the text; the width of a text is 5 per character
local drawn, cleared = {}, 0
local cx, cy, clevel = 0, 0, 15
screen = setmetatable({}, {__index = function() return function() end end})
screen.clear = function() drawn = {}; cleared = cleared + 1 end
screen.level = function(l) clevel = l end
screen.move = function(x, y) cx, cy = x, y end
screen.text = function(s) drawn[#drawn + 1] = {s = s, x = cx, y = cy, w = #s * 5, right = false} end
screen.text_right = function(s) drawn[#drawn + 1] = {s = s, x = cx - #s * 5, y = cy, w = #s * 5, right = true} end
screen.text_extents = function(s) return #s * 5 end
screen.update = function() end
screen.ping = function() end
local function shown(s) for _, d in ipairs(drawn) do if d.s == s then return d end end return nil end
local function line(y) local out = {} for _, d in ipairs(drawn) do if d.y == y then out[#out + 1] = d end end return out end

-- the menu API of lua/core/menu.lua (copied: the real menu needs the whole norns)
_menu = {mode = true}
norns = {none = function() end}
norns.menu = {}
norns.menu.status = function() return _menu.mode end
local current_page
norns.menu.init = function() if _menu.mode and current_page then norns.menu.set(current_page.enc, current_page.key, current_page.redraw, nil) end end -- _menu.set_mode(_menu.mode) puts the page back
norns.menu.set = function(e, k, r, f) _menu.penc, _menu.key, _menu.redraw, _menu.refresh = e, k, r, f end
norns.menu.get_enc = function() return _menu.penc end
norns.menu.get_key = function() return _menu.key end
norns.menu.get_redraw = function() return _menu.redraw end
norns.menu.get_refresh = function() return _menu.refresh end
_menu.set_page = function(p) _menu.last_page = p end
util = {clamp = function(x, lo, hi) return math.max(lo, math.min(hi, x)) end,
  scandir = function(dir) local out = {} local p = io.popen("ls -p '" .. map(dir) .. "' 2>/dev/null") for l in p:lines() do out[#out + 1] = l end p:close() return out end}
package.loaded.util = util
-- the real keyboard module is not needed: the entry is driven through its keyboard hooks (te_kbd) and its key / enc handlers, as the menu does
package.loaded["core/keyboard"] = {state = {}}
local te_kbd = require 'lib/textentry_kbd'
local te = require 'textentry'
local box = require 'core/box_settings'
box.log = function() end
local ui = require 'core/ui_settings'
ui.log = function() end
_norns = {box_look = function() end}
local page = dofile("lua/core/menu/box.lua")
local uipage = dofile("lua/core/menu/ui.lua")

local function type_text(s) for c in s:gmatch(".") do te_kbd.char(c) end end
local function press_code(code) -- a key like Return: the keyboard sets the state, then calls the hook (the entry looks at the state)
  -- the keyboard module calls the hook first and sets the state after it: the press sees the old state, the release sees the key as down
  local kb = package.loaded["core/keyboard"]
  if te_kbd.code then te_kbd.code(code, 1) end
  kb.state[code] = true
  if te_kbd.code then te_kbd.code(code, 0) end
  kb.state[code] = false
end
local function owner_is(p) return norns.menu.get_key() == p.key and norns.menu.get_enc() == p.enc end

local function fresh_box()
  os.execute("rm -rf '" .. tmp .. "'/box.conf '" .. tmp .. "'/box-presets '" .. tmp .. "'/ui.conf")
  box.load()
  ui.load()
  page.init()
  norns.menu.set(page.enc, page.key, page.redraw, nil)
  current_page = page
  page.pos = 4 -- KEYS
  page.redraw()
end

-- ---- 1. the pile-up ----
fresh_box()
page.key(3, 1) page.key(3, 0)
check(te.active == true and not owner_is(page), "the entry is open and has the keys")
check(shown("#404246") ~= nil, "the entry starts with the code that is set")
type_text("4")
check(shown("4") ~= nil and shown("#404246") == nil, "the first typed character replaces the code that was shown")
type_text("0424B")
check(shown("40424B") ~= nil, "six digits: 40424B")
local before = shown("40424B")
type_text("7")
check(shown("40424B") ~= nil and not shown("40424B7"), "a seventh digit is refused")
check(te.txt == "40424B", "the text is still six digits: '" .. tostring(te.txt) .. "'")
local hint
for _, d in ipairs(drawn) do if d.s:find("6 digits max", 1, true) then hint = d end end
check(hint ~= nil, "the refusal says so on the screen: 6 digits max")
check(hint and hint.y ~= shown("40424B").y, "the hint is on a line of its own, not on the text's line")
for i = 1, 30 do type_text("7") end
check(te.txt == "40424B", "thirty more digits: still six")
type_text("g")
check(te.txt == "40424B" and (function() for _, d in ipairs(drawn) do if d.s:find("0-9", 1, true) or d.s:find("a-f", 1, true) then return true end end end)(), "a letter that is not a hex digit is refused with a hint")
type_text("#")
check(te.txt == "40424B", "a # after digits is refused")
-- every redraw is a clean one: the screen is cleared first, nothing is drawn twice, no two texts overlap on a line
local c0 = cleared
type_text("z")
check(cleared == c0 + 1, "one clear per redraw")
local seen = {}
for _, d in ipairs(drawn) do
  local k = d.y .. ":" .. d.x .. ":" .. d.s
  check(not seen[k], "nothing is drawn twice: " .. k)
  seen[k] = true
end
local rows = {}
for _, d in ipairs(drawn) do
  if d.y == 32 or d.y == 24 or d.y == 16 then
    for _, o in ipairs(rows[d.y] or {}) do
      check(d.x >= o.x + o.w or o.x >= d.x + d.w, "two texts overlap on line " .. d.y .. ": '" .. o.s .. "' and '" .. d.s .. "'")
    end
    rows[d.y] = rows[d.y] or {}
    table.insert(rows[d.y], d)
  end
  check(d.x >= 0 and d.x + d.w <= 128 or d.y == 46, "'" .. d.s .. "' fits the screen (x " .. d.x .. ", width " .. d.w .. ")")
end
-- a # first, then digits, are fine; backspace works
package.loaded["core/keyboard"].state.BACKSPACE = true
te_kbd.code("BACKSPACE", 1)
package.loaded["core/keyboard"].state.BACKSPACE = false
check(te.txt == "40424", "backspace removes a digit: " .. te.txt)
-- finish with Return: the code is set
press_code("ENTER")
check(te.active == false and owner_is(page), "Return closes the entry, the page has the keys")
check(box.state.colours.keys == "404246" and page.msg ~= nil and page.msg:find("bad hex", 1, true), "five digits are not a code: refused with a message, the colour kept (" .. box.state.colours.keys .. ")")

-- typing "#40424B" with the hash is fine too, and 3 digits
fresh_box()
page.key(3, 1) page.key(3, 0)
type_text("#f80")
check(te.txt == "#f80", "# and three digits are accepted: " .. te.txt)
press_code("ENTER")
check(box.state.colours.keys == "FF8800", "#f80 is FF8800")

-- other uses of the entry: a long name. the screen is cleared, the text is cut at the left, nothing runs past the screen; the device layout is untouched (below)
te.enter(function() end, "", "NAME:", function(t) return #t > 10 and "long name" or nil end)
type_text("a very long name that goes on and on and on")
local widest = 0
for _, d in ipairs(drawn) do if d.y == 32 then widest = math.max(widest, d.x + d.w) end end
check(widest <= 128, "a long name is cut at the left, it never runs past the screen (" .. widest .. ")")
local w
for _, d in ipairs(drawn) do if d.s == "long name" then w = d end end
check(w ~= nil and w.y ~= 32, "the warning of a name check is on its own line too")
press_code("ESC")
check(te.active == false, "Esc closes it")

-- ---- 2. the page after every way of closing ----
local function navigates(p, label)
  p.init()
  norns.menu.set(p.enc, p.key, p.redraw, nil)
  current_page = p
  p.pos = 1
  local k_ok = owner_is(p)
  p.enc(2, 1)
  check(k_ok and p.pos == 2, label .. ": E2 moves the cursor (pos " .. tostring(p.pos) .. ")")
end
local closers = {
  ["Return"] = function() press_code("ENTER") end,
  ["Esc"] = function() press_code("ESC") end,
  ["OK row (E3 right, K3)"] = function() te.enc(3, 1); te.key(3, 1); te.key(3, 0) end,
  ["K2"] = function() te.key(2, 1); te.key(2, 0) end,
  ["K2 pressed only (release lost)"] = function() te.key(2, 1); te.key(2, 0) end,
}
local inputs = {["a valid code"] = "336699", ["nothing typed"] = "", ["an over-long input"] = string.rep("7", 40), ["letters"] = "zzzz"}
for cname, close in pairs(closers) do
  for iname, input in pairs(inputs) do
    local label = cname .. " after " .. iname .. ", BOX"
    fresh_box()
    page.key(3, 1) page.key(3, 0)
    type_text(input)
    close()
    check(te.active == false and te_kbd.code == nil and te_kbd.char == nil, label .. ": the entry is off and its keyboard hooks are off")
    check(owner_is(page), label .. ": the page owns the keys and encoders again")
    page.pos = 4
    page.enc(2, 1)
    check(page.pos == 5, label .. ": E2 moves (pos " .. page.pos .. ")")
    page.enc(2, -1)
    page.enc(3, 1)
    page.redraw()
    check(shown("KEYS") ~= nil or shown("BUTTONS") ~= nil, label .. ": the page draws")
    -- K3 opens the entry again, K2 leaves the page
    page.key(3, 1) page.key(3, 0)
    check(te.active == true, label .. ": K3 opens the entry again")
    te.key(2, 1) te.key(2, 0)
    check(not te.active, label .. ": and it closes again")
    page.key(2, 1)
    check(_menu.last_page == "SYSTEM", label .. ": K2 leaves the page")
    _menu.last_page = nil
  end
end
-- the same on the UI page's HEX row
for cname, close in pairs(closers) do
  for iname, input in pairs(inputs) do
    local label = cname .. " after " .. iname .. ", UI"
    os.execute("rm -f '" .. tmp .. "'/ui.conf")
    ui.load()
    uipage.init()
    norns.menu.set(uipage.enc, uipage.key, uipage.redraw, nil)
    current_page = uipage
    uipage.pos = 4 -- HEX
    uipage.key(3, 1) uipage.key(3, 0)
    check(te.active == true, label .. ": the HEX row opens the entry")
    type_text(input)
    close()
    check(te.active == false and te_kbd.code == nil and owner_is(uipage), label .. ": the UI page has the keys again")
    uipage.enc(2, -1)
    check(uipage.pos == 3, label .. ": E2 moves (pos " .. uipage.pos .. ")")
    check(#(ui.state.custom or "") <= 6, label .. ": the custom colour is never longer than 6 digits")
  end
end

-- opened twice: the second enter is ignored, the first one's restore stays right
fresh_box()
page.key(3, 1) page.key(3, 0)
local first_txt = te.txt
te.enter(function() print("PROBE second callback must not run") end, "x", "SECOND", nil)
check(te.txt == first_txt and te.heading ~= "SECOND", "a second enter while one is open is ignored")
check(norns.menu.get_key() == te.key, "the entry still has the keys")
te.key(2, 1) te.key(2, 0)
check(owner_is(page) and te.active == false, "closing it gives the keys back to the page, not to the entry")
page.enc(2, 1)
check(page.pos == 5, "and the page navigates")
-- closed twice: harmless
te.exit()
check(owner_is(page), "exit() when nothing is open changes nothing")
-- the menu was left while the entry was open (the box key mode): the keys come back right
fresh_box()
page.key(3, 1) page.key(3, 0)
_menu.mode = false
local saved_key = key
te.key(2, 1) te.key(2, 0)
_menu.mode = true
check(te.active == false and te_kbd.code == nil, "closed after the menu mode changed under it")

-- ---- the device: without NORNS_PLATFORM nothing of this changes ----
local src = assert(real_open("lua/lib/textentry.lua")):read("a")
check(src:find('os.getenv("NORNS_PLATFORM")', 1, true) ~= nil, "the new behaviour is behind the computer check (NORNS_PLATFORM)")
os.execute("rm -rf '" .. tmp .. "'")
-- the keyboard equivalents of the hardware controls (arrows, value keys) are behind NORNS_PLATFORM: the device's entry is upstream's
do
  local src = io.open("lua/lib/textentry.lua"):read("a")
  check(src:find("if not desktop or not te.active or value == 0 then", 1, true) ~= nil, "the entry's navigation keys do nothing unless desktop")
  check(src:find("if desktop and te.skip_char then", 1, true) ~= nil, "the value-key character skip is behind desktop")
end
if fails > 0 then print("textentry_test: " .. fails .. " failed") os.exit(1) end
print("textentry_test: all passed")
