-- SYSTEM > BOX (computers only, see core/menu/system.lua): the look of the box. docs/port/box-style-plan.md 2.6, 2.7. the values live in core/box_settings.lua (file: box.conf in the norns
-- home, and one small file per saved look in box-presets/); every change is applied and saved at once.
--   rows: STYLE, PIXEL LOOK (PIXEL, RETRO, 8-BIT, 16-BIT: only while STYLE is pixel; docs/port/retro-look-plan.md), PRESET, BOX, KEYS, ENCODERS, BUTTONS, FONT, SAVE, and DELETE only while one of his own looks is in use
--   E2 row, E3 value (STYLE: aluminium or pixel; PRESET: the next or previous look), K3: PRESET opens the list, a colour opens the text entry (the same as UI's HEX row), SAVE asks for a name,
--   DELETE asks once. K2 goes back (out of the list or the question, else to SYSTEM)

local box = require 'core/box_settings'
local keyboard = require 'core/keyboard'
local clipboard = require 'core/clipboard'

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
  local r = {"STYLE", "PIXEL LOOK", "PRESET", "BOX", "KEYS", "ENCODERS", "BUTTONS", "FONT", "SAVE"}
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
  elseif row == "PIXEL LOOK" then return st.pixel_look:upper()
  elseif row == "PRESET" then return preset_text()
  elseif row == "SAVE" then return "name..."
  elseif row == "DELETE" then local l = in_use_look() return l and ("* " .. l.name) or ""
  else return "#" .. st.colours[PARTS[row]] end
end

-- one line in logs/norns.log when a handler raises an error or a selection had to be clamped (a selection that was not in range is a state that should not happen)
local function dbg(s) print("THEME page: " .. s) end

local function clamp_rows(quiet)
  local n = #m.rows()
  local was = m.pos
  m.pos = util.clamp(m.pos, 1, n)
  if m.pos ~= was and not quiet then dbg("selection " .. tostring(was) .. " clamped to " .. m.pos .. " (" .. n .. " rows)") end
  if m.pos < m.top then m.top = m.pos end
  if m.pos > m.top + VISIBLE - 1 then m.top = m.pos - VISIBLE + 1 end
  m.top = util.clamp(m.top, 1, math.max(1, n - VISIBLE + 1))
end

m.init = function()
  box.load()
  if require('core/menu/picker').take_returning() then
    -- back from the colour picker: the row, the scroll and the message are as they were
    m.mode, m.confirm = "rows", nil
    clamp_rows()
    return
  end
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

-- the list's position must be on a look (not past the end, not on the separator), also when the looks changed under it
local function clamp_list()
  local items = list_items()
  local was = m.lpos
  m.lpos = util.clamp(m.lpos, 1, #items)
  while items[m.lpos] and items[m.lpos].sep and m.lpos < #items do m.lpos = m.lpos + 1 end
  if items[m.lpos] and items[m.lpos].sep then m.lpos = m.lpos - 1 end
  if m.lpos ~= was then dbg("list position " .. tostring(was) .. " clamped to " .. m.lpos .. " (" .. #items .. " entries)") end
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

-- K3 on a colour row: the colour picker, live on the box until K3 (keep and save) or K2 (give the old colour back)
function m.open_picker(row)
  local part = PARTS[row]
  require('core/menu/picker').open({
    label = "THEME " .. row,
    value = box.state.colours[part],
    preview = function(hex) box.preview_part(part, hex) end,
    restore = function() box.apply() end,
    ok = function(hex)
      local ok, why = box.set_part(part, hex)
      m.msg = ok and why or ("bad hex: " .. tostring(why))
    end,
    return_page = "BOX",
  })
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

local function key_raw(n, z)
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
  elseif row == "PIXEL LOOK" then
    if box.state.style ~= "pixel" then
      m.msg = "needs STYLE PIXEL"
    else
      -- K3 steps to the next look and goes round from the last to the first
      local i = box.pixel_look_index(box.state.pixel_look) + 1
      box.set_pixel_look(box.PIXEL_LOOKS[i % #box.PIXEL_LOOKS + 1])
    end
  elseif row == "PRESET" then
    open_list()
  elseif PARTS[row] then
    m.open_picker(row)
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

local function enc_raw(n, delta)
  m.msg = nil
  if m.mode == "list" then
    clamp_list()
    if n == 2 then list_move(delta) end
    return
  elseif m.mode == "confirm" then
    return
  end
  if n == 2 then
    m.pos = m.pos + delta
    clamp_rows(true) -- scrolling past either end is not an error
  elseif n == 3 then
    local row = m.rows()[m.pos]
    if row == "STYLE" then
      if delta > 0 then box.set_style("pixel") elseif delta < 0 then box.set_style("aluminium") end
    elseif row == "PIXEL LOOK" then
      if delta ~= 0 then
        if box.state.style ~= "pixel" then m.msg = "needs STYLE PIXEL" else box.step_pixel_look(delta) end
      end
    elseif row == "PRESET" then
      box.step_preset(delta)
    end
    clamp_rows()
  end
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
  clamp_list()
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

local function redraw_raw()
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
      if row == "PIXEL LOOK" and box.state.style ~= "pixel" then screen.level(2) end -- not active: the style is aluminium
      screen.text_right(value_text(row))
    end
  end
  scrollbar(m.top, #rows)
  hint("E2 row  E3 change  K3 more")
  screen.update()
end

-- the handlers the menu calls. every key press and every encoder turn ends with a redraw (a state change that is not drawn looks like a page that does not react: K3 on PRESET opens the list,
-- but without a redraw the screen kept showing the rows and up / down moved an invisible list), and an error in a handler is logged and leaves the page in a whole state (rows mode, its own handlers)
local function recover(what, err)
  dbg(what .. " raised an error: " .. tostring(err))
  m.mode, m.confirm = "rows", nil
  pcall(clamp_rows)
  reclaim()
end

-- Ctrl+C copies the code of the colour row under the selection, Ctrl+V pastes one (3 or 6 digits, with or without #) and keeps it at once; everything else is the menu's
local function keycode_raw(c, value)
  if not (keyboard.ctrl() and (c == "C" or c == "V")) or m.mode ~= "rows" then return false end
  local row = m.rows()[m.pos]
  local part = row and PARTS[row]
  if part == nil then return false end
  if value ~= 1 then return true end
  if c == "C" then
    local text = "#" .. box.state.colours[part]
    m.msg = clipboard.copy(text) and ("copied " .. text) or "no clipboard"
  else
    m.msg = "pasting.."
    clipboard.paste_colour(function(hex, why)
      if _menu.page ~= "BOX" or m.mode ~= "rows" then return end -- the answer came after the page was left (the picker is open, or another page): it is not for this page
      if hex then
        local ok, w = box.set_part(part, hex)
        m.msg = ok and (w or ("pasted #" .. hex)) or ("bad hex: " .. tostring(w))
      else
        m.msg = why
      end
      if _menu.page == "BOX" and norns.menu.status() then _menu.redraw() end
    end)
  end
  return true
end

m.keycode = function(c, value)
  local ok, used = pcall(keycode_raw, c, value)
  if not ok then
    dbg("keycode " .. tostring(c) .. " raised an error: " .. tostring(used))
    used = false
  end
  if used and norns.menu.status() then _menu.redraw() end
  return used
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
