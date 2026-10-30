-- SYSTEM > UI (computers only, see core/menu/system.lua): the look of the screen. BRIGHTNESS, COLOUR, CONTRAST and the custom colour HEX.
-- the values live in core/ui_settings.lua (file: ui.conf in the norns home); every change is applied and saved at once.
-- docs/port/ui-settings-plan.md. E2 row, E3 value, K3 on HEX opens the text entry that also names a pset (lib/textentry), K2 back.

local ui = require 'core/ui_settings'

local ROWS = {"BRIGHTNESS", "COLOUR", "CONTRAST", "HEX"}

local m = {pos = 1, msg = nil}

local function value_text(row)
  local st = ui.state
  if row == 1 then return ui.format_brightness(st.brightness)
  elseif row == 2 then return st.colour:upper()
  elseif row == 3 then return ui.format_contrast(st.contrast)
  elseif st.custom then return "#" .. st.custom
  else return "#------" end
end

m.init = function()
  ui.load()
  m.msg = nil
end

m.deinit = norns.none

local function key_raw(n, z)
  if z ~= 1 then return end
  if n == 2 then
    _menu.set_page("SYSTEM")
  elseif n == 3 and ROWS[m.pos] == "HEX" then
    local textentry = require 'textentry'
    m.msg = nil
    textentry.enter(m.hex_done, ui.state.custom and ("#" .. ui.state.custom) or "", "HEX (3 or 6 digits):", ui.hex_hint, {accept = ui.hex_accept, replace = true})
  end
end

-- the text entry is done: text is nil on cancel
m.hex_done = function(text)
  -- after the text entry the page must have its keys again (see core/menu/box.lua)
  if norns.menu.status() and norns.menu.get_key() ~= m.key then norns.menu.set(m.enc, m.key, m.redraw, m.refresh) end
  if text ~= nil then
    local ok, why = ui.set_custom(text)
    m.msg = (not ok) and ("bad hex: " .. why) or nil
  end
  _menu.redraw()
end

local function enc_raw(n, delta)
  m.msg = nil
  if n == 2 then
    m.pos = util.clamp(m.pos + delta, 1, #ROWS)
  elseif n == 3 then
    -- delta steps, like every other page (AUDIO: sel + delta): a release of the - and = keys arrives as 0 and changes nothing, a repeat as 2 is two steps
    local row = ROWS[m.pos]
    if row == "BRIGHTNESS" then ui.step_brightness(delta)
    elseif row == "COLOUR" then ui.step_colour(delta)
    elseif row == "CONTRAST" then ui.step_contrast(delta) end
  end
end

local function redraw_raw()
  screen.clear()
  for i, row in ipairs(ROWS) do
    screen.level(i == m.pos and 15 or 4)
    screen.move(0, 10 * i)
    screen.text(row)
    screen.move(127, 10 * i)
    screen.text_right(value_text(i))
  end
  -- the 16 levels as they look now
  for lv = 0, 15 do
    screen.level(lv)
    screen.rect(lv * 8, 45, 7, 5)
    screen.fill()
  end
  screen.level(m.msg and 15 or 2)
  screen.move(0, 62)
  screen.text(m.msg or "E2 row  E3 change  CONTRAST: more = lighter")
  screen.update()
end

-- the handlers the menu calls: every key press and encoder turn ends with a redraw, and an error in a handler is logged (one line in logs/norns.log) and leaves the page with its own handlers
local function dbg(s) print("SCREEN page: " .. s) end
local function recover(what, err)
  dbg(what .. " raised an error: " .. tostring(err))
  m.pos = util.clamp(m.pos, 1, #ROWS)
  if norns.menu.status() and norns.menu.get_key() ~= m.key then norns.menu.set(m.enc, m.key, m.redraw, m.refresh) end
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
  if not ok then dbg("redraw raised an error: " .. tostring(err)) end
end

return m
