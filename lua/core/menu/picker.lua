-- the colour picker (computers only, core/menu.lua registers it as the page PICKER): a page of the norns screen's param menu with the rows HUE, SATURATION, BRIGHTNESS and HEX, opened by K3 on a
-- hex row of THEME (BOX KEYS ENCODERS BUTTONS FONT) and SCREEN (HEX). docs/port/colour-picker-plan.md. every row is a param like any other: E2 (or UP / DOWN) chooses the row, E3 (or LEFT / RIGHT,
-- the value keys - and =) changes it by a step (5 degrees, 5 percent; Shift 5 steps; Ctrl a fine unit; a release changes nothing), and every change is applied to what is being edited at once
-- (opts.preview) without writing a file. K3 keeps (opts.ok writes once), K2 / Esc / F1 give the old colour back (opts.restore). K3 on HEX opens the text entry; C centres, H opens the text entry, R goes back
-- to the colour the picker opened with, Ctrl+C copies the code to the clipboard and Ctrl+V pastes one. every handler ends with a redraw, and an error in one is logged and leaves the page whole
local colour = require 'core/colour'
local clipboard = require 'core/clipboard'
local keyboard = require 'core/keyboard'

local m = {row = 1, val = colour.from_hex(nil), opts = nil, pending = nil, orig = nil, last_hex = nil, msg = nil, active = false, returning = false}

local ROWS = {"HUE", "SATURATION", "BRIGHTNESS", "HEX"}
local STRIP = {"h", "s", "v"}
local function dbg(s) print("PICKER page: " .. s) end

local function current_hex() return colour.value_hex(m.val) end

--- open the picker. opts: label (the heading), value (the code the thing has now, or nil), preview(hex), restore(), ok(hex), return_page
function m.open(opts)
  m.pending = opts
  _menu.set_page("PICKER")
end

m.init = function()
  local o = m.pending
  if o == nil then return end
  m.pending = nil
  m.opts = o
  local valid
  m.val, valid = colour.from_hex(o.value)
  m.orig = valid and colour.hex(o.value) or nil
  m.last_hex = m.orig
  m.row = 1
  m.msg = nil
  m.active = true
end

-- the page that opened the picker gets its row and scroll back: its init asks
function m.take_returning()
  local r = m.returning
  m.returning = false
  return r
end

local function apply_live()
  local hex = current_hex()
  if hex ~= m.last_hex then
    m.last_hex = hex
    if m.opts and m.opts.preview then m.opts.preview(hex) end
  end
end

local function finish(ok)
  local o = m.opts
  if not m.active or o == nil then return end
  m.active = false
  local hex = current_hex()
  if ok and m.last_hex ~= nil and hex ~= m.orig then
    o.ok(hex) -- the one write
  elseif o.restore then
    o.restore() -- nothing to keep: what is stored is shown
  end
  m.returning = true
  _menu.set_page(o.return_page)
end

-- left by anything else (F1-F4, another page): the old colour comes back
m.deinit = function()
  if m.active then
    m.active = false
    if m.opts and m.opts.restore then m.opts.restore() end
  end
end

local function step(amount)
  if amount == 0 or ROWS[m.row] == "HEX" then return end
  colour.move(m.val, STRIP[m.row], amount)
  apply_live()
end

local function set_row(r) m.row = math.max(1, math.min(#ROWS, r)) end

local function open_entry()
  local box = require 'core/box_settings'
  local textentry = require 'textentry'
  textentry.enter(m.entry_done, "#" .. current_hex(), "HEX (3 or 6 digits):", box.hex_hint, {accept = box.hex_accept, replace = true, clip = "colour"})
end

m.entry_done = function(text)
  if norns.menu.status() and norns.menu.get_key() ~= m.key then norns.menu.set(m.enc, m.key, m.redraw, m.refresh) end
  if text ~= nil then
    local hex = colour.hex(text)
    if hex then
      m.val = colour.from_hex(hex)
      apply_live()
    else
      m.msg = "bad hex"
    end
  end
  _menu.redraw()
end

local function copy()
  local hex = "#" .. current_hex()
  m.msg = clipboard.copy(hex) and ("copied " .. hex) or "no clipboard"
end

local function paste()
  m.msg = "pasting.."
  clipboard.paste_colour(function(hex, why)
    if not m.active or _menu.page ~= "PICKER" then return end
    if hex then
      m.val = colour.from_hex(hex)
      apply_live()
      m.msg = "pasted #" .. hex
    else
      m.msg = why
    end
    if norns.menu.status() then _menu.redraw() end
  end)
end

local function reset()
  if m.orig then m.val = colour.from_hex(m.orig) else m.val = colour.centre(colour.from_hex(nil)) end
  m.last_hex = m.orig
  if m.opts and m.opts.restore then m.opts.restore() end
  m.msg = "reset"
end

local function centre()
  colour.centre(m.val)
  apply_live()
  m.msg = "centre"
end

local function key_raw(n, z)
  if z ~= 1 then return end
  m.msg = nil
  if n == 2 then finish(false)
  elseif n == 3 then
    if ROWS[m.row] == "HEX" then open_entry() else finish(true) end
  end
end

local function enc_raw(n, delta)
  m.msg = nil
  if n == 2 then set_row(m.row + delta)
  elseif n == 3 then step(colour.amount(delta)) end
end

-- the keyboard: returns true when the key was the picker's (the menu's own bindings are not used for it), false to let the menu have it
local KNOWN = {UP = true, DOWN = true, LEFT = true, RIGHT = true, MINUS = true, EQUAL = true, PAGEUP = true, PAGEDOWN = true, HOME = true, ["END"] = true}
local function keycode_raw(c, value)
  local ctrl, shift = keyboard.ctrl(), keyboard.shift()
  if ctrl and (c == "C" or c == "V") then
    if value == 1 then
      m.msg = nil
      if c == "C" then copy() else paste() end
    end
    return true
  end
  if not KNOWN[c] then return false end
  if value == 0 then return true end -- a release changes nothing
  m.msg = nil
  if c == "UP" then set_row(m.row - 1)
  elseif c == "DOWN" then set_row(m.row + 1)
  elseif c == "LEFT" then step(colour.amount(-1, shift, ctrl))
  elseif c == "RIGHT" then step(colour.amount(1, shift, ctrl))
  elseif c == "MINUS" then step(colour.amount(-value, shift, ctrl)) -- a repeat (2) is two steps, as on the other pages
  elseif c == "EQUAL" then step(colour.amount(value, shift, ctrl))
  elseif c == "PAGEUP" then step(colour.amount(1, true, ctrl))
  elseif c == "PAGEDOWN" then step(colour.amount(-1, true, ctrl))
  elseif c == "HOME" or c == "END" then
    if ROWS[m.row] ~= "HEX" then
      local to = c == "HOME" and 0 or (m.row == 1 and colour.HUE_MAX or colour.PCT_MAX)
      colour.move(m.val, STRIP[m.row], to - m.val[STRIP[m.row]])
      apply_live()
    end
  end
  return true
end

local function keychar_raw(a)
  if keyboard.ctrl() then return end -- Ctrl+C and Ctrl+V are handled as keys
  a = tostring(a):lower()
  m.msg = nil
  if a == "c" then centre()
  elseif a == "h" then open_entry()
  elseif a == "r" then reset() end
end

-- ---------------------------------------------------------------- drawing
local function redraw_raw()
  screen.clear()
  local o = m.opts or {}
  screen.level(4)
  screen.move(0, 8)
  screen.text(o.label or "COLOUR")
  if m.orig == nil and m.last_hex == nil then
    screen.move(127, 8)
    screen.text_right("not set")
  end
  for i = 1, 3 do
    local y = 19 + (i - 1) * 9
    screen.level(i == m.row and 15 or 4)
    screen.move(0, y)
    screen.text(ROWS[i])
    local key = STRIP[i]
    local t = m.val[key] / (i == 1 and colour.HUE_MAX or colour.PCT_MAX)
    screen.level(2)
    screen.rect(66, y - 6, 40, 5)
    screen.stroke()
    screen.level(i == m.row and 15 or 6)
    screen.rect(66 + math.floor(t * 37 + 0.5), y - 8, 3, 9)
    screen.fill()
    screen.level(i == m.row and 15 or 4)
    screen.move(127, y)
    screen.text_right(tostring(math.floor(m.val[key] + 0.5)))
  end
  screen.level(m.row == 4 and 15 or 4)
  screen.move(0, 46)
  screen.text("HEX")
  screen.move(127, 46)
  screen.text_right("#" .. current_hex())
  screen.level(m.msg and 15 or 2)
  screen.move(0, 55)
  screen.text(m.msg or "C centre H hex R reset")
  screen.level(2)
  screen.move(0, 63)
  screen.text("E2 row E3 step K3 ok K2 x")
  screen.update()
end

-- ---------------------------------------------------------------- the handlers the menu calls: each ends with a redraw, an error is logged and leaves the page whole
local function recover(what, err)
  dbg(what .. " raised an error: " .. tostring(err))
  m.row = math.max(1, math.min(#ROWS, m.row))
  if norns.menu.status() and m.active and norns.menu.get_key() ~= m.key then norns.menu.set(m.enc, m.key, m.redraw, m.refresh) end
end

m.key = function(n, z)
  local ok, err = pcall(key_raw, n, z)
  if not ok then recover("key " .. tostring(n) .. " " .. tostring(z), err) end
  if (z == 1 or not ok) and m.active and norns.menu.status() then _menu.redraw() end
end

m.enc = function(n, delta)
  local ok, err = pcall(enc_raw, n, delta)
  if not ok then recover("enc " .. tostring(n) .. " " .. tostring(delta), err) end
  if m.active and norns.menu.status() then _menu.redraw() end
end

m.keycode = function(c, value)
  local ok, used = pcall(keycode_raw, c, value)
  if not ok then
    recover("keycode " .. tostring(c) .. " " .. tostring(value), used)
    used = true
  end
  if used and (value ~= 0 or c == "C" or c == "V") and m.active and norns.menu.status() then _menu.redraw() end
  return used
end

m.keychar = function(a)
  local ok, err = pcall(keychar_raw, a)
  if not ok then recover("char " .. tostring(a), err) end
  if m.active and norns.menu.status() then _menu.redraw() end
end

m.redraw = function()
  local ok, err = pcall(redraw_raw)
  if not ok then dbg("redraw raised an error: " .. tostring(err)) end
end

return m
