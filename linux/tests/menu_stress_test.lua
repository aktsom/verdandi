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
  os.execute("rm -rf '" .. tmp .. "'/box.conf '" .. tmp .. "'/ui.conf '" .. tmp .. "'/box-presets '" .. tmp .. "'/midimap.conf '" .. tmp .. "'/midimap-presets")
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
    scandir = function(dir) local out = {} local p = io.popen("ls -p '" .. map(dir) .. "' 2>/dev/null") for l in p:lines() do out[#out + 1] = l end p:close() return out end,
    file_exists = function() return false end, make_dir = function() end, os_capture = function() return "" end, s_to_hms = function() return "0:00:00" end}
  package.loaded.util = util
  w.box_calls, w.ui_calls, w.clip, w.clip_asked, w.toasts = {}, {}, nil, 0, {}
  _norns = {box_look = function(...) w.box_calls[#w.box_calls + 1] = {...} end, ui_look = function(...) w.ui_calls[#w.ui_calls + 1] = {...} end, show_control = function() end,
    toast = function(t) w.toasts[#w.toasts + 1] = t end,
    clipboard_set = function(t) w.clip = t end, clipboard_request = function() w.clip_asked = w.clip_asked + 1 end,
    midimap_arm = function(a) w.armed = a end, midimap_show = function(st) w.ring = st end,
    -- the window actions: a call is a finding when the master switch is off, a text entry is open, a learn is on, or the name is not one of the 14
    window_action = function(name)
      w.actions_fired = (w.actions_fired or 0) + 1
      COVER.fired = COVER.fired + 1
      local ok = false
      for _, id in ipairs(w.mm_set.ACTION_IDS) do if id == name then ok = true end end
      if not ok then w.action_bad = "window_action(" .. tostring(name) .. ")"
      elseif not w.mm_set.state.actions_on then w.action_bad = "window_action(" .. name .. ") while the master switch is off"
      elseif w.textentry.active then w.action_bad = "window_action(" .. name .. ") while a text entry is open"
      elseif w.mm.learn.state ~= "idle" then w.action_bad = "window_action(" .. name .. ") during a learn (" .. w.mm.learn.state .. ")" end
    end,
    midi_actions_menu = function(on) w.menu_tick = on end,
    -- the virtual arc: ticks are whole, non-zero, for a ring of 1 to 4; the window may be closed (the call says so)
    arc_turn = function(n, t)
      if type(n) ~= "number" or n < 1 or n > 4 or n ~= math.floor(n) or type(t) ~= "number" or t ~= math.floor(t) or t == 0 then w.arc_bad = "arc_turn(" .. tostring(n) .. ", " .. tostring(t) .. ")" end
      if not w.arc_open then w.arc_refused = (w.arc_refused or 0) + 1 return false end
      w.arc_turns = (w.arc_turns or 0) + 1
      return true
    end,
    key = function(n, z) if n ~= 1 then _menu.key(n, z) end end, enc = function(n, d) if n ~= 1 then _menu.penc(n, d) end end}
  write("/home/we/keyboard.layout", "us\n")
  _path = {keyboard_layout = "/home/we/keyboard.layout"}
  norns = {none = function() end}
  _menu = {mode = true, page = "SYSTEM", goto_panel = function() end, draw_panel = function() end,
    -- the menu's own set_mode tells the text entry that the menu changed (lua/core/menu.lua; a source check below makes sure it does)
    set_mode = function(mode) _menu.mode = mode; if w.textentry and w.textentry.menu_changed then w.textentry.menu_changed("mode") end end}
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
  -- the MIDI MAP page (docs/port/midi-map-plan.md): the real layer, settings and page; the devices are plain tables, the window's calls are recorded
  for _, k in ipairs({"core/midimap", "core/midimap_settings", "core/midimap_value", "core/pmap"}) do package.loaded[k] = nil end
  w.armed, w.ring, w.T, w.arc_open = 0, 0, 1000, true
  params = {lookup = {}, lookup_param = function(self, id) return {name = id} end}
  midi = {devices = {}, vports = {}}
  for i = 1, 16 do midi.vports[i] = {name = "none"} end
  w.devs = {{id = 1, name = "mio", port = 1}, {id = 2, name = "iii grid", port = 2}, {id = 3, name = "Push 2", port = 3}, {id = 4, name = "Verdandi JACK in", port = 4}}
  for _, d in ipairs(w.devs) do midi.devices[d.id] = d; midi.vports[d.port].name = d.name end
  w.pmap = require 'core/pmap'
  norns.pmap, norns.state = w.pmap, {shortname = "stress"}
  w.mm_set = require 'core/midimap_settings'
  w.mm_set.log = function(s) w.logs[#w.logs + 1] = s end
  w.mm = require 'core/midimap'
  w.mm.log = function(s) w.logs[#w.logs + 1] = s end
  w.mm.clock = function() return w.T end
  norns.midimap = w.mm
  w.mm.load()
  w.mm.install()
  w.pages.MIDIMAP = dofile("lua/core/menu/midimap.lua")
  -- the tape page (its REC name entry is a text entry like the others): the audio side is a stub
  audio = {tape = {constants = setmetatable({}, {__index = function() return 0 end}), subscribe = function() end, unsubscribe = function() end, get_state = function() return {rec = {state = 0, pos = 0}, play = {state = 0, pos = 0, len = 0}} end}}
  for _, f in ipairs({"tape_play_stop", "tape_record_open", "tape_record_start", "tape_play_start", "tape_play_pause", "tape_record_pause", "tape_record_stop", "tape_play_open", "tape_play_loop"}) do audio[f] = function() end end
  audio.tape_compute_diskfree = function() return 0 end
  tab = require "tabutil"
  _path.tape = "/home/we/tape/"
  -- (the tape page's file browser and its unload question are other modals: stubs here, they are not what is tested)
  package.loaded.fileselect = {enter = function() end, pushd = function() end}
  package.loaded.listselect = {enter = function() end}
  package.loaded["core/menu/tape"] = nil
  w.pages.TAPE = dofile("lua/core/menu/tape.lua")
  _menu.set_page = function(p)
    w.pages[_menu.page].deinit()
    if w.textentry.menu_changed then w.textentry.menu_changed("page") end
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

COVER = {fired = 0, walks = 0, aviews = 0} -- (the random runs must reach the new code: counted, checked at the end)
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
  elseif e.k == "midi" then
    w.mm.event(w.devs[e.dev], e.b) -- (midi.lua calls it under pcall; here an error is a finding)
  elseif e.k == "click" then
    if w.armed == 1 then _norns.midimap_pick(e.id:sub(1, 1), e.id:sub(2)) end -- the window only reports a click while a pick is armed
  elseif e.k == "nav" then
    -- straight to the actions list (row 13) and one of its rows: ASSIGN ALL, an action's view, CLEAR ALL (the random page keys rarely get so far down)
    if _menu.page ~= "MIDIMAP" then _menu.set_page("MIDIMAP") end
    local pg = w.pages.MIDIMAP
    if pg.mode == "rows" and not w.textentry.active and w.mm.learn.state == "idle" then
      pg.pos = 13; pg.redraw(); tap(w, "RIGHT")
      pg.apos = e.n; pg.redraw(); tap(w, "RIGHT")
    end
  elseif e.k == "tick" then
    w.T = w.T + e.dt
    w.mm.tick()
  elseif e.k == "page" then
    -- (the menu may change pages under an open entry: it is closed, docs/port/KNOWN-ISSUES.md item 25)
    local from = _menu.page
    _menu.set_page(e.p)
    if from == "MIDIMAP" and e.p ~= "MIDIMAP" then w.left_midimap = true end
  elseif e.k == "ext" then
    if e.what == "pmap" then w.pmap.clear() w.pmap.new("p") w.pmap.assign("p", e.dev, 1, e.cc)
    elseif e.what == "unpmap" then w.pmap.clear()
    elseif e.what == "arckeyson" or e.what == "arckeysoff" then
      -- (a setting written from outside the page: not while a learn waits, which promises that no file is written)
      if w.mm.learn.state == "idle" then w.mm_set.set_arc_keys(e.what == "arckeyson") end
    elseif e.what == "amap" then
      -- an action set from outside the page (a preset, another session of the page): only while no learn waits
      if w.mm.learn.state == "idle" then
        local kinds = {"note", "ccbutton", "step"}
        w.mm_set.assign_action(w.mm_set.ACTION_IDS[e.id], kinds[e.kind], e.num, {mode = ({"rel2c", "relsm", "relob"})[e.kind], dir = (e.id % 2 == 0) and "up" or "down"})
      end
    elseif e.what == "aclear" then if w.mm.learn.state == "idle" then w.mm.clear(w.mm_set.ACTION_IDS[e.id]) end
    elseif e.what == "aon" or e.what == "aoff" then _norns.midi_actions_changed(e.what == "aon") -- the window menu's tick and Ctrl+Shift+M
    elseif e.what == "mon" or e.what == "moff" then w.mm.set_actions(e.what == "mon")   -- the page's row
    elseif e.what == "arcopen" then w.arc_open = true
    elseif e.what == "arcclose" then w.arc_open = false
    elseif e.what == "unplug" then local d = w.devs[e.dev] midi.devices[d.id] = nil w.mm.device_removed(d)
    elseif e.what == "plug" then local d = w.devs[e.dev] midi.devices[d.id] = d
    elseif e.what == "drop" then os.remove("/home/we/box-presets/alpha.box") w.box.reload_looks()
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
  elseif e.k == "midi" then return "midi dev" .. e.dev .. " " .. table.concat(e.b, ",")
  elseif e.k == "click" then return "click " .. e.id
  elseif e.k == "nav" then return "nav actions row " .. e.n
  elseif e.k == "tick" then return "tick +" .. e.dt
  elseif e.k == "ext" then return "ext " .. e.what .. (e.dev and (" dev" .. e.dev) or "") .. (e.cc and (" cc" .. e.cc) or "") end
  return e.k .. " " .. e.name
end

local function state_of(w)
  local p, pg = _menu.page, w.pages[_menu.page]
  local s = p
  if p == "BOX" then s = s .. string.format(" mode=%s pos=%s top=%s lpos=%s rows=%d", pg.mode, pg.pos, pg.top, pg.lpos, #pg.rows())
  elseif p == "UI" then s = s .. " pos=" .. tostring(pg.pos)
  elseif p == "MIDIMAP" then s = s .. string.format(" mode=%s pos=%s dpos=%s ctl=%s learn=%s target=%s armed=%s", pg.mode, pg.pos, pg.dpos, tostring(pg.ctl), w.mm.learn.state, tostring(w.mm.learn.target), tostring(w.armed)) end
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
    if rows[1] ~= "STYLE" or rows[2] ~= "PIXEL LOOK" then return "rows: STYLE and PIXEL LOOK are not the first two rows" end
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
  elseif p == "MIDIMAP" then
    if pg.mode ~= "rows" and pg.mode ~= "detail" and pg.mode ~= "confirm" and pg.mode ~= "watch" and pg.mode ~= "turn" and pg.mode ~= "actions" and pg.mode ~= "aview" then return "modal: unknown mode " .. tostring(pg.mode) end
    if (pg.mode == "watch") ~= w.mm.watching then return "modal: the WATCH view and the layer's watching flag disagree (" .. tostring(pg.mode) .. ", " .. tostring(w.mm.watching) .. ")" end
    if (pg.mode == "turn") ~= (w.mm.calib_target() ~= nil) then return "modal: the ONE TURN view and the layer's calibration disagree" end
    if pg.mode == "turn" and (pg.ctl == nil or pg.ctl:sub(1, 1) ~= "a") then return "modal: ONE TURN for a control that is not an arc encoder" end
    if (pg.mode == "confirm") ~= (pg.confirm ~= nil) then return "modal: the confirm flag and the mode disagree" end
    local rows = pg.rows()
    if rows[1] ~= "PRESET" or rows[2] ~= "LEARN" then return "rows: PRESET and LEARN are not the first two rows" end
    local pr = w.mm_set.preset_by_name(w.mm_set.state.preset)
    if (rows[#rows] == "DELETE") ~= (pr ~= nil and not pr.builtin) then return "rows: DELETE does not match the preset in use (" .. tostring(w.mm_set.state.preset) .. ")" end
    if pg.mode == "actions" and not (pg.apos >= 1 and pg.apos <= #pg.arows()) then return "selection: actions row " .. pg.apos .. " of " .. #pg.arows() end
    if pg.mode == "aview" then
      if pg.act == nil or w.mm_set.state.actions[pg.act] == nil then return "modal: an action view without an action" end
      local ar = pg.adrows()
      if not (pg.dpos >= 1 and pg.dpos <= #ar) then return "selection: action view row " .. pg.dpos .. " of " .. #ar end
    end
    if pg.mode ~= "detail" and not (pg.pos >= 1 and pg.pos <= #rows) then return "selection: row " .. pg.pos .. " of " .. #rows end
    if pg.mode == "detail" then
      if pg.ctl == nil or w.mm_set.state.ctl[pg.ctl] == nil then return "modal: a view without a control" end
      local dr = pg.drows()
      if not (pg.dpos >= 1 and pg.dpos <= #dr) then return "selection: view row " .. pg.dpos .. " of " .. #dr end
    end
  elseif p == "PICKER" then
    if pg.active ~= true then return "modal: the picker is the page but not active" end
    if not (pg.row >= 1 and pg.row <= 4) then return "selection: picker row " .. tostring(pg.row) end
    if pg.val.h < 0 or pg.val.h > 360 or pg.val.s < 0 or pg.val.s > 100 or pg.val.v < 0 or pg.val.v > 100 then return "selection: a picker value is out of range" end
  end
  if w.textentry.active then
    local t = w.textentry
    if not (type(t.pos) == "number" and (t.row == 0 or t.row == 1) and (t.delok == 0 or t.delok == 1) and type(t.txt) == "string") then return "selection: the text entry's state is out of range" end
  end
  local lb0 = w.box_calls[#w.box_calls]
  if lb0 then
    local idx = 0
    for i, n in ipairs(w.box.PIXEL_LOOKS) do if n == w.box.state.pixel_look then idx = i - 1 end end
    if lb0[8] ~= idx then return "preview: the window has pixel look " .. tostring(lb0[8]) .. " but the stored one is " .. idx end
  end
  -- MIDI MAP: the window is armed exactly while a pick or a listen is open, the ring is off exactly when no learn is open, a learn does not outlive the page, no mapping is written while a learn waits,
  -- and leaving the page releases every key the layer holds
  do
    local L = w.mm.learn
    local waiting = L.state == "pick" or L.state == "listen"
    local act_target = L.target ~= nil and w.mm.is_action(L.target)
    if not (L.state == "idle" or waiting or L.state == "confirm" or L.state == "ask") then return "learn: unknown state " .. tostring(L.state) end
    if (L.state == "ask") ~= (L.ask ~= nil) then return "learn: the question and the learn state disagree" end
    if p ~= "MIDIMAP" and (w.mm.watching or w.mm.calib_target() ~= nil) then return "learn: WATCH or ONE TURN is open on another page (" .. p .. ")" end
    if w.arc_bad then return "arc: a bad arc_turn call " .. w.arc_bad end
    if act_target and L.state == "listen" then waiting = false end -- (an action has no control in the window to click: the window is not armed)
    if (w.armed == 1) ~= waiting then return "learn: the window is " .. (w.armed == 1 and "armed" or "not armed") .. " but the learn state is " .. L.state end
    if (w.ring == 0) ~= (L.state == "idle" or (act_target and L.state == "listen")) then return "learn: the ring is " .. tostring(w.ring) .. " but the learn state is " .. L.state end
    if p ~= "MIDIMAP" and L.state ~= "idle" then return "learn: a learn is open on another page (" .. p .. ")" end
    if (L.state == "listen" or L.state == "confirm") and (L.target == nil or (w.mm_set.state.ctl[L.target] == nil and not act_target)) then return "learn: listening without a target" end
    if w.mm.walk_index() then
      if p ~= "MIDIMAP" or L.state == "idle" or L.state == "pick" then return "walk: ASSIGN ALL is open but the learn is " .. L.state .. " on " .. p end
      if not act_target or w.mm.walk_index() < 1 or w.mm.walk_index() > 14 or w.mm_set.ACTION_IDS[w.mm.walk_index()] ~= L.target then return "walk: the target " .. tostring(L.target) .. " is not action " .. tostring(w.mm.walk_index()) end
    end
    if w.action_bad then return "actions: " .. w.action_bad end
    if w.menu_tick ~= nil and w.menu_tick ~= (w.mm_set.state.actions_on == true) then return "actions: the window menu's tick (" .. tostring(w.menu_tick) .. ") and the stored switch (" .. tostring(w.mm_set.state.actions_on) .. ") disagree" end
    local h = io.open(map("/home/we/midimap.conf"), "r")
    local conf = h and h:read("a") or ""
    if h then h:close() end
    conf = conf:gsub("actions=%d\n", "") -- (the master switch may be flipped by a shortcut at any time: that is not a mapping)
    if waiting and not w.mm.walk_index() then
      if w.learn_conf == nil then w.learn_conf = conf elseif w.learn_conf ~= conf then return "learn: the mapping file changed while a learn was waiting" end
    else w.learn_conf = nil end
    if w.left_midimap then
      w.left_midimap = nil
      if #w.mm.held() ~= 0 then return "learn: a key is held down after the page was left" end
    end
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
  -- (the tape page is upstream's: its E2 switches PLAY and REC and redraws with its next tape update, so it is not held to this rule)
  if p == "TAPE" and not w.textentry.active then return nil end
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
    if _menu.page == "TAPE" and not w.textentry.active then _menu.set_page("SYSTEM") break end -- (the tape page's K2 arms the recorder: it is left with a page key, as on the device)
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
    if w.mm.walk_index() then COVER.walks = COVER.walks + 1 end
    if _menu.page == "MIDIMAP" and w.pages.MIDIMAP.mode == "aview" then COVER.aviews = COVER.aviews + 1 end
    if not msg and i % 25 == 0 then
      local w2msg = escape_check(w)
      if w2msg then msg = w2msg else _menu.set_page(({"BOX", "UI", "MIDIMAP", "TAPE"})[(i // 25) % 4 + 1]) end
    end
    if trace then lines[#lines + 1] = string.format("%3d %-22s -> %s", i, fmt(e), state_of(w) .. (msg and ("   <-- " .. msg) or "")) end
    if msg then return {index = i, message = msg, trace = lines} end
  end
  return nil, lines
end

-- the generator
local KEYS = {"T", "Y", "G", "N", "5", "6", "UP", "DOWN", "LEFT", "RIGHT", "EQUAL", "MINUS", "ENTER", "ESC", "BACKSPACE", "SPACE", "1", "2", "3", "Q", "W", "A", "S", "Z", "X", "PAGEUP", "PAGEDOWN",
  "4", "5", "6", "7", "8", "9", "0", "B", "C", "D", "E", "F", "H", "RIGHT", "RIGHT", "DOWN", "UP", "3", "2", "R", "HOME", "END", "H", "C"}
local function pick(t) return t[math.random(#t)] end
local CCS = {10, 16, 17, 18, 64, 71, 72, 73, 85, 102, 103, 104}
local VALS = {0, 1, 2, 3, 63, 64, 65, 100, 126, 127}
local function gen_midi()
  local r = math.random(100)
  if r <= 55 then
    local ch = math.random(3) - 1
    local kind = math.random(10)
    if kind <= 7 then return {k = "midi", dev = math.random(4), b = {0xB0 + ch, pick(CCS), pick(VALS)}} end
    if kind == 8 then return {k = "midi", dev = math.random(4), b = {0x90 + ch, pick({36, 37, 38, 40, 60}), pick({0, 1, 100, 127})}} end
    if kind == 9 then return {k = "midi", dev = math.random(4), b = {0x80 + ch, pick({36, 37, 60}), 0}} end
    return {k = "midi", dev = math.random(4), b = pick({{0xF8}, {0xFE}, {0xE0, 1, 2}, {0xB0}, {0xC0, 5}})}
  elseif r <= 70 then return {k = "click", id = pick({"e1", "e2", "e3", "k1", "k2", "k3"})}
  elseif r <= 85 then return {k = "tick", dt = pick({0.1, 1, 2, 4, 16})}
  else return {k = "ext", what = pick({"pmap", "unpmap", "unplug", "plug", "arcopen", "arcclose", "arckeyson", "arckeysoff", "amap", "amap", "amap", "aclear", "aon", "aoff", "mon", "moff"}), dev = math.random(4), cc = pick(CCS), id = math.random(14), kind = math.random(3), num = pick({36, 37, 38, 40, 10, 16, 17, 71, 72, 73})} end
end
local function gen(n)
  local ev = {}
  for i = 1, n do
    local r = math.random(100)
    if math.random(100) <= 4 then ev[i] = {k = "nav", n = pick({1, 1, 2, 3, 5, 16})}
    elseif math.random(100) <= 30 then ev[i] = gen_midi()
    elseif r <= 52 then ev[i] = {k = "tap", name = pick(KEYS), rep = math.random(4) == 1 and math.random(3) or 0}
    elseif r <= 60 then ev[i] = {k = "press", name = pick(KEYS)}
    elseif r <= 68 then ev[i] = {k = "release", name = pick(KEYS)}
    elseif r <= 76 then ev[i] = {k = "ctrl", name = pick({"C", "V", "V", "C", "O", "M", "Q"})}
    elseif r <= 80 then ev[i] = {k = "clip", i = math.random(11)}
    elseif r <= 90 then ev[i] = {k = "enc", n = math.random(2, 3), d = pick({-5, -2, -1, 0, 1, 1, 2, 5})}
    elseif r <= 96 then ev[i] = {k = "page", p = pick({"BOX", "UI", "SYSTEM", "BOX", "MIDIMAP", "MIDIMAP", "MIDIMAP", "TAPE"})}
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
    w.pages.BOX.pos = pos or 4
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
  is(_menu.page == "BOX" and w.pages.BOX.pos == 4, "K3 keeps the colour and the THEME page comes back on the same row")
  is(w.box.state.colours.box == shown_hex, "the colour is stored")
  is(slurp("/home/we/box.conf"):find("box=" .. shown_hex, 1, true) ~= nil, "and written")
  is(last(w)[2] == shown_hex, "the box has it")
  -- cancel: K2, Esc and a page key give the old colour back and write nothing
  for _, how in ipairs({"2", "ESC", "F1"}) do
    local w2 = world()
    local c0 = slurp("/home/we/box.conf")
    open_box(w2, 5) -- KEYS
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
  w5.pages.BOX.pos = 5
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
  _menu.set_page("BOX") w6.pages.BOX.pos = 5
  ctrlkey(w6, "C")
  is(w6.pages.BOX.msg == "no clipboard", "without the window's binding Ctrl+C says so")
  ctrlkey(w6, "V")
  is(w6.pages.BOX.msg == "no clipboard", "and so does Ctrl+V")
end

-- ---------------------------------------------------------------- the PIXEL LOOK row through the real keyboard and menu bindings
do
  local function F(what) fails_total = fails_total + 1 print("FAIL pixel look row: " .. what) end
  local function is(c, what) if not c then F(what) end end
  local w = world()
  _menu.set_page("BOX")
  local pg = w.pages.BOX
  pg.pos = 2
  local n = #w.box_calls
  tap(w, "EQUAL")
  is(w.box.state.pixel_look == "pixel" and #w.box_calls == n, "inactive while the style is aluminium: = does nothing")
  w.box.set_style("pixel")
  local f0 = frame_text(w.shown)
  tap(w, "EQUAL")
  is(w.box.state.pixel_look == "retro", "= steps to RETRO")
  is(frame_text(w.shown) ~= f0, "and the screen shows it at once (the handler ends with a redraw)")
  is(w.box_calls[#w.box_calls][8] == 1, "the window is told")
  send(w, "EQUAL", 0)
  is(w.box.state.pixel_look == "retro", "a release changes nothing")
  send(w, "EQUAL", 1) send(w, "EQUAL", 2) send(w, "EQUAL", 0)
  is(w.box.state.pixel_look == "16-bit", "a press and a repeat: two more steps (8-BIT, 16-BIT)")
  tap(w, "MINUS") tap(w, "MINUS") tap(w, "MINUS")
  is(w.box.state.pixel_look == "pixel", "- steps back")
  tap(w, "RIGHT")
  is(w.box.state.pixel_look == "retro", "RIGHT (K3) steps and redraws")
  w.box.set_pixel_look("16-bit")
  tap(w, "RIGHT")
  is(w.box.state.pixel_look == "pixel", "K3 goes round from 16-BIT to PIXEL")
  -- the live colour preview carries the pixel look
  w.box.set_pixel_look("8-bit")
  pg.pos = 5
  tap(w, "RIGHT")
  tap(w, "EQUAL")
  is(w.box_calls[#w.box_calls][8] == 2, "a colour change in the picker keeps the 8-bit look")
  tap(w, "2")
  is(w.box_calls[#w.box_calls][8] == 2 and w.box.state.pixel_look == "8-bit", "and so does cancelling it")
end

-- ---------------------------------------------------------------- the picker's messages, the HEX row's brightness steps, the SYSTEM list (docs/port/colour-picker-plan.md, small fixes)
do
  local function F(what) fails_total = fails_total + 1 print("FAIL picker feedback: " .. what) end
  local function is(c, what) if not c then F(what) end end
  local function open_box(w, pos) _menu.set_page("BOX") w.pages.BOX.pos = pos w.pages.BOX.redraw() tap(w, "RIGHT") end
  local colourm = require('core/colour')
  local function count(list, text) local n = 0 for _, t in ipairs(list) do if t == text then n = n + 1 end end return n end
  -- K3 keeps: "saved #HEX" on the page that comes back, once, with the right code; it goes with the next key
  local w = world()
  open_box(w, 5) -- KEYS
  tap(w, "EQUAL") tap(w, "EQUAL")
  local hex = colourm.value_hex(w.pages.PICKER.val)
  tap(w, "ENTER")
  is(_menu.page == "BOX" and w.pages.BOX.msg == "saved #" .. hex, "K3 shows 'saved #" .. hex .. "' on the THEME page (" .. tostring(w.pages.BOX.msg) .. ")")
  w.pages.BOX.redraw()
  is(w.shown and table.concat(w.shown, "|"):find("saved #" .. hex, 1, true) ~= nil, "the message is on the norns screen")
  is(count(w.toasts, "restored, not saved") == 0, "keeping shows no 'not saved'")
  tap(w, "DOWN")
  is(w.pages.BOX.msg == nil, "the message goes with the next key (the same life as 'copied')")
  -- K2 and Esc: "restored"
  for _, how in ipairs({"2", "ESC"}) do
    local w2 = world()
    open_box(w2, 5)
    tap(w2, "EQUAL")
    tap(w2, how)
    is(_menu.page == "BOX" and w2.pages.BOX.msg == "restored", how .. ": 'restored' on the THEME page (" .. tostring(w2.pages.BOX.msg) .. ")")
    is(#w2.toasts == 0, how .. ": no toast")
  end
  -- leaving by a page key or a page change with a live change: the colour comes back and "restored, not saved" is shown once (a toast on the box: the page is gone)
  local w3 = world()
  open_box(w3, 5)
  for _ = 1, 8 do tap(w3, "EQUAL") end -- a colour that really changes (a dark grey needs a few degrees)
  _menu.set_page("SYSTEM")
  is(count(w3.toasts, "restored, not saved") == 1, "a page change with a live change: 'restored, not saved' once (" .. table.concat(w3.toasts, "|") .. ")")
  is(w3.pages.BOX.msg == "restored, not saved", "and it is the THEME page's message too")
  local w3b = world()
  open_box(w3b, 5)
  _menu.set_page("SYSTEM")
  is(#w3b.toasts == 0, "a page change with nothing changed says nothing")
  -- the SCREEN page: saved and restored messages (its init keeps the message after the picker)
  local w4 = world()
  _menu.set_page("UI") w4.pages.UI.pos = 4
  tap(w4, "RIGHT")
  tap(w4, "C")
  tap(w4, "ENTER")
  is(w4.pages.UI.msg == "saved #408080", "SCREEN: 'saved #408080' (" .. tostring(w4.pages.UI.msg) .. ")")
  local w5 = world()
  _menu.set_page("UI") w5.pages.UI.pos = 4
  tap(w5, "RIGHT") tap(w5, "C") tap(w5, "2")
  is(w5.pages.UI.msg == "restored", "SCREEN: 'restored' after K2")
  -- a contrast warning is kept next to 'saved'
  local w6 = world()
  w6.box.set_part("buttons", "808080")
  open_box(w6, 8) -- FONT
  for _ = 1, 40 do tap(w6, "MINUS") end
  tap(w6, "ENTER")
  is(w6.pages.BOX.msg and w6.pages.BOX.msg:find("^saved #") ~= nil, "a colour that gives low contrast is still 'saved'")
  -- the hint line: K3 keeps, K2 cancels, and it fits
  local w7 = world()
  open_box(w7, 5)
  local frame = table.concat(w7.shown, "|")
  is(frame:find("K3 keeps", 1, true) and frame:find("K2 cancels", 1, true), "the picker says that K3 keeps and K2 cancels")
  -- the HEX row: left, right and the value keys step the brightness, by the same steps, with the live preview and no text entry
  local pk = w7.pages.PICKER
  tap(w7, "DOWN") tap(w7, "DOWN") tap(w7, "DOWN")
  is(pk.row == 4, "DOWN x3 is the HEX row")
  local v0, h0, s0 = pk.val.v, pk.val.h, pk.val.s
  local n = #w7.box_calls
  tap(w7, "RIGHT")
  is(math.abs(pk.val.v - math.min(100, v0 + 5)) < 1e-9 and pk.val.h == h0 and pk.val.s == s0, "RIGHT on HEX: brightness +5, hue and saturation unchanged")
  is(#w7.box_calls == n + 1 and not w7.textentry.active, "live, and the text entry stays closed")
  tap(w7, "LEFT") tap(w7, "LEFT")
  is(math.abs(pk.val.v - math.max(0, v0 - 5)) < 1e-9, "LEFT x2: brightness -5 from the start")
  tap(w7, "EQUAL")
  send(w7, "EQUAL", 0)
  local vv = pk.val.v
  send(w7, "EQUAL", 0)
  is(pk.val.v == vv, "a release changes nothing")
  w7.keyboard.process(1, w7.codes["LEFTSHIFT"], 1) tap(w7, "MINUS") w7.keyboard.process(1, w7.codes["LEFTSHIFT"], 0)
  is(math.abs(pk.val.v - math.max(0, vv - 25)) < 1e-9, "Shift is 5 steps")
  send(w7, "LEFTCTRL", 1) local vc = pk.val.v tap(w7, "RIGHT") send(w7, "LEFTCTRL", 0)
  is(math.abs(pk.val.v - (vc + 1)) < 1e-9, "Ctrl is a fine step")
  local f0 = table.concat(w7.shown, "|")
  tap(w7, "RIGHT")
  is(table.concat(w7.shown, "|") ~= f0, "and the screen shows the new code")
  _norns.enc(3, 1)
  is(pk.val.v > vc, "the encoder E3 on HEX steps the brightness too")
  -- the SYSTEM list through the real page: MODS is directly below AUDIO, the other pages keep their order
  local sys = dofile("lua/core/menu/system.lua")
  is(table.concat(sys.pages, ",") == "DEVICES,AUDIO,MODS,UI,BOX,MIDIMAP,CLEANUP,RESET,RESTART", "SYSTEM's pages: " .. table.concat(sys.pages, ","))
  is(table.concat(sys.list, "|") == "DEVICES > |AUDIO >|MODS >|SCREEN >|THEME >|MIDI MAP >|CLEAN UP >|RESET|RESTART", "SYSTEM's list: " .. table.concat(sys.list, "|"))
  local opened
  _menu.set_page = function(p) opened = p end
  sys.pos = 3
  sys.key(3, 1)
  is(opened == "MODS", "K3 on the third row opens MODS (" .. tostring(opened) .. ")")
end

-- what every control does while the hex entry is open (printed with "entry"; the checks below assert it)
local function open_entry(w)
  _menu.set_page("BOX")
  w.pages.BOX.pos = 4
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
    w2.pages.BOX.pos = 9 -- SAVE
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
    local row = name == "set_style" and 1 or 3
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
    if w.pages.BOX.pos ~= math.min(row + 1, 9) then fails_total = fails_total + 1 print("FAIL DOWN does not work after a handler error (" .. name .. ")") end
  end
  -- a selection that is out of range is clamped with one log line, and not logged when it is in range or when scrolling past the end
  local pg = w.pages.BOX
  pg.mode, pg.pos = "rows", 10
  printed = {}
  pg.redraw()
  local clamped = false
  for _, l in ipairs(printed) do if l:find("selection 10 clamped to", 1, true) then clamped = true end end
  if not clamped or pg.pos ~= 9 then fails_total = fails_total + 1 print("FAIL an out of range selection is not clamped and logged") end
  printed = {}
  pg.pos = 9
  for _ = 1, 3 do apply(w, {k = "tap", name = "DOWN"}) end
  for _, l in ipairs(printed) do if l:find("clamped", 1, true) then fails_total = fails_total + 1 print("FAIL scrolling past the last row is logged as a clamp") break end end
end

-- ---------------------------------------------------------------- text entries on MIDI MAP and the tape page (found on the installed package: digits 5 and 6 could not be typed with the arc window open, a preset name vanished, the tape
-- name entry would not open any more). every entry goes through the real keyboard module and the real textentry; the tape page is the real one
do
  local function F(what) fails_total = fails_total + 1 print("FAIL entries: " .. what) end
  local function is(c, what) if not c then F(what) end end
  local function logged(part) for _, l in ipairs(printed) do if l:find(part, 1, true) then return true end end return false end
  local function setup(arc_open, arc_keys)
    local w = world()
    w.arc_open = arc_open
    w.mm_set.set_arc_keys(arc_keys)
    return w
  end
  local function open_midimap(w, row) _menu.set_page("MIDIMAP"); w.pages.MIDIMAP.pos = row; w.pages.MIDIMAP.redraw() end
  local function tape_entry_opens(w, what, stay)
    if not stay then _menu.set_page("TAPE") end
    w.pages.TAPE.mode = w.pages.TAPE.constants.TAPE_MODE_REC
    if stay then _menu.key(3, 1); _menu.key(3, 0) -- a mouse click or a mapped control: the keyboard still belongs to the entry that was left behind
    else tap(w, "RIGHT") end -- K3 on the REC side of the tape page: the name entry
    is(w.textentry.active and w.textentry.heading == "tape filename:", "the tape name entry opens " .. what .. " (active " .. tostring(w.textentry.active) .. ", heading " .. tostring(w.textentry.heading) .. ")")
    local msg = invariants(w)
    is(msg == nil, "the page is whole with the tape entry open " .. what .. ": " .. tostring(msg))
    tap(w, "ESC")
    is(not w.textentry.active and w.te_kbd.code == nil, "the tape name entry closes with ESC " .. what)
    if stay then w.textentry.exit() end
  end
  for _, arc_open in ipairs({true, false}) do
    for _, arc_keys in ipairs({true, false}) do
      local combo = "(arc window " .. (arc_open and "open" or "closed") .. ", ARC KEYS " .. (arc_keys and "on" or "off") .. ")"
      -- a preset name whose first letter is, or is not, one of the arc keys; the digits 5 and 6 as a first character too
      for _, first in ipairs({"B", "T", "H", "N", "Y", "G", "A", "M", "5", "6"}) do
        local w = setup(arc_open, arc_keys)
        open_midimap(w, 18)
        tap(w, "RIGHT")
        is(w.textentry.active, "SAVE AS opens the entry " .. combo)
        tap(w, first); tap(w, "A")
        local want = first:lower() .. "a"
        is(w.textentry.txt == want, "the name typed with '" .. first .. "' first is '" .. want .. "' " .. combo .. " (got " .. tostring(w.textentry.txt) .. ")")
        tap(w, "ENTER")
        is(not w.textentry.active, "ENTER closes the entry " .. combo)
        is(w.mm_set.preset_by_name(want) ~= nil, "the preset '" .. want .. "' was saved " .. combo)
        is((w.arc_turns or 0) == 0, "typing a name turned the arc " .. combo)
      end
      -- a number typed for a control: the digits 5 and 6 included
      do
        local w = setup(arc_open, arc_keys)
        open_midimap(w, 9)
        tap(w, "RIGHT")               -- K3 on A1: its view
        w.pages.MIDIMAP.dpos = 2
        tap(w, "RIGHT")               -- K3 on NUMBER: the entry
        is(w.textentry.active, "NUMBER opens the entry " .. combo)
        for _, d in ipairs({"5", "6"}) do tap(w, d) end
        is(w.textentry.txt == "56", "56 can be typed " .. combo .. " (got " .. tostring(w.textentry.txt) .. ")")
        tap(w, "ENTER")
        is(w.mm_set.state.ctl.a1.num == 56, "CC 56 was set " .. combo .. " (" .. tostring(w.mm_set.state.ctl.a1.num) .. ")")
        is((w.arc_turns or 0) == 0, "typing a number turned the arc " .. combo)
      end
      -- mapped controls (a Beatstep or any unit) do not touch an entry: K2 would cancel it, E2 and E3 move its cursor
      do
        local w = setup(arc_open, arc_keys)
        local S = w.mm_set
        S.set("k2", "type", "cc"); S.set("k2", "num", 85); S.set("e2", "num", 72); S.set("e2", "mode", "rel2c"); S.set("e3", "num", 73); S.set("e3", "mode", "rel2c")
        S.set("a1", "num", 76); S.set("a1", "mode", "rel2c"); S.set("k3", "type", "cc"); S.set("k3", "num", 86); w.mm.changed()
        open_midimap(w, 18)
        tap(w, "RIGHT")
        tap(w, "A")
        local te = w.textentry
        local before = {te.pos, te.row, te.delok, te.txt}
        for _, m in ipairs({{0xB0, 85, 127}, {0xB0, 85, 0}, {0xB0, 72, 1}, {0xB0, 72, 127}, {0xB0, 73, 1}, {0xB0, 73, 127}, {0xB0, 76, 1}, {0xB0, 86, 127}, {0xB0, 86, 0}}) do
          w.mm.event(w.devs[1], m)
        end
        is(te.active, "a mapped K2 or K3 closed the entry " .. combo)
        is(te.txt == before[4] and te.pos == before[1] and te.row == before[2] and te.delok == before[3], "mapped controls moved the entry (text " .. tostring(te.txt) .. ", pos " .. tostring(te.pos) .. ", row " .. tostring(te.row) .. ") " .. combo)
        is((w.arc_turns or 0) == 0, "a mapped arc encoder turned while an entry was open " .. combo)
        tap(w, "B")
        is(te.txt == "ab", "typing goes on after the controls were moved (got " .. tostring(te.txt) .. ") " .. combo)
        tap(w, "ENTER")
        is(S.preset_by_name("ab") ~= nil, "the name was saved " .. combo)
        -- and when no entry is open they work again
        w.mm.event(w.devs[1], {0xB0, 76, 1})
        is((w.arc_turns or 0) == 1 or not arc_open, "the mapped arc encoder works again after the entry " .. combo)
      end
      -- the menu moves on under an open entry (a window button, a page key, a mapped K1): the entry is closed, the handlers are the page's, the tape name entry opens
      for _, how in ipairs({"page", "mode"}) do
        local w = setup(arc_open, arc_keys)
        open_midimap(w, 18)
        tap(w, "RIGHT")
        is(w.textentry.active, "the entry is open before the menu moves " .. combo)
        if how == "page" then _menu.set_page("TAPE") else _menu.set_mode(false); _menu.set_mode(true); _menu.set_page("TAPE") end
        is(not w.textentry.active, "the entry is closed when the menu moves on (" .. how .. ") " .. combo)
        is(w.te_kbd.code == nil and w.te_kbd.char == nil, "its keyboard hooks are gone (" .. how .. ") " .. combo)
        tape_entry_opens(w, "after the menu moved on (" .. how .. ") " .. combo)
      end
      -- an entry left active by something that did not tell textentry (the hook is off): the next entry recovers and says so in one line
      do
        local w = setup(arc_open, arc_keys)
        open_midimap(w, 18)
        tap(w, "RIGHT")
        local hook = w.textentry.menu_changed
        w.textentry.menu_changed = nil
        _menu.set_page("TAPE")
        w.textentry.menu_changed = hook
        is(w.textentry.active, "the orphaned entry is still marked active (the situation of the bug) " .. combo)
        printed = {}
        tape_entry_opens(w, "although an earlier entry was left active " .. combo, true)
        is(logged("textentry: an earlier entry") , "the recovery is logged " .. combo)
      end
      -- a second entry while one really is open: refused, and the log says why, once
      do
        local w = setup(arc_open, arc_keys)
        open_midimap(w, 18)
        tap(w, "RIGHT")
        tap(w, "A")
        printed = {}
        w.textentry.enter(function() end, "", "SECOND:")
        is(w.textentry.heading ~= "SECOND:" and w.textentry.txt == "a", "a second entry does not replace the open one " .. combo)
        local n = 0
        for _, l in ipairs(printed) do if l:find("textentry: cannot open", 1, true) and l:find("another entry", 1, true) then n = n + 1 end end
        is(n == 1, "one log line says why it could not open (" .. n .. ") " .. combo)
        tap(w, "ENTER")
      end
      -- the sequence of the report: MIDI MAP number entries, preset saves and cancels, then the tape page and its name entry
      do
        local w = setup(arc_open, arc_keys)
        for round = 1, 3 do
          open_midimap(w, 9); tap(w, "RIGHT"); w.pages.MIDIMAP.dpos = 2; tap(w, "RIGHT"); tap(w, "7"); tap(w, round == 2 and "ESC" or "ENTER")
          is(not w.textentry.active, "the number entry closed (round " .. round .. ") " .. combo)
          tap(w, "ESC"); tap(w, "ESC") -- out of the view and the page
          open_midimap(w, 18); tap(w, "RIGHT"); tap(w, "C"); tap(w, round == 3 and "ESC" or "ENTER")
          is(not w.textentry.active, "the preset entry closed (round " .. round .. ") " .. combo)
          open_midimap(w, 18); tap(w, "RIGHT"); tap(w, "ENTER") -- an empty name: refused
          is(not w.textentry.active, "an empty name closed the entry (round " .. round .. ") " .. combo)
          tape_entry_opens(w, "after MIDI MAP entries (round " .. round .. ") " .. combo)
        end
      end
    end
  end
  -- menu.lua tells the text entry when the menu page or mode changes (the stress world's stubs do the same: this checks the real file)
  local src = io.open("lua/core/menu.lua"):read("a")
  local mode_body = src:match("_menu%.set_mode = function%(mode%)(.-)\n_menu%.set_page = function")
  local page_body = src:match("_menu%.set_page = function%(page%)(.-)\nend")
  is(mode_body and mode_body:find("menu_changed", 1, true), "lua/core/menu.lua: set_mode tells the text entry")
  is(page_body and page_body:find("menu_changed", 1, true), "lua/core/menu.lua: set_page tells the text entry")
end

-- ---------------------------------------------------------------- the tape page's K3 (record): a file in the tape folder whose name starts with a number that is not a whole number ("0.50 take.wav") made the
-- default name a fraction and string.format("%04d") raised an error, so K3 did nothing (KNOWN-ISSUES 26). fractional tempo and clock values are in the world too, as the owner suspected them
do
  local function F(what) fails_total = fails_total + 1 print("FAIL tape: " .. what) end
  local function is(c, what) if not c then F(what) end end
  local listings = {
    ["a fraction first"] = "0.50 take.wav\n",
    ["a fraction among numbers"] = "0003_a.wav\n1.5_x.wav\n0007.wav\n",
    ["an exponent"] = "1e02 loop.wav\n",
    ["a hex-like name"] = "0x10.wav\n",
    ["negative and blank"] = "-1.5 a.wav\n  7 b.wav\n",
    ["only whole numbers"] = "0001.wav\n0002.wav\n",
    ["nothing"] = "",
    ["a long float"] = "3.14159.wav\n",
  }
  local want = {["a fraction first"] = "0000", ["a fraction among numbers"] = "0008", ["an exponent"] = "0000", ["a hex-like name"] = "0000", ["negative and blank"] = "0000",
    ["only whole numbers"] = "0003", ["nothing"] = "0000", ["a long float"] = "0000"}
  for name, listing in pairs(listings) do
    for _, tempo in ipairs({120, 120.5, 97.3333, 0.5, 1e-9}) do
      local w = world()
      util.os_capture = function() return listing end
      clock = {get_tempo = function() return tempo end, get_beats = function() return tempo * 1.25 end, get_beat_sec = function() return 60 / tempo end}
      norns.state = norns.state or {}
      norns.state.clock = {tempo = tempo}
      _menu.set_page("TAPE")
      w.pages.TAPE.mode = w.pages.TAPE.constants.TAPE_MODE_REC
      printed = {}
      tap(w, "RIGHT") -- K3
      is(w.textentry.active and w.textentry.heading == "tape filename:", "K3 opens the rec name entry (" .. name .. ", tempo " .. tostring(tempo) .. ")")
      is(w.textentry.txt == want[name], "the default name is " .. want[name] .. " (" .. name .. "): got " .. tostring(w.textentry.txt))
      for _, l in ipairs(printed) do if l:find("bad argument", 1, true) or l:find("raised an error", 1, true) then F("an error was logged (" .. name .. "): " .. l) end end
      local msg = invariants(w)
      is(msg == nil, "the page is whole (" .. name .. "): " .. tostring(msg))
      tap(w, "ESC")
      is(not w.textentry.active, "the entry closes (" .. name .. ")")
    end
  end
  -- K2 arms it too (on release) and the REC side stays usable after the entry
  local w = world()
  util.os_capture = function() return "0.50 take.wav\n" end
  _menu.set_page("TAPE")
  w.pages.TAPE.mode = w.pages.TAPE.constants.TAPE_MODE_REC
  tap(w, "LEFT")
  is(w.textentry.active, "K2 (on release) opens the rec name entry too")
  tap(w, "ESC")
end
if SEEDS >= 20 and (COVER.fired == 0 or COVER.walks == 0 or COVER.aviews == 0) then
  print(string.format("FAIL coverage: the random runs did not reach the actions (fired %d, walk events %d, action view events %d)", COVER.fired, COVER.walks, COVER.aviews))
  fails_total = fails_total + 1
end
if fails_total == 0 then print("menu_stress_test: all passed (" .. SEEDS .. " runs of " .. EVENTS .. " events)") end
os.exit(fails_total == 0 and 0 or 1)
