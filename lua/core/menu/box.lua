-- SYSTEM > BOX (computers only, see core/menu/system.lua): the look of the box. docs/port/box-style-plan.md 2.6, 2.7. the values live in core/box_settings.lua (file: box.conf in the norns
-- home, and one small file per saved look in box-presets/); every change is applied and saved at once.
--   rows: STYLE, PRESET, BOX, KEYS, ENCODERS, BUTTONS, FONT, SAVE, and DELETE only while one of his own looks is in use
--   E2 row, E3 value (STYLE: aluminium or pixel; PRESET: the next or previous look), K3: PRESET opens the list, a colour opens the text entry (the same as UI's HEX row), SAVE asks for a name,
--   DELETE asks once. K2 goes back (out of the list or the question, else to SYSTEM)

local box = require 'core/box_settings'

local m = {pos = 1, top = 1, msg = nil, mode = "rows", lpos = 1, confirm = nil}

local VISIBLE = 6
local PARTS = {BOX = "box", KEYS = "keys", ENCODERS = "encoders", BUTTONS = "buttons", FONT = "font"}

local function in_use_look()
  local l = box.look_by_name(box.state.preset)
  if l ~= nil and box.state.preset ~= "CUSTOM" then return l end
  return nil
end

--- the rows of the page, in order (DELETE only for one of his own looks)
function m.rows()
  local r = {"STYLE", "PRESET", "BOX", "KEYS", "ENCODERS", "BUTTONS", "FONT", "SAVE"}
  local l = in_use_look()
  if l ~= nil and not l.builtin then r[#r + 1] = "DELETE" end
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

local function preset_text()
  local l = in_use_look()
  local text = box.label()
  if l ~= nil and not l.builtin then return "* " .. text end
  return text
end

local function value_text(row)
  local st = box.state
  if row == "STYLE" then return st.style:upper()
  elseif row == "PRESET" then return preset_text()
  elseif row == "SAVE" then return "name..."
  elseif row == "DELETE" then local l = in_use_look() return l and ("* " .. l.name) or ""
  else return "#" .. st.colours[PARTS[row]] end
end

local function clamp_rows()
  local n = #m.rows()
  m.pos = util.clamp(m.pos, 1, n)
  if m.pos < m.top then m.top = m.pos end
  if m.pos > m.top + VISIBLE - 1 then m.top = m.pos - VISIBLE + 1 end
  m.top = util.clamp(m.top, 1, math.max(1, n - VISIBLE + 1))
end

m.init = function()
  box.load()
  m.pos, m.top, m.msg, m.mode, m.confirm = 1, 1, nil, "rows", nil
end

m.deinit = norns.none

-- ---- the list of looks (K3 on PRESET) ----
local function list_items()
  local items = {}
  local own = false
  for _, l in ipairs(box.look_list()) do
    if not l.builtin and not own then
      own = true
      items[#items + 1] = {sep = true}
    end
    items[#items + 1] = {look = l}
  end
  return items
end

local function open_list()
  m.mode = "list"
  local items = list_items()
  m.lpos = 1
  for i, it in ipairs(items) do
    if it.look and it.look.name == box.state.preset then m.lpos = i end
  end
  m.ltop = 1
end

local function list_move(d)
  local items = list_items()
  local i = m.lpos
  repeat
    i = i + (d > 0 and 1 or -1)
  until i < 1 or i > #items or not items[i].sep
  if i >= 1 and i <= #items then m.lpos = i end
end

-- ---- text entries ----
-- after the text entry the page must have its keys again. the entry gives back what it found; if the menu was changed while it was open it may not (docs/port/box-style-plan.md), so check
local function reclaim()
  if norns.menu.status() and norns.menu.get_key() ~= m.key then
    norns.menu.set(m.enc, m.key, m.redraw, m.refresh)
  end
end

local function hex_done(row)
  return function(text)
    reclaim()
    if text ~= nil then
      local ok, why = box.set_part(PARTS[row], text)
      if not ok then m.msg = "bad hex: " .. why
      else m.msg = why end
    end
    _menu.redraw()
  end
end

local function name_done(text)
  reclaim()
  if text ~= nil then
    local ok, why, existing = box.save_look(text)
    if ok then
      m.msg = "saved: " .. box.state.preset
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

-- the entry for a name takes only what a name may hold, up to 18 characters
local function name_accept(text)
  if #text > box.MAX_NAME then return false, box.MAX_NAME .. " characters max" end
  if text:find("[^%w _%.%-]") then return false, "letters, digits, - _ . only" end
  return true
end

local function name_hint(text)
  local t = tostring(text or "")
  if t:match("^%s*$") then return "" end
  local v, why = box.validate_name(t)
  return v and "" or why
end

m.key = function(n, z)
  if z ~= 1 then return end
  if m.mode == "list" then
    if n == 2 then
      m.mode = "rows"
    elseif n == 3 then
      local it = list_items()[m.lpos]
      if it and it.look then
        box.select_look(it.look.name)
        m.msg = nil
      end
      m.mode = "rows"
      clamp_rows()
    end
    return
  elseif m.mode == "confirm" then
    if n == 3 then
      local c = m.confirm
      if c.kind == "overwrite" then
        local ok, why = box.save_look(c.typed, true)
        m.msg = ok and ("saved: " .. box.state.preset) or why
      elseif c.kind == "delete" then
        local ok, why = box.delete_look(c.name)
        m.msg = ok and ("deleted: " .. c.name) or why
      end
    end
    m.mode, m.confirm = "rows", nil
    clamp_rows()
    return
  end
  if n == 2 then
    _menu.set_page("SYSTEM")
    return
  end
  if n ~= 3 then return end
  local row = m.rows()[m.pos]
  m.msg = nil
  local textentry = require 'textentry'
  if row == "STYLE" then
    box.set_style(box.state.style == "pixel" and "aluminium" or "pixel")
  elseif row == "PRESET" then
    open_list()
  elseif PARTS[row] then
    textentry.enter(hex_done(row), "#" .. box.state.colours[PARTS[row]], "HEX (3 or 6 digits):", box.hex_hint, {accept = box.hex_accept, replace = true})
  elseif row == "SAVE" then
    textentry.enter(name_done, "", "NAME FOR THIS LOOK:", name_hint, {accept = name_accept})
  elseif row == "DELETE" then
    local l = in_use_look()
    if l and not l.builtin then
      m.mode = "confirm"
      m.confirm = {kind = "delete", name = l.name, text = "DELETE " .. l.name .. "?"}
    end
  end
end

m.enc = function(n, delta)
  m.msg = nil
  if m.mode == "list" then
    if n == 2 then list_move(delta) end
    return
  elseif m.mode == "confirm" then
    return
  end
  if n == 2 then
    m.pos = m.pos + delta
    clamp_rows()
  elseif n == 3 then
    local row = m.rows()[m.pos]
    if row == "STYLE" then
      if delta > 0 then box.set_style("pixel") elseif delta < 0 then box.set_style("aluminium") end
    elseif row == "PRESET" then
      box.step_preset(delta)
    end
    clamp_rows()
  end
  _menu.redraw()
end

-- ---- drawing ----
local function scrollbar(first, total)
  if total <= VISIBLE then return end
  local h = math.max(4, math.floor(54 * VISIBLE / total))
  local y = 8 + math.floor((54 - h) * (first - 1) / math.max(1, total - VISIBLE))
  screen.level(6)
  screen.rect(126, y, 2, h)
  screen.fill()
end

local function hint(text)
  screen.level(m.msg and 15 or 2)
  screen.move(0, 62)
  screen.text(m.msg or text)
end

local function redraw_list()
  local items = list_items()
  if m.lpos < m.ltop then m.ltop = m.lpos end
  if m.lpos > m.ltop + VISIBLE - 1 then m.ltop = m.lpos - VISIBLE + 1 end
  for i = 0, VISIBLE - 1 do
    local it = items[m.ltop + i]
    if it then
      local y = 8 + 9 * i
      screen.move(0, y)
      if it.sep then
        screen.level(2)
        screen.text("- MY PRESETS -")
      else
        local l = it.look
        local used = l.name == box.state.preset
        local text = (l.builtin and "" or "* ") .. l.name
        local room = 125 - (used and (screen.text_extents("in use") + 4) or 0)
        screen.level(m.ltop + i == m.lpos and 15 or 4)
        screen.text(fit(text, room))
        if used then
          screen.move(124, y)
          screen.text_right("in use")
        end
      end
    end
  end
  scrollbar(m.ltop, #items)
  hint("E2 pick K3 use *=yours")
end

m.redraw = function()
  screen.clear()
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
  if m.mode == "list" then
    redraw_list()
    screen.update()
    return
  end
  clamp_rows()
  local rows = m.rows()
  for i = 0, VISIBLE - 1 do
    local row = rows[m.top + i]
    if row then
      local y = 8 + 9 * i
      screen.level(m.top + i == m.pos and 15 or 4)
      screen.move(0, y)
      screen.text(row)
      screen.move(124, y)
      screen.text_right(value_text(row))
    end
  end
  scrollbar(m.top, #rows)
  hint("E2 row  E3 change  K3 more")
  screen.update()
end

return m
