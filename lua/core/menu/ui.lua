-- SYSTEM > SCREEN (computers only, see core/menu/system.lua): the look of the screen, laid out like SYSTEM > THEME (core/menu/box.lua). the values live in core/ui_settings.lua (file: ui.conf in the
-- norns home, and one small file per saved colour in screen-presets/); every change is applied and saved at once. docs/port/ui-settings-plan.md.
--   rows: PRESET, COLOUR, BRIGHTNESS, CONTRAST, SAVE, and DELETE only while one of his own presets is in use
--   a preset is the colour of the screen only: BRIGHTNESS and CONTRAST are separate rows and keep their values when a preset is chosen
--   E2 row, E3 value (PRESET: the next or previous preset), K3: PRESET opens the list, COLOUR opens the colour picker (the same as THEME's colour rows), SAVE asks for a name, DELETE asks once.
--   K2 goes back (out of the list or the question, else to SYSTEM)

local ui = require 'core/ui_settings'
local keyboard = require 'core/keyboard'
local clipboard = require 'core/clipboard'

local m = {pos = 1, top = 1, msg = nil, mode = "rows", lpos = 1, confirm = nil}

local VISIBLE = 5 -- the strip of the 16 grey levels is below them

local function in_use_preset()
  local p = ui.preset_by_name(ui.state.preset)
  if p ~= nil and ui.state.preset ~= "CUSTOM" then return p end
  return nil
end

--- the rows of the page, in order (DELETE only for one of his own presets)
function m.rows()
  local r = {"PRESET", "COLOUR", "BRIGHTNESS", "CONTRAST", "SAVE"}
  local p = in_use_preset()
  if p ~= nil and not p.builtin then r[#r + 1] = "DELETE" end
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
  local p = in_use_preset()
  local text = ui.label()
  if p ~= nil and not p.builtin then return "* " .. text end
  return text
end

local function value_text(row)
  local st = ui.state
  if row == "PRESET" then return preset_text()
  elseif row == "COLOUR" then return "#" .. st.tint
  elseif row == "BRIGHTNESS" then return ui.format_brightness(st.brightness)
  elseif row == "CONTRAST" then return ui.format_contrast(st.contrast)
  elseif row == "SAVE" then return "name..."
  else local p = in_use_preset() return p and ("* " .. p.name) or "" end
end

-- one line in logs/norns.log when a handler raises an error or a selection had to be clamped (a selection that was not in range is a state that should not happen)
local function dbg(s) print("SCREEN page: " .. s) end

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
  ui.load()
  ui.reload_presets()
  if require('core/menu/picker').take_returning() then
    -- back from the colour picker: the row, the scroll and the message are as they were
    m.mode, m.confirm = "rows", nil
    clamp_rows()
    return
  end
  m.pos, m.top, m.msg, m.mode, m.confirm = 1, 1, nil, "rows", nil
end

m.deinit = norns.none

-- ---- the list of presets (K3 on PRESET) ----
local function list_items()
  local items = {}
  local own = false
  for _, p in ipairs(ui.preset_list()) do
    if not p.builtin and not own then
      own = true
      items[#items + 1] = {sep = true}
    end
    items[#items + 1] = {preset = p}
  end
  return items
end

-- the list's position must be on a preset (not past the end, not on the separator), also when the presets changed under it
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
    if it.preset and it.preset.name == ui.state.preset then m.lpos = i end
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
-- after the text entry the page must have its keys again (see core/menu/box.lua)
local function reclaim()
  if norns.menu.status() and norns.menu.get_key() ~= m.key then
    norns.menu.set(m.enc, m.key, m.redraw, m.refresh)
  end
end

local function name_done(text)
  reclaim()
  if text ~= nil then
    local ok, why, existing = ui.save_preset(text)
    if ok then
      m.msg = "saved: " .. ui.state.preset
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

-- K3 on COLOUR: the colour picker, live on the screen until K3 (keep and save) or K2 (give the old colour back)
function m.open_picker()
  require('core/menu/picker').open({
    label = "SCREEN COLOUR",
    value = ui.state.tint,
    preview = function(hex) ui.preview_custom(hex) end,
    restore = function() ui.apply() end,
    ok = function(hex)
      local ok, why = ui.set_custom(hex)
      m.msg = (not ok) and ("bad hex: " .. tostring(why)) or ("saved #" .. hex)
    end,
    note = function(text) m.msg = text end,
    return_page = "UI",
  })
end

-- the entry for a name takes only what a name may hold, up to 18 characters
local function name_accept(text)
  if #text > ui.MAX_NAME then return false, ui.MAX_NAME .. " characters max" end
  if text:find("[^%w _%.%-]") then return false, "letters, digits, - _ . only" end
  return true
end

local function name_hint(text)
  local t = tostring(text or "")
  if t:match("^%s*$") then return "" end
  local v, why = ui.validate_name(t)
  return v and "" or why
end

local function key_raw(n, z)
  if z ~= 1 then return end
  if m.mode == "list" then
    if n == 2 then
      m.mode = "rows"
    elseif n == 3 then
      local it = list_items()[m.lpos]
      if it and it.preset then
        ui.select_preset(it.preset.name)
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
        local ok, why = ui.save_preset(c.typed, true)
        m.msg = ok and ("saved: " .. ui.state.preset) or why
      elseif c.kind == "delete" then
        local ok, why = ui.delete_preset(c.name)
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
  if row == "PRESET" then
    open_list()
  elseif row == "COLOUR" then
    m.open_picker()
  elseif row == "SAVE" then
    require('textentry').enter(name_done, "", "NAME FOR THIS COLOUR:", name_hint, {accept = name_accept})
  elseif row == "DELETE" then
    local p = in_use_preset()
    if p and not p.builtin then
      m.mode = "confirm"
      m.confirm = {kind = "delete", name = p.name, text = "DELETE " .. p.name .. "?"}
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
    -- delta steps, like every other page: a release of the - and = keys arrives as 0 and changes nothing, a repeat as 2 is two steps
    local row = m.rows()[m.pos]
    if row == "PRESET" then ui.step_preset(delta)
    elseif row == "BRIGHTNESS" then ui.step_brightness(delta)
    elseif row == "CONTRAST" then ui.step_contrast(delta) end
    clamp_rows()
  end
end

-- ---- drawing ----
local function scrollbar(first, total)
  if total <= VISIBLE then return end
  local h = math.max(4, math.floor(40 * VISIBLE / total))
  local y = 8 + math.floor((40 - h) * (first - 1) / math.max(1, total - VISIBLE))
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
  if m.lpos > m.ltop + 5 then m.ltop = m.lpos - 5 end
  for i = 0, 5 do
    local it = items[m.ltop + i]
    if it then
      local y = 8 + 9 * i
      screen.move(0, y)
      if it.sep then
        screen.level(2)
        screen.text("- MY PRESETS -")
      else
        local p = it.preset
        local used = p.name == ui.state.preset
        local text = (p.builtin and "" or "* ") .. p.name
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
  if #items > 6 then
    local h = math.max(4, math.floor(54 * 6 / #items))
    local y = 8 + math.floor((54 - h) * (m.ltop - 1) / math.max(1, #items - 6))
    screen.level(6)
    screen.rect(126, y, 2, h)
    screen.fill()
  end
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
      screen.text_right(value_text(row))
    end
  end
  scrollbar(m.top, #rows)
  -- the 16 levels as they look now
  for lv = 0, 15 do
    screen.level(lv)
    screen.rect(lv * 8, 50, 7, 5)
    screen.fill()
  end
  hint("E2 row  E3 change  K3 more")
  screen.update()
end

-- the handlers the menu calls. every key press and every encoder turn ends with a redraw, and an error in a handler is logged (one line in logs/norns.log) and leaves the page in a whole state
local function recover(what, err)
  dbg(what .. " raised an error: " .. tostring(err))
  m.mode, m.confirm = "rows", nil
  pcall(clamp_rows)
  reclaim()
end

-- Ctrl+C copies the code of the COLOUR row, Ctrl+V pastes one (3 or 6 digits, with or without #) and keeps it at once; everything else is the menu's
local function keycode_raw(c, value)
  if not (keyboard.ctrl() and (c == "C" or c == "V")) or m.mode ~= "rows" or m.rows()[m.pos] ~= "COLOUR" then return false end
  if value ~= 1 then return true end
  if c == "C" then
    local text = "#" .. ui.state.tint
    m.msg = clipboard.copy(text) and ("copied " .. text) or "no clipboard"
  else
    m.msg = "pasting.."
    clipboard.paste_colour(function(hex, why)
      if _menu.page ~= "UI" or m.mode ~= "rows" then return end -- the answer came after the page was left (the picker is open, or another page): it is not for this page
      if hex then
        local ok, w = ui.set_custom(hex)
        m.msg = ok and ("pasted #" .. hex) or ("bad hex: " .. tostring(w))
      else
        m.msg = why
      end
      if _menu.page == "UI" and norns.menu.status() then _menu.redraw() end
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
