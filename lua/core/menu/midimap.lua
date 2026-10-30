-- SYSTEM > MIDI MAP (computers only, see core/menu/system.lua): which MIDI controls turn E1-E3 and press K1-K3. docs/port/midi-map-plan.md 2.6. the mappings live in core/midimap_settings.lua
-- (file: midimap.conf in the norns home, presets in midimap-presets/), the layer that acts on messages and the learn flow are core/midimap.lua. every change is saved at once.
--   rows: PRESET, LEARN, E1 E2 E3 K1 K2 K3, ON CLASH, SAVE AS, and DELETE only while one of his own presets is in use
--   E2 row, E3 change (PRESET: browse the presets, K3 applies), K3: LEARN starts a pick (click a control in the window, then move the controller), a control opens its view, SAVE AS asks for a name,
--   DELETE asks once. K2 goes back (out of a learn, a view or the question, else to SYSTEM). a view has LEARN, NUMBER, DEVICE, CHANNEL, MODE and SENS (encoders), TYPE and THRESHOLD (keys), CLEAR
-- while a learn is on the screen shows an inverted banner, the target row and the seconds left; the window rings the control (core/midimap.lua)

local S = require 'core/midimap_settings'
local mm = require 'core/midimap'
local V = require 'core/midimap_value'

local m = {pos = 1, top = 1, mode = "rows", dpos = 1, dtop = 1, ctl = nil, msg = nil, confirm = nil, browse = nil}

local VISIBLE = 5
local CTLS = {"e1", "e2", "e3", "k1", "k2", "k3"}

local function is_enc(id) return id:sub(1, 1) == "e" end

--- the rows of the page, in order (DELETE only for one of his own presets)
function m.rows()
  local r = {"PRESET", "LEARN", "E1", "E2", "E3", "K1", "K2", "K3", "ON CLASH", "SAVE AS"}
  local p = S.preset_by_name(S.state.preset)
  if p ~= nil and not p.builtin then r[#r + 1] = "DELETE" end
  return r
end

--- the rows of the view of the control in `m.ctl`
function m.drows()
  local id = m.ctl or "e1"
  local c = S.state.ctl[id]
  if is_enc(id) then return {"LEARN", "NUMBER", "DEVICE", "CHANNEL", "MODE", "SENS", "CLEAR"} end
  local r = {"LEARN", "TYPE", "NUMBER", "DEVICE", "CHANNEL"}
  if c.type == "cc" then r[#r + 1] = "THRESHOLD" end
  r[#r + 1] = "CLEAR"
  return r
end

local function fit(s, w)
  if screen.text_extents(s) <= w then return s end
  local n = #s
  while n > 1 do
    n = n - 1
    if screen.text_extents(s:sub(1, n) .. "..") <= w then return s:sub(1, n) .. ".." end
  end
  return s:sub(1, 1)
end

local function dbg(s) print("MIDI MAP page: " .. s) end

-- ---------------------------------------------------------------- the devices
--- the choices of a control's DEVICE row: ANY, every device by name, the name of an interface with several ports (`mio` for `mio 1`, `mio 2`), and a remembered name that is not there
function m.device_choices()
  local names, seen = {}, {}
  for _, d in pairs(midi.devices or {}) do
    if d.name and not seen[d.name] then seen[d.name] = true; names[#names + 1] = d.name end
  end
  local bases = {}
  for _, n in ipairs(names) do
    local base = n:match("^(.-) %d+$")
    if base and base ~= "" then bases[base] = (bases[base] or 0) + 1 end
  end
  local list = {}
  for _, n in ipairs(names) do list[#list + 1] = {value = n, label = n:upper()} end
  for base, count in pairs(bases) do
    if count >= 2 and not seen[base] then list[#list + 1] = {value = base, label = base:upper() .. " (ALL PORTS)"} end
  end
  table.sort(list, function(a, b) return a.value:lower() < b.value:lower() end)
  table.insert(list, 1, {value = "ANY", label = "ANY"})
  local id = m.ctl
  local c = id and S.state.ctl[id]
  if c and c.dev ~= "ANY" then
    local have = false
    for _, e in ipairs(list) do if V.norm_name(e.value) == V.norm_name(c.dev) then have = true end end
    if not have then
      local present = false
      for _, n in ipairs(names) do if V.name_matches(c.dev, n) then present = true end end
      if present then list[#list + 1] = {value = c.dev, label = c.dev:upper() .. " (ALL PORTS)"}
      else list[#list + 1] = {value = c.dev, label = c.dev:upper() .. " (ABSENT)"} end
    end
  end
  return list
end

local function device_index(list, c)
  for i, e in ipairs(list) do if V.norm_name(e.value) == V.norm_name(c.dev) then return i end end
  return 1
end

-- ---------------------------------------------------------------- texts
local function clash_map()
  local out = {}
  for _, item in ipairs(mm.clashes()) do out[item.id] = item end
  return out
end

local function ctl_text(id, clash)
  local c = S.state.ctl[id]
  if c.type == "none" or c.num == nil then return "-----" end
  local t
  if c.type == "note" then t = "NOTE " .. c.num
  elseif is_enc(id) then t = "CC" .. c.num .. " " .. mm.MODE_NAMES[c.mode] .. (mm.guess[id] and "?" or "")
  else t = "CC" .. c.num .. " >" .. c.threshold end
  if clash and clash[id] then t = t .. " !" end
  return t
end

local function preset_text()
  local name = m.browse or S.state.preset
  local p = S.preset_by_name(name)
  local text = p and p.label or name
  if p and not p.builtin then text = "* " .. text end
  return text
end

local function row_text(row, clash)
  if row == "PRESET" then return preset_text()
  elseif row == "LEARN" then return "CLICK A CONTROL"
  elseif row == "ON CLASH" then return S.state.on_clash == "both" and "BOTH" or "PARAMS MAP"
  elseif row == "SAVE AS" then return "NAME..."
  elseif row == "DELETE" then local p = S.preset_by_name(S.state.preset) return p and ("* " .. p.name) or ""
  else return ctl_text(row:lower(), clash) end
end

local function detail_text(row)
  local id = m.ctl
  local c = S.state.ctl[id]
  if row == "LEARN" then return "K3"
  elseif row == "TYPE" then return c.type:upper()
  elseif row == "NUMBER" then
    if c.num == nil then return "-" end
    return (c.type == "note" and "NOTE " or "CC ") .. c.num
  elseif row == "DEVICE" then
    local list = m.device_choices()
    return list[device_index(list, c)].label
  elseif row == "CHANNEL" then return c.ch == 0 and "ANY" or tostring(c.ch)
  elseif row == "MODE" then return mm.MODE_NAMES[c.mode] .. (mm.guess[id] and "?" or "")
  elseif row == "SENS" then return tostring(c.sens)
  elseif row == "THRESHOLD" then return ">" .. c.threshold
  end
  return ""
end

-- ---------------------------------------------------------------- selection
local function clamp_rows()
  local n = #m.rows()
  m.pos = math.max(1, math.min(n, m.pos))
  if m.pos < m.top then m.top = m.pos end
  if m.pos > m.top + VISIBLE - 1 then m.top = m.pos - VISIBLE + 1 end
  m.top = math.max(1, math.min(m.top, math.max(1, n - VISIBLE + 1)))
end

local function clamp_detail()
  local n = #m.drows()
  m.dpos = math.max(1, math.min(n, m.dpos))
  if m.dpos < m.dtop then m.dtop = m.dpos end
  if m.dpos > m.dtop + VISIBLE - 1 then m.dtop = m.dpos - VISIBLE + 1 end
  m.dtop = math.max(1, math.min(m.dtop, math.max(1, n - VISIBLE + 1)))
end

local function reclaim()
  if norns.menu.status() and norns.menu.get_key() ~= m.key then
    norns.menu.set(m.enc, m.key, m.redraw, m.refresh)
  end
end

local function learning() return mm.learn.state ~= "idle" end

function m.changed()
  if _menu.page == "MIDIMAP" and norns.menu.status() then _menu.redraw() end
end

m.init = function()
  mm.load()
  mm.on_change = m.changed
  m.mode, m.confirm, m.msg, m.browse, m.ctl = "rows", nil, nil, nil, nil
  clamp_rows()
end

m.deinit = function()
  mm.leave()
  mm.on_change = nil
end

-- ---------------------------------------------------------------- names and numbers (the text entry)
local function name_accept(text)
  if #text > S.MAX_NAME then return false, S.MAX_NAME .. " characters max" end
  if text:find("[^%w _%.%-]") then return false, "letters, digits, - _ . only" end
  return true
end

local function name_hint(text)
  local t = tostring(text or "")
  if t:match("^%s*$") then return "" end
  local v, why = S.validate_name(t)
  return v and "" or why
end

local function name_done(text)
  reclaim()
  if text ~= nil then
    local ok, why, existing = S.save_preset(text)
    if ok then
      m.msg = "saved: " .. S.state.preset
    elseif why == "exists" then
      m.mode = "confirm"
      m.confirm = {kind = "overwrite", name = existing, typed = text, text = "OVERWRITE " .. existing .. "?"}
    else
      m.msg = why
    end
  end
  clamp_rows()
  _menu.redraw()
end

local function number_done(text)
  reclaim()
  if text ~= nil then
    local n = tonumber(text)
    local ok = n ~= nil and S.set(m.ctl, "num", n)
    if not ok then m.msg = "0 TO 127" end
  end
  _menu.redraw()
end

local function number_accept(text)
  if not text:find("^%d*$") then return false, "digits only" end
  if #text > 3 then return false, "0 to 127" end
  return true
end

local function number_hint(text)
  local n = tonumber(text)
  if n and n > 127 then return "0 to 127" end
  return ""
end

-- ---------------------------------------------------------------- keys and encoders
local TYPES = {"none", "cc", "note"}
local function step_in(list, value, d)
  local idx = 1
  for i, v in ipairs(list) do if v == value then idx = i end end
  return list[math.max(1, math.min(#list, idx + d))]
end

local function after_preset()
  local list = mm.clashes()
  if #list > 0 then m.msg = mm.clash_short(list[1]) end
end

local function key_rows(n)
  if n == 2 then
    _menu.set_page("SYSTEM")
    return
  end
  if n ~= 3 then return end
  local row = m.rows()[m.pos]
  if row == "PRESET" then
    local name = m.browse or S.state.preset
    if S.preset_by_name(name) and S.select_preset(name) then
      m.msg = "applied: " .. S.state.preset
      after_preset()
    end
    m.browse = nil
  elseif row == "LEARN" then
    mm.start_pick()
  elseif row == "ON CLASH" then
    S.set_clash(S.state.on_clash == "params" and "both" or "params")
  elseif row == "SAVE AS" then
    require('textentry').enter(name_done, "", "NAME FOR THIS PRESET:", name_hint, {accept = name_accept})
  elseif row == "DELETE" then
    local p = S.preset_by_name(S.state.preset)
    if p and not p.builtin then
      m.mode = "confirm"
      m.confirm = {kind = "delete", name = p.name, text = "DELETE " .. p.name .. "?"}
    end
  else
    m.ctl = row:lower()
    m.mode = "detail"
    m.dpos, m.dtop = 1, 1
  end
end

local function key_detail(n)
  if n == 2 then
    m.mode, m.ctl = "rows", nil
    clamp_rows()
    return
  end
  if n ~= 3 then return end
  local row = m.drows()[m.dpos]
  if row == "LEARN" then
    mm.start_listen(m.ctl)
  elseif row == "NUMBER" then
    local c = S.state.ctl[m.ctl]
    require('textentry').enter(number_done, c.num and tostring(c.num) or "", "NUMBER 0-127:", number_hint, {accept = number_accept})
  elseif row == "CLEAR" then
    mm.clear(m.ctl)
    m.msg = m.ctl:upper() .. " CLEARED"
  elseif row == "DEVICE" then
    local list = m.device_choices()
    local i = device_index(list, S.state.ctl[m.ctl]) % #list + 1
    S.set(m.ctl, "dev", list[i].value)
  end
end

local function key_raw(n, z)
  if z ~= 1 then return end
  if learning() then
    if n == 2 then mm.cancel()
    elseif n == 3 and mm.learn.state == "confirm" then mm.finish_confirm() end
    return
  end
  m.msg = nil
  mm.learn.msg, mm.learn.warn, mm.learn.warn_short = nil, nil, nil
  if m.mode == "confirm" then
    if n == 3 then
      local c = m.confirm
      if c.kind == "overwrite" then
        local ok, why = S.save_preset(c.typed, true)
        m.msg = ok and ("saved: " .. S.state.preset) or why
      elseif c.kind == "delete" then
        local ok, why = S.delete_preset(c.name)
        m.msg = ok and ("deleted: " .. c.name) or why
      end
    end
    m.mode, m.confirm = "rows", nil
    clamp_rows()
    return
  end
  if m.mode == "detail" then key_detail(n) clamp_detail() return end
  key_rows(n)
  clamp_rows()
end

local function enc_detail(n, delta)
  local id = m.ctl
  local c = S.state.ctl[id]
  if n == 2 then
    m.dpos = m.dpos + delta
    clamp_detail()
    return
  end
  if n ~= 3 or delta == 0 then return end
  local row = m.drows()[m.dpos]
  if row == "NUMBER" then
    S.set(id, "num", math.max(0, math.min(127, (c.num or -1) + delta)))
  elseif row == "TYPE" then
    local t = step_in(is_enc(id) and {"none", "cc"} or TYPES, c.type, delta)
    if t ~= c.type then S.set(id, "type", t) end
  elseif row == "DEVICE" then
    local list = m.device_choices()
    local i = math.max(1, math.min(#list, device_index(list, c) + delta))
    S.set(id, "dev", list[i].value)
  elseif row == "CHANNEL" then
    S.set(id, "ch", math.max(0, math.min(16, c.ch + delta)))
  elseif row == "MODE" then
    local mode = step_in(S.MODES, c.mode, delta)
    if mode ~= c.mode then S.set(id, "mode", mode); mm.guess[id] = nil end
  elseif row == "SENS" then
    S.set(id, "sens", math.max(1, math.min(9, c.sens + delta)))
  elseif row == "THRESHOLD" then
    S.set(id, "threshold", math.max(0, math.min(126, c.threshold + delta)))
  end
end

local function enc_raw(n, delta)
  if learning() then return end
  m.msg = nil
  mm.learn.msg, mm.learn.warn, mm.learn.warn_short = nil, nil, nil
  if m.mode == "confirm" then return end
  if m.mode == "detail" then enc_detail(n, delta) return end
  if n == 2 then
    m.pos = m.pos + delta
    clamp_rows()
  elseif n == 3 and delta ~= 0 then
    local row = m.rows()[m.pos]
    if row == "PRESET" then
      local list = S.preset_list()
      local idx = 0
      for i, p in ipairs(list) do if p.name == (m.browse or S.state.preset) then idx = i end end
      idx = math.max(1, math.min(#list, idx + delta))
      m.browse = list[idx].name
    elseif row == "ON CLASH" then
      S.set_clash(delta > 0 and "both" or "params")
    end
  end
end

-- ---------------------------------------------------------------- drawing
local function scrollbar(first, total)
  if total <= VISIBLE then return end
  local h = math.max(4, math.floor(36 * VISIBLE / total))
  local y = 12 + math.floor((36 - h) * (first - 1) / math.max(1, total - VISIBLE))
  screen.level(6)
  screen.rect(126, y, 2, h)
  screen.fill()
end

local function banner()
  local L = mm.learn
  if L.state == "idle" then return end
  screen.level(15)
  screen.rect(70, 1, 58, 9)
  screen.fill()
  screen.level(0)
  screen.move(99, 8)
  screen.text_center(L.state == "pick" and "CLICK ONE" or ("LEARN " .. L.target:upper()))
end

local function hint(default)
  local L = mm.learn
  local text, level = default, 2
  if L.state ~= "idle" then
    text, level = L.msg or "K2 CANCEL", 15
    local left = mm.seconds_left()
    if left > 0 then
      screen.level(3)
      screen.move(126, 64)
      screen.text_right(tostring(left))
    end
  elseif m.msg then text, level = m.msg, 15
  elseif L.warn_short then text, level = L.warn_short, 15
  elseif L.msg then text, level = L.msg, 15 end
  screen.level(level)
  screen.move(0, 64)
  screen.text(text)
end

local function draw_row(i, y, label, value, selected, target)
  if target then
    screen.level(15)
    screen.rect(0, y - 7, 128, 9)
    screen.fill()
    screen.level(0)
  else
    screen.level(selected and 15 or 4)
  end
  screen.move(2, y)
  screen.text(label)
  screen.move(124, y)
  screen.text_right(fit(value, 124 - screen.text_extents(label) - 8))
end

local function redraw_raw()
  screen.clear()
  screen.aa(0)
  screen.font_face(1)
  screen.font_size(8)
  if m.mode == "confirm" then
    screen.level(15)
    screen.move(0, 26)
    screen.text(fit(m.confirm.text, 125))
    screen.level(4)
    screen.move(0, 62)
    screen.text("K3 yes  K2 no")
    screen.update()
    return
  end
  local L = mm.learn
  screen.level(15)
  screen.move(0, 8)
  if m.mode == "detail" then
    clamp_detail()
    screen.text(m.ctl:upper() .. " MIDI")
    banner()
    local rows = m.drows()
    for i = 1, VISIBLE do
      local row = rows[m.dtop + i - 1]
      if row then
        local target = L.state ~= "idle" and row == "LEARN" and L.target == m.ctl
        local value = target and (L.state == "confirm" and "TURN IT" or (is_enc(m.ctl) and "MOVE A KNOB" or "PRESS A BUTTON")) or detail_text(row)
        draw_row(i, 10 + 9 * i, row, value, m.dtop + i - 1 == m.dpos, target)
      end
    end
    scrollbar(m.dtop, #rows)
    hint("E2 row  E3 change  K3")
  else
    clamp_rows()
    screen.text("MIDI MAP")
    banner()
    local rows = m.rows()
    local clash = clash_map()
    for i = 1, VISIBLE do
      local row = rows[m.top + i - 1]
      if row then
        local target = L.state ~= "idle" and L.target ~= nil and row == L.target:upper()
        local value
        if target then value = L.state == "confirm" and ctl_text(L.target, clash) or (is_enc(L.target) and "MOVE A KNOB" or "PRESS A BUTTON")
        else value = row_text(row, clash) end
        draw_row(i, 10 + 9 * i, row, value, m.top + i - 1 == m.pos, target and L.state ~= "confirm")
      end
    end
    scrollbar(m.top, #rows)
    local p = S.preset_by_name(m.browse or S.state.preset)
    if rows[m.pos] == "PRESET" and p and p.unverified then hint("UNVERIFIED: USE LEARN")
    else hint("E2 row  E3 change  K3") end
  end
  screen.update()
end

-- the handlers the menu calls. every key press and every encoder turn ends with a redraw (a state change that is not drawn looks like a page that does not react), and an error in a handler
-- is logged and leaves the page in a whole state (rows mode, its own handlers)
local function recover(what, err)
  dbg(what .. " raised an error: " .. tostring(err))
  m.mode, m.confirm = "rows", nil
  pcall(clamp_rows)
  reclaim()
end

m.key = function(n, z)
  local ok, err = pcall(key_raw, n, z)
  if not ok then recover("key " .. tostring(n) .. " " .. tostring(z), err) end
  if (z == 1 or not ok) and norns.menu.status() then _menu.redraw() end
end

m.enc = function(n, delta)
  local ok, err = pcall(enc_raw, n, delta)
  if not ok then recover("enc " .. tostring(n) .. " " .. tostring(delta), err) end
  if norns.menu.status() then _menu.redraw() end
end

m.redraw = function()
  local ok, err = pcall(redraw_raw)
  if not ok then
    dbg("redraw raised an error: " .. tostring(err))
    m.mode, m.confirm = "rows", nil
  end
end

return m
