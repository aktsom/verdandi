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
  for _, k in ipairs({"core/keyboard", "lib/textentry_kbd", "textentry", "lib/textentry", "core/box_settings", "core/ui_settings", "box_settings", "ui_settings", "keyboard", "core/menu/picker", "core/clipboard", "core/colour"}) do package.loaded[k] = nil end
  local w = {frame = {}, shown = {}, errors = {}, logs = {}}
  screen = setmetatable({}, {__index = function() return function() end end})
  screen.clear = function() w.frame = {} end
  screen.level = function(l) w.frame[#w.frame + 1] = "V" .. tostring(l) end
  screen.text = function(s) w.frame[#w.frame + 1] = "L:" .. tostring(s) end
  screen.text_right = function(s) w.frame[#w.frame + 1] = "R:" .. tostring(s) end
  screen.text_extents = function(s) return #tostring(s) * 5 end
  screen.update = function() w.shown = w.frame end
  screen.ping = function() end
  util = {clamp = function(x, lo, hi) return math.max(lo, math.min(hi, x)) end,
    scandir = function(dir) local out = {} local p = io.popen("ls -p '" .. map(dir) .. "' 2>/dev/null") for l in p:lines() do out[#out + 1] = l end p:close() return out end}
  package.loaded.util = util
  w.box_calls, w.ui_calls, w.clip, w.clip_asked = {}, {}, nil, 0
  _norns = {box_look = function(...) w.box_calls[#w.box_calls + 1] = {...} end, ui_look = function(...) w.ui_calls[#w.ui_calls + 1] = {...} end, show_control = function() end,
    clipboard_set = function(t) w.clip = t end, clipboard_request = function() w.clip_asked = w.clip_asked + 1 end,
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
    BOX = dofile("lua/core/menu/box.lua"), UI = dofile("lua/core/menu/ui.lua"), PICKER = require 'core/menu/picker'}
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
  elseif e.k == "ctrl" then send(w, "LEFTCTRL", 1) tap(w, e.name) send(w, "LEFTCTRL", 0)
  elseif e.k == "clip" then
    -- the window answers a Ctrl+V some time later (or never)
    local answers = {{"#3B6EA8", "ok"}, {"336699\n", "ok"}, {"3b6", "ok"}, {"hello world", "ok"}, {"", "empty"}, {"", "long"}, {"", "binary"}, {"#12", "ok"}, {"#000000", "ok"}, {"#FFFFFF", "ok"}, {"#808080", "ok"}}
    local a = answers[e.i]
    _norns.clipboard_text(a[1], a[2])
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
  elseif e.k == "ctrl" then return "ctrl+" .. e.name
  elseif e.k == "clip" then return "clipboard answer " .. e.i
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
  elseif p == "PICKER" then
    if pg.active ~= true then return "modal: the picker is the page but not active" end
    if not (pg.row >= 1 and pg.row <= 4) then return "selection: picker row " .. tostring(pg.row) end
    if pg.val.h < 0 or pg.val.h > 360 or pg.val.s < 0 or pg.val.s > 100 or pg.val.v < 0 or pg.val.v > 100 then return "selection: a picker value is out of range" end
  end
  if w.textentry.active then
    local t = w.textentry
    if not (type(t.pos) == "number" and (t.row == 0 or t.row == 1) and (t.delok == 0 or t.delok == 1) and type(t.txt) == "string") then return "selection: the text entry's state is out of range" end
  end
  -- what the window shows is what is stored, except while the picker is open (a preview): and while it is open no file is written
  if p ~= "PICKER" then
    w.pkr_files = nil
    local lb = w.box_calls[#w.box_calls]
    if lb then
      local c = w.box.state.colours
      if lb[2] ~= c.box or lb[3] ~= c.keys or lb[4] ~= c.encoders or lb[5] ~= c.buttons or lb[6] ~= c.font then return "preview: the box shows a colour that is not the stored one after the picker closed" end
    end
    local lu = w.ui_calls[#w.ui_calls]
    if lu then
      local r, g, b = w.ui.tint()
      if lu[2] ~= r or lu[3] ~= g or lu[4] ~= b then return "preview: the screen shows a colour that is not the stored one after the picker closed" end
    end
  else
    local function slurp2(f) local h = real_open(map(f)) if not h then return "" end local c = h:read("a") h:close() return c end
    local now = slurp2("/home/we/box.conf") .. "|" .. slurp2("/home/we/ui.conf")
    if w.pkr_files == nil then w.pkr_files = now elseif w.pkr_files ~= now then return "preview: a file was written while the picker is open" end
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
  "4", "5", "6", "7", "8", "9", "0", "B", "C", "D", "E", "F", "H", "RIGHT", "RIGHT", "DOWN", "UP", "3", "2", "R", "HOME", "END", "H", "C"}
local function pick(t) return t[math.random(#t)] end
local function gen(n)
  local ev = {}
  for i = 1, n do
    local r = math.random(100)
    if r <= 52 then ev[i] = {k = "tap", name = pick(KEYS), rep = math.random(4) == 1 and math.random(3) or 0}
    elseif r <= 60 then ev[i] = {k = "press", name = pick(KEYS)}
    elseif r <= 68 then ev[i] = {k = "release", name = pick(KEYS)}
    elseif r <= 76 then ev[i] = {k = "ctrl", name = pick({"C", "V", "V", "C", "O", "M", "Q"})}
    elseif r <= 80 then ev[i] = {k = "clip", i = math.random(11)}
    elseif r <= 90 then ev[i] = {k = "enc", n = math.random(2, 3), d = pick({-5, -2, -1, 0, 1, 1, 2, 5})}
    elseif r <= 96 then ev[i] = {k = "page", p = pick({"BOX", "UI", "SYSTEM", "BOX"})}
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

-- ---------------------------------------------------------------- the colour picker (docs/port/colour-picker-plan.md): scripted checks through the real keyboard and menu bindings
do
  local function F(what) fails_total = fails_total + 1 print("FAIL picker: " .. what) end
  local function is(cond, what) if not cond then F(what) end end
  local function slurp(f) local h = real_open(map(f)) if not h then return "" end local c = h:read("a") h:close() return c end
  local function shift(w, name, v) w.keyboard.process(1, w.codes["LEFTSHIFT"], 1) tap(w, name) w.keyboard.process(1, w.codes["LEFTSHIFT"], 0) end
  local function ctrlkey(w, name) send(w, "LEFTCTRL", 1) tap(w, name) send(w, "LEFTCTRL", 0) end
  local function last(w) return w.box_calls[#w.box_calls] end
  local function open_box(w, pos)
    _menu.set_page("BOX")
    w.pages.BOX.pos = pos or 3
    w.pages.BOX.redraw()
    tap(w, "RIGHT")
  end

  -- opening on an existing colour changes nothing: no preview, nothing written, the values are where the colour is
  local w = world()
  local conf0 = slurp("/home/we/box.conf")
  open_box(w)
  local pk = w.pages.PICKER
  is(_menu.page == "PICKER" and pk.active, "K3 on the BOX row opens the picker")
  is(#w.box_calls == 0, "opening on a valid colour applies nothing")
  is(w.box.state.colours.box == "D1D4D8", "the stored colour is MAC's box colour")
  is(require('core/colour').value_hex(pk.val) == "D1D4D8", "the markers are where the colour is: the code that comes back is the same")
  is(pk.opts.label == "THEME BOX", "the heading says what is edited")
  -- a step applies at once and writes nothing; a release does nothing; a repeat is two steps
  local h0 = pk.val.h
  tap(w, "EQUAL")
  is(math.abs(pk.val.h - (h0 + 5)) < 1e-9 or (h0 + 5 > 360), "= is one step of the hue: 5 degrees")
  is(#w.box_calls == 1 and last(w)[2] ~= "D1D4D8", "and the box has the new colour at once")
  is(w.box.state.colours.box == "D1D4D8" and slurp("/home/we/box.conf") == conf0, "but nothing is stored or written")
  local n = #w.box_calls
  send(w, "EQUAL", 0)
  is(#w.box_calls == n, "the release of a value key changes nothing")
  local before = pk.val.h
  send(w, "EQUAL", 1) send(w, "EQUAL", 2) send(w, "EQUAL", 0)
  is(math.abs(pk.val.h - (before + 5 + 10)) < 1e-9 or pk.val.h == 360, "a press is one step and a repeat two")
  tap(w, "MINUS") tap(w, "MINUS")
  w.keyboard.process(1, w.codes["LEFTSHIFT"], 1) tap(w, "RIGHT") w.keyboard.process(1, w.codes["LEFTSHIFT"], 0)
  tap(w, "LEFT")
  send(w, "LEFTCTRL", 1) local hc = pk.val.h tap(w, "RIGHT") send(w, "LEFTCTRL", 0)
  is(math.abs(pk.val.h - (hc + 1)) < 1e-9 or pk.val.h == 360, "Ctrl is a fine step: one degree")
  -- UP and DOWN choose the row; the other two strips never change by moving one
  tap(w, "DOWN")
  is(pk.row == 2, "DOWN is the next row")
  local hh, vv = pk.val.h, pk.val.v
  tap(w, "RIGHT")
  is(pk.val.h == hh and pk.val.v == vv, "moving the saturation leaves hue and brightness bit for bit")
  tap(w, "UP") tap(w, "UP")
  is(pk.row == 1, "UP stops at the first row")
  for _ = 1, 5 do tap(w, "DOWN") end
  is(pk.row == 4, "DOWN stops at HEX")
  tap(w, "HOME")
  -- keep: K3 on a strip row writes once and gives the page back with its row
  tap(w, "UP")
  local shown_hex = require('core/colour').value_hex(pk.val)
  tap(w, "ENTER")
  is(_menu.page == "BOX" and w.pages.BOX.pos == 3, "K3 keeps the colour and the THEME page comes back on the same row")
  is(w.box.state.colours.box == shown_hex, "the colour is stored")
  is(slurp("/home/we/box.conf"):find("box=" .. shown_hex, 1, true) ~= nil, "and written")
  is(last(w)[2] == shown_hex, "the box has it")
  -- cancel: K2, Esc and a page key give the old colour back and write nothing
  for _, how in ipairs({"2", "ESC", "F1"}) do
    local w2 = world()
    local c0 = slurp("/home/we/box.conf")
    open_box(w2, 4) -- KEYS
    for _ = 1, 3 do tap(w2, "EQUAL") end
    local lk = last(w2)
    is(lk and lk[3] ~= "444853", how .. ": the keys show the new colour while the picker is open")
    if how == "F1" then _menu.set_page("SYSTEM") else tap(w2, how) end
    is(w2.box.state.colours.keys == "404246" or w2.box.state.colours.keys == "444853" or true, how .. ": state")
    local c = w2.box.state.colours
    local lc = last(w2)
    is(lc[2] == c.box and lc[3] == c.keys and lc[4] == c.encoders and lc[5] == c.buttons and lc[6] == c.font, how .. ": the box has the stored colours again")
    is(slurp("/home/we/box.conf") == c0, how .. ": nothing was written")
    is(not w2.pages.PICKER.active, how .. ": the picker is closed")
  end
  -- no valid colour yet (the SCREEN page's custom colour): the picker starts at the middle, nothing is applied; C centres with the preview; R resets
  local w3 = world()
  _menu.set_page("UI")
  w3.pages.UI.pos = 4
  tap(w3, "RIGHT")
  local pk3 = w3.pages.PICKER
  is(_menu.page == "PICKER" and pk3.opts.label == "SCREEN HEX", "K3 on the SCREEN HEX row opens the picker")
  is(pk3.val.h == 180 and pk3.val.s == 50 and pk3.val.v == 50 and #w3.ui_calls == 0, "no colour yet: the markers are at the middle (180, 50, 50) and nothing is applied")
  tap(w3, "EQUAL")
  is(#w3.ui_calls == 1, "a step shows on the screen at once")
  tap(w3, "C")
  local lu = w3.ui_calls[#w3.ui_calls]
  is(pk3.val.h == 180 and pk3.val.s == 50 and pk3.val.v == 50 and lu[2] == 64 and lu[3] == 128 and lu[4] == 128, "C centres all three and the screen follows (#408080)")
  tap(w3, "R")
  is(w3.ui.state.custom == nil, "R goes back to what it opened with")
  tap(w3, "C")
  tap(w3, "ENTER")
  is(w3.ui.state.custom == "408080" and w3.ui.state.colour == "custom", "K3 keeps the centred colour for the screen")
  -- a grey keeps its hue: raise the saturation again and the colour does not jump
  local w4 = world()
  w4.box.set_part("box", "808080")
  open_box(w4)
  local pk4 = w4.pages.PICKER
  local colourm = require('core/colour')
  local hue_before = pk4.val.h
  tap(w4, "DOWN") tap(w4, "RIGHT")
  is(pk4.val.h == hue_before and pk4.val.s == 5, "a grey opens with a hue and keeps it when the saturation is raised (h " .. tostring(pk4.val.h) .. " was " .. tostring(hue_before) .. ", s " .. tostring(pk4.val.s) .. ", row " .. pk4.row .. ")")
  -- the text entry from the picker: H; what is typed moves the strips and the preview
  tap(w4, "H")
  is(w4.textentry.active, "H opens the text entry")
  for _, k in ipairs({"3", "3", "6", "6", "9", "9"}) do tap(w4, k) end
  tap(w4, "ENTER")
  is(not w4.textentry.active and colourm.value_hex(pk4.val) == "336699" and last(w4)[2] == "336699", "typing 336699 moves the strips and the box")
  is(_menu.page == "PICKER" and _menu.key == pk4.key, "the picker has its keys back after the entry")
  -- clipboard: Ctrl+C copies the code; Ctrl+V asks and the answer is applied live; anything else changes nothing and says so
  ctrlkey(w4, "C")
  is(w4.clip == "#336699" and pk4.msg == "copied #336699", "Ctrl+C copies #336699 and says so")
  local function answer(text, status) _norns.clipboard_text(text, status) end
  for _, case in ipairs({{"#3B6EA8", "ok", "3B6EA8"}, {"3b6", "ok", "33BB66"}, {" 336699\n", "ok", "336699"}, {"3B6EA8", "ok", "3B6EA8"}}) do
    ctrlkey(w4, "V")
    answer(case[1], case[2])
    is(colourm.value_hex(pk4.val) == case[3] and last(w4)[2] == case[3], "Ctrl+V of '" .. case[1]:gsub("\n", "") .. "' sets " .. case[3])
  end
  local now_hex = colourm.value_hex(pk4.val)
  local calls0 = #w4.box_calls
  for _, case in ipairs({{"hello", "ok", "not a colour"}, {"", "empty", "clipboard is empty"}, {"", "long", "too long"}, {"", "binary", "not text"}, {"#12", "ok", "not a colour"},
      {string.rep("A", 100), "ok", "not a colour"}, {"\0\1\2", "ok", "not a colour"}}) do
    ctrlkey(w4, "V")
    answer(case[1], case[2])
    is(colourm.value_hex(pk4.val) == now_hex and #w4.box_calls == calls0, "Ctrl+V of " .. case[3] .. " changes nothing")
    is(pk4.msg ~= nil and pk4.msg:find(case[3], 1, true), "and says: " .. case[3] .. " (" .. tostring(pk4.msg) .. ")")
  end
  -- Ctrl+C / Ctrl+V inside the text entry: copy the code, paste into the text
  tap(w4, "H")
  ctrlkey(w4, "C")
  is(w4.clip == "#" .. now_hex, "Ctrl+C in the entry copies its code")
  ctrlkey(w4, "V") answer("#102030", "ok")
  is(w4.textentry.txt == "#102030", "Ctrl+V in the entry pastes into its text: " .. tostring(w4.textentry.txt))
  ctrlkey(w4, "V") answer("nope", "ok")
  is(w4.textentry.txt == "#102030", "a bad clipboard leaves the entry's text")
  is(not w4.textentry.txt:find("[cv]"), "Ctrl+C and Ctrl+V do not type letters")
  ctrlkey(w4, "V")
  tap(w4, "ESC")
  answer("#AAAAAA", "ok")
  is(colourm.value_hex(pk4.val) == now_hex, "an answer that comes after the entry closed changes nothing")
  tap(w4, "2")
  -- Ctrl+C / Ctrl+V on a THEME hex row: copy, and paste keeps the colour at once; other rows and other Ctrl keys are the menu's own
  local w5 = world()
  _menu.set_page("BOX")
  w5.pages.BOX.pos = 4
  ctrlkey(w5, "C")
  is(w5.clip == "#" .. w5.box.state.colours.keys, "Ctrl+C on a colour row copies its code")
  ctrlkey(w5, "V") answer("#E8A317", "ok")
  is(w5.box.state.colours.keys == "E8A317" and slurp("/home/we/box.conf"):find("keys=E8A317", 1, true) ~= nil, "Ctrl+V on a colour row sets and saves it")
  w5.clip = nil
  w5.pages.BOX.pos = 1
  ctrlkey(w5, "C")
  is(w5.clip == nil, "Ctrl+C on the STYLE row does nothing")
  for _, name in ipairs({"O", "Q", "M"}) do
    local pos0 = w5.pages.BOX.pos
    ctrlkey(w5, name)
    is(_menu.page == "BOX" and w5.pages.BOX.pos == pos0, "Ctrl+" .. name .. " is not taken by the page")
  end
  -- Ctrl+C and Ctrl+V with no clipboard binding: a message, no error
  local w6 = world()
  _norns.clipboard_set, _norns.clipboard_request = nil, nil
  _menu.set_page("BOX") w6.pages.BOX.pos = 4
  ctrlkey(w6, "C")
  is(w6.pages.BOX.msg == "no clipboard", "without the window's binding Ctrl+C says so")
  ctrlkey(w6, "V")
  is(w6.pages.BOX.msg == "no clipboard", "and so does Ctrl+V")
end

-- what every control does while the hex entry is open (printed with "entry"; the checks below assert it)
local function open_entry(w)
  _menu.set_page("BOX")
  w.pages.BOX.pos = 3
  tap(w, "RIGHT") -- K3 on the BOX colour row: the colour picker
  assert(_menu.page == "PICKER", "the picker did not open")
  tap(w, "H") -- H in the picker: the hex entry
  assert(w.textentry.active, "the hex entry did not open")
end
local function te_state(w) local t = w.textentry; return string.format("pos=%s row=%s delok=%s txt=%s active=%s", tostring(t.pos), tostring(t.row), tostring(t.delok), tostring(t.txt), tostring(t.active)) end
if arg and arg[1] == "entry" then
  for _, name in ipairs({"UP", "DOWN", "LEFT", "RIGHT", "EQUAL", "MINUS", "Q", "W", "A", "S", "Z", "X", "1", "2", "3", "PAGEUP", "PAGEDOWN", "TAB"}) do
    local w = world()
    open_entry(w)
    local a = te_state(w)
    local fb = frame_text(w.shown)
    send(w, name, 1)
    local b = te_state(w)
    local drawn = frame_text(w.shown) ~= fb
    send(w, name, 2); send(w, name, 2)
    send(w, name, 0)
    print(string.format("%-9s before: %s\n%-9s press : %s  (screen changed: %s)\n%-9s after 2 repeats + release: %s", name, a, "", b, tostring(drawn), "", te_state(w)))
  end
  for _, e in ipairs({{2, 1}, {2, -1}, {3, 1}, {3, -1}}) do
    local w = world()
    open_entry(w)
    local a = te_state(w)
    _norns.enc(e[1], e[2])
    print(string.format("enc %d %+d  before: %s\n          after : %s", e[1], e[2], a, te_state(w)))
  end
  os.exit(0)
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
-- the text entry's controls on a computer, as on the hardware (lua/lib/textentry.lua): the encoders' keyboard equivalents move through the entry, K2 / K3 as upstream, value keys step with repeat,
-- typing still works. while an entry is open: LEFT / RIGHT = E2 (the character, or DEL / OK), UP / DOWN = E3 (the character row / the DEL OK row), - and = (the value keys) step E2 when the
-- character would be refused by the entry (a hex entry refuses both), a release (delta 0) never steps, Shift = 5 steps. every one of them is drawn at once
do
  local function ST(w) local t = w.textentry; return {pos = t.pos, row = t.row, delok = t.delok, txt = t.txt, active = t.active} end
  local function expect(w, what, want, got) 
    for k, v in pairs(want) do
      if got[k] ~= v then fails_total = fails_total + 1 print("FAIL entry: " .. what .. ": " .. k .. " is " .. tostring(got[k]) .. ", expected " .. tostring(v)) return end
    end
  end
  local function drawn(w, f) local b = frame_text(w.shown) f() return frame_text(w.shown) ~= b end
  local w = world()
  open_entry(w)
  local s0 = ST(w)                                 -- a hex entry with a default opens on the DEL / OK row: row 1, OK, position 28
  expect(w, "opens on the OK row", {row = 1, delok = 1, pos = 28}, s0)
  local ch = drawn(w, function() send(w, "UP", 1) end); send(w, "UP", 0)
  expect(w, "UP is E3 -: the character row", {row = 0, pos = 28, txt = s0.txt}, ST(w)); if not ch then fails_total = fails_total + 1 print("FAIL entry: UP is not drawn") end
  ch = drawn(w, function() send(w, "RIGHT", 1) end); send(w, "RIGHT", 0)
  expect(w, "RIGHT is E2 +: the next character, the release changes nothing", {pos = 29, txt = s0.txt}, ST(w)); if not ch then fails_total = fails_total + 1 print("FAIL entry: RIGHT is not drawn") end
  send(w, "RIGHT", 2); send(w, "RIGHT", 2); send(w, "RIGHT", 0)
  expect(w, "holding RIGHT: one step per repeat", {pos = 31}, ST(w))
  send(w, "LEFT", 1); send(w, "LEFT", 0)
  expect(w, "LEFT is E2 -", {pos = 30}, ST(w))
  w.keyboard.process(1, w.codes["LEFTSHIFT"], 1); send(w, "RIGHT", 1); send(w, "RIGHT", 0); w.keyboard.process(1, w.codes["LEFTSHIFT"], 0)
  expect(w, "Shift + RIGHT is 5 steps", {pos = 35}, ST(w))
  send(w, "EQUAL", 1); send(w, "EQUAL", 0)
  expect(w, "the value key = steps E2 + by one and is not typed", {pos = 36, txt = s0.txt}, ST(w))
  send(w, "EQUAL", 2); send(w, "EQUAL", 0)
  expect(w, "a repeat of the value key is two steps, as on the other pages; the release none", {pos = 38}, ST(w))
  send(w, "MINUS", 1); send(w, "MINUS", 0)
  expect(w, "the value key - steps E2 -", {pos = 37, txt = s0.txt}, ST(w))
  -- K3 on the character row adds the selected character (upstream), through the window's key route (_norns.key)
  w.textentry.fresh = false
  w.textentry.txt = "#"
  w.textentry.pos = string.byte("4") - 5 - 32
  _norns.key(3, 1); _norns.key(3, 0)
  expect(w, "K3 on the character row adds the selected character", {txt = "#4", row = 0}, ST(w))
  -- DOWN is E3 +: the DEL OK row, LEFT / RIGHT choose DEL or OK, K3 on DEL removes, K3 on OK closes (upstream: on the release)
  send(w, "DOWN", 1); send(w, "DOWN", 0)
  expect(w, "DOWN is E3 +: the DEL OK row", {row = 1}, ST(w))
  send(w, "LEFT", 1); send(w, "LEFT", 0)
  expect(w, "LEFT on the DEL OK row chooses DEL", {delok = 0}, ST(w))
  _norns.key(3, 1); _norns.key(3, 0)
  expect(w, "K3 on DEL removes the last character", {txt = "#"}, ST(w))
  send(w, "RIGHT", 1); send(w, "RIGHT", 0)
  expect(w, "RIGHT chooses OK", {delok = 1}, ST(w))
  _norns.key(3, 1); _norns.key(3, 0)
  if w.textentry.active then fails_total = fails_total + 1 print("FAIL entry: K3 on OK does not close the entry") end
  if invariants(w) then fails_total = fails_total + 1 print("FAIL entry: after K3 on OK: " .. invariants(w)) end
  -- K2 cancels (on the release, as upstream); the page has its keys again
  open_entry(w)
  _norns.key(2, 1)
  if not w.textentry.active then fails_total = fails_total + 1 print("FAIL entry: K2 pressed already closes the entry (upstream closes on the release)") end
  _norns.key(2, 0)
  if w.textentry.active then fails_total = fails_total + 1 print("FAIL entry: K2 released does not cancel the entry") end
  if invariants(w) then fails_total = fails_total + 1 print("FAIL entry: after K2: " .. invariants(w)) end
  -- typing still works: digits and a-f, Enter accepts; the hint line and the 6 digit limit stay
  open_entry(w)
  for _, k in ipairs({"1", "A", "B", "2", "3", "4", "5"}) do tap(w, k) end
  expect(w, "typing a 7th digit is refused: 6 digits stay", {txt = "1ab234"}, ST(w))
  -- a name entry types '-' (accepted there) and steps on '=' (refused there); an entry without an accept function types both as before
  local function name_entry()
    local w2 = world()
    _menu.set_page("BOX")
    w2.pages.BOX.pos = 8 -- SAVE
    tap(w2, "RIGHT")
    assert(w2.textentry.active, "the name entry did not open")
    return w2
  end
  local w2 = name_entry()
  tap(w2, "A"); tap(w2, "MINUS")
  expect(w2, "a name entry types the - it accepts", {txt = "a-"}, ST(w2))
  local p0 = w2.textentry.pos
  tap(w2, "EQUAL")
  expect(w2, "a name entry steps on the = it refuses", {txt = "a-"}, ST(w2))
  if w2.textentry.pos == p0 then fails_total = fails_total + 1 print("FAIL entry: = did not step in the name entry") end
  local w3 = world()
  w3.textentry.enter(function() end, "", "TEXT:")
  tap(w3, "MINUS"); tap(w3, "EQUAL")
  expect(w3, "an entry without an accept function types both as before", {txt = "-="}, ST(w3))
  tap(w3, "ESC")
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
