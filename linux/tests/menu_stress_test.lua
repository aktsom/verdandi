-- the THEME (BOX) and SCREEN (UI) pages under thousands of random key, encoder and page events, through the real keyboard module, the real text entry and the menu's own key bindings
-- (_menu.keycode, cut out of lua/core/menu.lua) and its set_page / norns.menu.set handler rules. after every event the invariants are checked:
--   1 the entry's keyboard hooks are set exactly while an entry is open        2 the page's own key / enc / redraw handlers are the installed ones (the entry's while it is open)
--   3 the selection is in range and on a selectable row (the list: not on its separator)       4 the modal flags agree (confirm only in confirm mode)
--   5 THE SCREEN SHOWS THE STATE: what the last redraw drew is what a redraw now would draw (a state change without a redraw looks like a page that does not react)
--   6 the row list matches the state (DELETE only for an own look in use)        7 no handler raises an error
--   8 every few events: ESC, at most 4 times, always leaves the page and ends every modal state
-- a failure is shrunk to a short sequence and printed with the page state after each event. run from the repo root:
--   NORNS_PLATFORM=linux NORNS_HARDWARE_KEYS=1 lua5.3 linux/tests/menu_stress_test.lua [seeds [events]] | trace
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
local TRACE = arg and arg[1] == "trace"
local SEEDS = tonumber(arg and arg[1]) or 40
local EVENTS = tonumber(arg and arg[2]) or 400
local real_print = print
local printed = {}
print = function(...) local a = ... if type(a) == "string" and a:find("error loading keyboard layout", 1, true) then return end printed[#printed + 1] = tostring(a) real_print(...) end

local function write(path, text) local h = real_open(map(path), "w"); h:write(text); h:close() end
local function own_look(name, a, b)
  local slug = name:lower():gsub("[^%w]+", "-")
  os.execute("mkdir -p /home/we/box-presets")
  write("/home/we/box-presets/" .. slug .. ".box", "verdandi-box=1\nname=" .. name .. "\nbox=" .. a .. "\nkeys=" .. b .. "\nencoders=" .. a .. "\nbuttons=" .. b .. "\nfont=FFFFFF\n")
end

-- a fresh world: new modules, new state, an own look or two on disk
local W
local function world()
  os.execute("rm -rf '" .. tmp .. "'/box.conf '" .. tmp .. "'/ui.conf '" .. tmp .. "'/box-presets")
  for _, k in ipairs({"core/keyboard", "lib/textentry_kbd", "textentry", "lib/textentry", "core/box_settings", "core/ui_settings", "box_settings", "ui_settings", "keyboard"}) do package.loaded[k] = nil end
  local w = {frame = {}, shown = {}, errors = {}, logs = {}}
  screen = setmetatable({}, {__index = function() return function() end end})
  screen.clear = function() w.frame = {} end
  screen.text = function(s) w.frame[#w.frame + 1] = "L:" .. tostring(s) end
  screen.text_right = function(s) w.frame[#w.frame + 1] = "R:" .. tostring(s) end
  screen.text_extents = function(s) return #tostring(s) * 5 end
  screen.update = function() w.shown = w.frame end
  screen.ping = function() end
  util = {clamp = function(x, lo, hi) return math.max(lo, math.min(hi, x)) end,
    scandir = function(dir) local out = {} local p = io.popen("ls -p '" .. map(dir) .. "' 2>/dev/null") for l in p:lines() do out[#out + 1] = l end p:close() return out end}
  package.loaded.util = util
  _norns = {box_look = function() end, ui_look = function() end, show_control = function() end,
    key = function(n, z) if n ~= 1 then _menu.key(n, z) end end, enc = function(n, d) if n ~= 1 then _menu.penc(n, d) end end}
  write("/home/we/keyboard.layout", "us\n")
  _path = {keyboard_layout = "/home/we/keyboard.layout"}
  norns = {none = function() end}
  _menu = {mode = true, page = "SYSTEM", goto_panel = function() end, set_mode = function() end}
  norns.menu = {}
  norns.menu.init = function() end
  norns.menu.status = function() return _menu.mode end
  norns.menu.set = function(e, k, r, f) _menu.penc, _menu.key, _menu.redraw, _menu.refresh = e, k, r, f end
  norns.menu.get_enc = function() return _menu.penc end
  norns.menu.get_key = function() return _menu.key end
  norns.menu.get_redraw = function() return _menu.redraw end
  norns.menu.get_refresh = function() return _menu.refresh end
  require 'core/keyboard'
  w.keyboard = keyboard
  w.te_kbd = require 'lib/textentry_kbd'
  w.textentry = require 'textentry'
  w.box = require 'core/box_settings'
  w.ui = require 'core/ui_settings'
  w.box.log = function(s) w.logs[#w.logs + 1] = s end
  w.ui.log = function(s) w.logs[#w.logs + 1] = s end
  -- the menu's own key bindings
  local src = io.open("lua/core/menu.lua"):read("a")
  local block = src:match("(%-%- global menu keys\nfunction _menu%.keycode.-)\nfunction _menu%.keychar")
  assert(block, "_menu.keycode not found in lua/core/menu.lua")
  load(block)()
  function _menu.keychar(c) if _menu.keyboardchar then _menu.keyboardchar(c) end end
  w.pages = {SYSTEM = {init = function() end, deinit = function() end, key = function() end, enc = function() end, redraw = function() screen.clear() screen.text("SYSTEM") screen.update() end},
    BOX = dofile("lua/core/menu/box.lua"), UI = dofile("lua/core/menu/ui.lua")}
  w.pages.BOX.msg_log = nil
  _menu.set_page = function(p)
    w.pages[_menu.page].deinit()
    _menu.page = p
    local pg = w.pages[p]
    _menu.key, _menu.penc, _menu.redraw, _menu.refresh = pg.key, pg.enc, pg.redraw, pg.refresh
    _menu.keyboardcode, _menu.keyboardchar = pg.keycode, pg.keychar
    pg.init()
    _menu.redraw()
  end
  own_look("Alpha", "112233", "445566")
  own_look("Beta", "AA3300", "00AA33")
  w.box.load()
  w.codes = {}
  for k, v in pairs(keyboard.codes) do w.codes[v] = k end
  return w
end

local function send(w, name, v) w.keyboard.process(1, w.codes[name], v) end
local function tap(w, name, repeats)
  send(w, name, 1)
  for _ = 1, repeats or 0 do send(w, name, 2) end
  send(w, name, 0)
end

-- one event: {k = "tap" name repeats} | {k = "press" name} | {k = "release" name} | {k = "enc" n d} | {k = "page" p} | {k = "ext" what}
local function apply(w, e)
  if e.k == "tap" then tap(w, e.name, e.rep)
  elseif e.k == "press" then send(w, e.name, 1)
  elseif e.k == "release" then send(w, e.name, 0)
  elseif e.k == "enc" then _norns.enc(e.n, e.d)
  elseif e.k == "page" then
    if w.textentry.active then return end -- the menu does not change pages under an open entry (its keys are the entry's)
    _menu.set_page(e.p)
  elseif e.k == "ext" then
    if e.what == "drop" then os.remove("/home/we/box-presets/alpha.box") w.box.reload_looks()
    elseif e.what == "add" then own_look("Gamma", "336699", "996633") w.box.reload_looks() end
    _menu.redraw() -- the change comes from outside the page; whatever triggers the next redraw finds the page in range
  end
end

local function fmt(e)
  if e.k == "tap" then return "tap " .. e.name .. ((e.rep or 0) > 0 and ("+" .. e.rep .. "rep") or "")
  elseif e.k == "enc" then return "enc " .. e.n .. " " .. e.d
  elseif e.k == "page" then return "page " .. e.p
  elseif e.k == "ext" then return "ext " .. e.what end
  return e.k .. " " .. e.name
end

local function state_of(w)
  local p, pg = _menu.page, w.pages[_menu.page]
  local s = p
  if p == "BOX" then s = s .. string.format(" mode=%s pos=%s top=%s lpos=%s rows=%d", pg.mode, pg.pos, pg.top, pg.lpos, #pg.rows())
  elseif p == "UI" then s = s .. " pos=" .. tostring(pg.pos) end
  return s .. " entry=" .. tostring(w.textentry.active)
end

local function frame_text(f) return table.concat(f, "|") end

-- the invariants: nil, or "name: what"
local function invariants(w)
  local p, pg = _menu.page, w.pages[_menu.page]
  if (w.te_kbd.code ~= nil) ~= (w.textentry.active == true) then return "hooks: the entry's keyboard hooks and its active flag disagree" end
  if w.textentry.active then
    if _menu.key ~= w.textentry.key then return "handlers: an entry is open but the key handler is not the entry's" end
  else
    if _menu.key ~= pg.key then return "handlers: the key handler is not the page's own (" .. p .. ")" end
    if _menu.penc ~= pg.enc then return "handlers: the enc handler is not the page's own (" .. p .. ")" end
    if _menu.redraw ~= pg.redraw then return "handlers: the redraw handler is not the page's own (" .. p .. ")" end
  end
  if p == "BOX" then
    if pg.mode ~= "rows" and pg.mode ~= "list" and pg.mode ~= "confirm" then return "modal: unknown mode " .. tostring(pg.mode) end
    if (pg.mode == "confirm") ~= (pg.confirm ~= nil) then return "modal: the confirm flag and the mode disagree" end
    local rows = pg.rows()
    if pg.mode == "rows" and not (pg.pos >= 1 and pg.pos <= #rows) then return "selection: row " .. pg.pos .. " of " .. #rows end
    if pg.mode == "rows" and not (pg.top >= 1 and pg.top <= math.max(1, #rows)) then return "selection: top " .. pg.top end
    local l = w.box.look_by_name(w.box.state.preset)
    local own = l ~= nil and not l.builtin and w.box.state.preset ~= "CUSTOM"
    if (rows[#rows] == "DELETE") ~= own then return "rows: DELETE does not match the look in use (" .. tostring(w.box.state.preset) .. ")" end
    if pg.mode == "list" then
      local builtin = #w.box.look_list() - #w.box.own
      local n = builtin + (#w.box.own > 0 and 1 + #w.box.own or 0)
      if pg.lpos < 1 or pg.lpos > n then return "selection: list position " .. pg.lpos .. " of " .. n end
      if #w.box.own > 0 and pg.lpos == builtin + 1 then return "selection: the list position is on the separator" end
    end
  elseif p == "UI" then
    if not (pg.pos >= 1 and pg.pos <= 4) then return "selection: UI row " .. tostring(pg.pos) end
  end
  -- the screen shows the state: a redraw now draws what the last one drew
  local before = frame_text(w.shown)
  _menu.redraw()
  local after = frame_text(w.shown)
  if before ~= after then return "screen: the page changed but did not redraw (was: " .. before:sub(1, 60) .. " | now: " .. after:sub(1, 60) .. ")" end
  return nil
end

-- ESC at most 4 times leaves the page and ends every modal state
local function escape_check(w)
  for _ = 1, 4 do
    if _menu.page == "SYSTEM" and not w.textentry.active then break end
    tap(w, "ESC")
  end
  if _menu.page ~= "SYSTEM" or w.textentry.active then return "liveness: 4 times ESC did not leave the page (" .. state_of(w) .. ")" end
  return nil
end

-- run a list of events; returns nil or {index, message, trace}
local function run(events, trace)
  local w = world()
  _menu.set_page("BOX")
  local lines = {}
  for i, e in ipairs(events) do
    local ok, err = pcall(apply, w, e)
    local msg = not ok and ("error: " .. tostring(err)) or invariants(w)
    if not msg and i % 25 == 0 then
      local w2msg = escape_check(w)
      if w2msg then msg = w2msg else _menu.set_page((i // 25) % 2 == 0 and "BOX" or "UI") end
    end
    if trace then lines[#lines + 1] = string.format("%3d %-22s -> %s", i, fmt(e), state_of(w) .. (msg and ("   <-- " .. msg) or "")) end
    if msg then return {index = i, message = msg, trace = lines} end
  end
  return nil, lines
end

-- the generator
local KEYS = {"UP", "DOWN", "LEFT", "RIGHT", "EQUAL", "MINUS", "ENTER", "ESC", "BACKSPACE", "SPACE", "1", "2", "3", "Q", "W", "A", "S", "Z", "X", "PAGEUP", "PAGEDOWN",
  "4", "5", "6", "7", "8", "9", "0", "B", "C", "D", "E", "F", "H", "RIGHT", "RIGHT", "DOWN", "UP", "3", "2"}
local function pick(t) return t[math.random(#t)] end
local function gen(n)
  local ev = {}
  for i = 1, n do
    local r = math.random(100)
    if r <= 58 then ev[i] = {k = "tap", name = pick(KEYS), rep = math.random(4) == 1 and math.random(3) or 0}
    elseif r <= 66 then ev[i] = {k = "press", name = pick(KEYS)}
    elseif r <= 74 then ev[i] = {k = "release", name = pick(KEYS)}
    elseif r <= 88 then ev[i] = {k = "enc", n = math.random(2, 3), d = pick({-5, -2, -1, 0, 1, 1, 2, 5})}
    elseif r <= 95 then ev[i] = {k = "page", p = pick({"BOX", "UI", "SYSTEM", "BOX"})}
    else ev[i] = {k = "ext", what = pick({"drop", "add"})} end
  end
  return ev
end

local function shrink(events, key)
  local function fails(list) local f = run(list); return f and f.message:match("^(%a+):") == key end
  local cur = events
  local chunk = math.max(1, #cur // 2)
  while chunk >= 1 do
    local i, progressed = 1, false
    while i <= #cur do
      local try = {}
      for j = 1, #cur do if j < i or j >= i + chunk then try[#try + 1] = cur[j] end end
      if #try > 0 and fails(try) then cur = try progressed = true else i = i + chunk end
    end
    if not progressed then chunk = chunk // 2 end
  end
  return cur
end

local fails_total = 0
local function report(events, f, label)
  local key = f.message:match("^(%a+):")
  local small = shrink({table.unpack(events, 1, f.index)}, key)
  print(string.format("FAIL %s: %s", label, f.message))
  print("  shortest sequence (" .. #small .. " events):")
  local r = run(small, true)
  for _, l in ipairs(r and r.trace or {}) do print("  " .. l) end
  fails_total = fails_total + 1
end

if TRACE then
  -- the owner's sequence: open THEME, select PRESET, RIGHT (K3) several times, value keys, then up / down
  local seq = {{k = "tap", name = "DOWN"}, {k = "tap", name = "RIGHT"}, {k = "tap", name = "DOWN"}, {k = "tap", name = "DOWN"}, {k = "tap", name = "LEFT"}, {k = "tap", name = "EQUAL"}, {k = "tap", name = "UP"}}
  local f, lines = run(seq, true)
  for _, l in ipairs(f and f.trace or lines or {}) do print(l) end
  os.exit(f and 1 or 0)
end

for seed = 1, SEEDS do
  math.randomseed(seed)
  local ev = gen(EVENTS)
  local f = run(ev)
  if f then report(ev, f, "seed " .. seed) break end
end

-- regression sequences: the owner's (RIGHT on PRESET opens the list: the screen must show it, up/down move it, K3 uses it, K2 closes it)
local owner = {{k = "tap", name = "DOWN"}, {k = "tap", name = "RIGHT"}, {k = "tap", name = "DOWN"}, {k = "tap", name = "DOWN"}, {k = "tap", name = "RIGHT"}, {k = "tap", name = "DOWN"},
  {k = "tap", name = "UP"}, {k = "tap", name = "RIGHT"}, {k = "tap", name = "LEFT"}, {k = "tap", name = "DOWN"}, {k = "tap", name = "EQUAL"}, {k = "tap", name = "DOWN"}}
local f = run(owner)
if f then report(owner, f, "owner sequence") end
for _, name in ipairs({"RIGHT", "ENTER", "SPACE", "3"}) do
  local seq = {{k = "tap", name = "DOWN"}, {k = "tap", name = name}, {k = "tap", name = "DOWN"}, {k = "tap", name = "UP"}, {k = "tap", name = "2"}, {k = "tap", name = "DOWN"}}
  local f2 = run(seq)
  if f2 then report(seq, f2, "PRESET opened with " .. name) end
end
-- a handler that raises an error: one line in the log, the page is whole afterwards (rows mode, its own handlers), the next key works
do
  local w = world()
  _menu.set_page("BOX")
  for _, name in ipairs({"set_style", "step_preset"}) do
    local row = name == "set_style" and 1 or 2
    local orig = w.box[name]
    w.box[name] = function() error("boom " .. name) end
    w.pages.BOX.pos = row
    printed = {}
    local ok = pcall(function() apply(w, {k = "tap", name = row == 1 and "RIGHT" or "EQUAL"}) end)
    local line
    for _, l in ipairs(printed) do if l:find("THEME page: ", 1, true) and l:find("raised an error", 1, true) and l:find("boom " .. name, 1, true) then line = l end end
    w.box[name] = orig
    if not ok or not line then fails_total = fails_total + 1 print("FAIL a handler error is not logged or escapes the page (" .. name .. ")") end
    local msg = invariants(w)
    if msg then fails_total = fails_total + 1 print("FAIL the page is not whole after a handler error (" .. name .. "): " .. msg) end
    apply(w, {k = "tap", name = "DOWN"})
    if w.pages.BOX.pos ~= math.min(row + 1, 8) then fails_total = fails_total + 1 print("FAIL DOWN does not work after a handler error (" .. name .. ")") end
  end
  -- a selection that is out of range is clamped with one log line, and not logged when it is in range or when scrolling past the end
  local pg = w.pages.BOX
  pg.mode, pg.pos = "rows", 9
  printed = {}
  pg.redraw()
  local clamped = false
  for _, l in ipairs(printed) do if l:find("selection 9 clamped to", 1, true) then clamped = true end end
  if not clamped or pg.pos ~= 8 then fails_total = fails_total + 1 print("FAIL an out of range selection is not clamped and logged") end
  printed = {}
  pg.pos = 8
  for _ = 1, 3 do apply(w, {k = "tap", name = "DOWN"}) end
  for _, l in ipairs(printed) do if l:find("clamped", 1, true) then fails_total = fails_total + 1 print("FAIL scrolling past the last row is logged as a clamp") break end end
end
if fails_total == 0 then print("menu_stress_test: all passed (" .. SEEDS .. " runs of " .. EVENTS .. " events)") end
os.exit(fails_total == 0 and 0 or 1)
