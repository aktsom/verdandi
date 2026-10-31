--- textentry UI
--
-- The [norns script reference](https://monome.org/docs/norns/reference/)
-- has [examples for this module](https://monome.org/docs/norns/reference/lib/textentry).
--
-- @module lib.textentry
-- @alias te

local te_kbd_cb = require 'lib/textentry_kbd'
local keyboard = require 'core/keyboard'

local te = {}

-- on a computer (NORNS_PLATFORM is set by the Linux launcher) the entry is tidier and can be limited (docs/port/box-style-plan.md): the hint of a check is on a line of its own instead of over the end of
-- the text, a text wider than the screen is cut at the left, an optional accept(text) refuses characters (a hex code: 6 digits at most) with a short hint, the first typed character can replace the
-- text that was shown, and a second enter while one is open is ignored (it used to save the entry's own handlers as the ones to restore, and the page never got its keys back).
-- on the device none of this exists: the entry is the one of upstream norns
local desktop = os.getenv("NORNS_PLATFORM") ~= nil
te.active = false
te.opening = false -- true while enter() sets the entry up (it calls the menu, which tells textentry that it changed)

-- computers: the arc window's keys (5 6 T Y G H B N, matron/src/platform/linux/arc_keys.h) are the entry's too while one is open: lua tells the window
local function arc_block(on)
  if desktop and _norns and _norns.arc_keys_block then _norns.arc_keys_block(on and 1 or 0) end
end

-- computers: an entry that is marked active but whose menu moved on (a page or a mode change that did not close it) would keep every key for itself, hide itself, and make every later entry refuse to open
-- ("one entry at a time"). what it takes to know: the menu mode and the page it was opened in, and (in a menu) that the menu's key handler is still the entry's
local function orphaned()
  if not te.active then return false end
  if te.opened_menu ~= norns.menu.status() then return true end
  if te.opened_menu then
    return _menu.page ~= te.opened_page or norns.menu.get_key() ~= te.key
  end
  return key ~= te.key
end

--- close an entry without calling its callback (its page is gone): hooks off, the script's handlers back if it was opened over a script
local function abandon()
  te.active = false
  te_kbd_cb.code = nil
  te_kbd_cb.char = nil
  if te.opened_menu == false and te.key_restore ~= nil then
    key = te.key_restore
    enc = te.enc_restore
    redraw = te.redraw_restore
    refresh = te.refresh_restore
  end
  arc_block(false)
end

--- the menu changed its page or its mode (lua/core/menu.lua set_page and set_mode): an entry that was open for the old one is closed
te.menu_changed = function(what)
  if not desktop or te.opening or not te.active then return end
  abandon()
end

-- add one character: false (and a hint) if the entry refuses it
local function add_char(a)
  local t = te.txt
  if desktop and te.fresh then t = "" end
  t = t .. a
  if desktop and te.accept then
    local ok, why = te.accept(t)
    if not ok then
      te.warn = why or te.refuse or "not allowed"
      return false
    end
  end
  te.fresh = false
  te.txt = t
  if te.check then te.warn = te.check(te.txt) else te.warn = nil end
  return true
end

-- computers: the keyboard equivalents of the hardware controls while an entry is open (the keys are the entry's, so the menu's own bindings and the hardware keys are off):
-- LEFT / RIGHT are E2 (the character, or DEL / OK), UP / DOWN are E3 (the character row, the DEL OK row), PAGEUP / PAGEDOWN five steps of E2, and the value keys (- and =, the two keys
-- right of 0) step E2 when the character they would type is refused by the entry (a hex entry refuses both; a name entry types - and steps on =; an entry without an accept function types both
-- as before). Shift makes E2 five steps. a press and a repeat act, a release (delta 0) never does. every control ends in te.enc, which redraws
local nav = {LEFT = {2, -1}, RIGHT = {2, 1}, UP = {3, -1}, DOWN = {3, 1}, PAGEUP = {2, -5}, PAGEDOWN = {2, 5}}
local value_keys = {MINUS = -1, EQUAL = 1}

local function navigate(c, value)
  if not desktop or not te.active or value == 0 then
    return false
  end
  local n = nav[c]
  if n then
    local d = n[2]
    if n[1] == 2 and keyboard.shift() and math.abs(d) == 1 then d = d * 5 end
    te.enc(n[1], d)
    return true
  end
  local v = value_keys[c]
  if v and te.accept then
    local a = keyboard.code_to_char(c)
    local base = te.fresh and "" or te.txt
    if a ~= nil and te.accept(base .. a) then
      return false -- the entry takes this character: typing wins
    end
    te.skip_char = a ~= nil
    te.enc(2, v * value) -- a repeat (2) is two steps, as on the other pages
    return true
  end
  return false
end

-- computers, an entry opened with opts.clip = "colour" (the picker's hex entry): Ctrl+C copies the code (when the text is a colour) and Ctrl+V pastes one (3 or 6 digits, with or without #)
-- into the text; a clipboard that is empty, too long, binary or not a colour changes nothing and says so on the hint line. these two never type a character
local function clip_keys(c, value)
  if not desktop or not te.active or te.clip ~= "colour" or not keyboard.ctrl() or (c ~= "C" and c ~= "V") then
    return false
  end
  if value ~= 1 then
    return true
  end
  local clipboard = require 'core/clipboard'
  local colour = require 'core/colour'
  if c == "C" then
    local hex = colour.hex(te.txt)
    if hex == nil then
      te.warn = "not a colour yet"
    else
      te.warn = clipboard.copy("#" .. hex) and ("copied #" .. hex) or "no clipboard"
    end
    te.redraw()
  else
    te.warn = "pasting.."
    clipboard.paste_colour(function(hex, why)
      if not te.active then return end
      if hex then
        te.txt = "#" .. hex
        te.fresh = false
        te.row = 1
        te.delok = 1
        te.warn = "pasted #" .. hex
      else
        te.warn = why
      end
      te.redraw()
    end)
    te.redraw()
  end
  return true
end

local function keycode(c,value)
  if clip_keys(c, value) then
    return
  end
  if navigate(c, value) then
    return
  end
  if keyboard.state.ESC then
    te.txt = nil
    te.exit()
  elseif keyboard.state.ENTER then
    te.exit()
  elseif keyboard.state.BACKSPACE then
    te.row = 1
    te.delok = 0
    te.fresh = false
    te.txt = string.sub(te.txt,0,-2)
    if te.check then
      te.warn = te.check(te.txt)
    end
    te.redraw()
  end
end

local function keychar(a)
  if desktop and te.clip == "colour" and keyboard.ctrl() then
    return -- Ctrl+C and Ctrl+V are keys of the entry, not letters
  end
  if desktop and te.skip_char then
    te.skip_char = false -- this character was a value key: it has stepped the selection already
    return
  end
  te.row = 0
  te.pos = string.byte(a) - 5 - 32
  if desktop then
    add_char(a)
  else
    te.txt = te.txt .. a
    if te.check then
      te.warn = te.check(te.txt)
    end
  end
  te.redraw()
end

-- opts (computers only): accept(text) -> true, or false and a short hint; replace = true: the first typed character replaces the default
te.enter = function(callback, default, heading, check, opts)
  if desktop and te.active then
    if orphaned() then
      -- the entry that is marked active is not on the screen any more: close it and open this one, and say so (the next time it happens the log shows what left it behind)
      print("textentry: an earlier entry ('" .. tostring(te.heading) .. "') was left active (the menu moved on: page " .. tostring(te.opened_page) .. ", now " .. tostring(_menu.page) .. "); it is closed")
      abandon()
    else
      print("textentry: cannot open '" .. tostring(heading) .. "': another entry ('" .. tostring(te.heading) .. "') is still active")
      return -- one entry at a time: the keys are the open entry's, and its restore must stay the page's
    end
  end
  te.opening = true
  te.opened_menu = norns.menu.status()
  te.opened_page = _menu and _menu.page
  te.active = true
  te.accept = desktop and opts and opts.accept or nil
  te.refuse = desktop and opts and opts.refuse or nil
  te.clip = desktop and opts and opts.clip or nil
  te.fresh = desktop and opts and opts.replace and default ~= nil and default ~= "" or false
  te.txt = default or ""
  te.heading = heading or ""
  te.pos = 28
  if default then te.row=1 else te.row = 0 end
  te.delok = 1
  te.callback = callback
  te.check = check
  te.warn = nil
  te.pending = false
  te.skip_char = false
  te_kbd_cb.code = keycode
  te_kbd_cb.char = keychar
  arc_block(true)

  if norns.menu.status() == false then
    te.key_restore = key
    te.enc_restore = enc
    te.redraw_restore = redraw
    te.refresh_restore = refresh
    key = te.key
    enc = te.enc
    norns.menu.init()
    redraw = norns.none
  else
    te.key_restore = norns.menu.get_key()
    te.enc_restore = norns.menu.get_enc()
    te.redraw_restore = norns.menu.get_redraw()
    te.refresh_restore = norns.menu.get_refresh()
    norns.menu.set(te.enc, te.key, te.redraw, te.refresh)
  end
  te.opening = false
  te.redraw()
end

te.exit = function()
  if desktop and not te.active then
    return -- nothing is open: nothing to give back
  end
  te.active = false
  te_kbd_cb.code = nil
  te_kbd_cb.char = nil
  arc_block(false)

  if norns.menu.status() == false then
    key = te.key_restore
    enc = te.enc_restore
    redraw = te.redraw_restore
    refresh = te.refresh_restore
    norns.menu.init()
  else
    norns.menu.set(te.enc_restore, te.key_restore, te.redraw_restore, te.refresh_restore)
  end
  if te.txt then te.callback(te.txt)
  else te.callback(nil) end
end


te.key = function(n,z)
  if n==2 and z==0 then
    te.txt = nil
    te.exit()
  elseif n==3 and z==1 then
    if te.row == 0 then
      local ch = ((5+te.pos)%95)+32
      if desktop then
        add_char(utf8.char(ch))
      else
        te.txt = te.txt .. utf8.char(ch)
        if te.check then
          te.warn = te.check(te.txt)
        end
      end
      te.redraw()
    else
      if te.delok==0 then
        te.fresh = false
        te.txt = string.sub(te.txt,0,-2)
        if te.check then
          te.warn = te.check(te.txt)
	end
        te.redraw()
      elseif te.delok == 1 then
        te.pending = true
      end
    end
  elseif n==3 and z==0 and te.pending == true then
    if te.row == 1 and te.delok==1 then te.exit() end
  end
end

te.enc = function(n,delta)
  if n==2 then
    if te.row == 1 then
      if delta > 0 then te.delok = 1
      else te.delok = 0 end
    else te.pos = (te.pos + delta) % 95 end
    te.redraw()
  elseif n==3 then
    if delta > 0 then te.row = 1
    else te.row = 0 end
    te.redraw()
  end
end

-- computers: the text as far as it fits (the end of it, with .. in front when it is cut)
local function fitted(txt)
  if screen.text_extents(txt) <= 124 then return txt end
  local n = #txt
  while n > 1 and screen.text_extents(".." .. string.sub(txt, #txt - n + 1)) > 124 do n = n - 1 end
  return ".." .. string.sub(txt, #txt - n + 1)
end

te.redraw = function()
  if desktop and not te.active then
    return -- a stale redraw (the menu still holds it for a moment after the entry closed): nothing to draw
  end
  screen.clear()
  screen.level(15)
  screen.move(0,16)
  screen.text(te.heading)
  screen.move(0,32)
  if desktop then
    screen.text(fitted(te.txt))
    if te.warn ~= nil and te.warn ~= "" then
      screen.level(10)
      screen.move(0,24)
      screen.text(te.warn)
      screen.level(15)
    end
  else
    screen.text(te.txt)
    if te.warn ~= nil then
      screen.move(128,32)
      screen.text_right(te.warn)
    end
  end
  for x=0,15 do
    if x==5 and te.row==0 then screen.level(15) else screen.level(2) end
    screen.move(x*8,46)
    screen.text(utf8.char((x+te.pos)%95+32))
  end

  screen.move(0,60)
  if te.row==1 and te.delok==0 then screen.level(15) else screen.level(2) end
  screen.text("DEL")
  screen.move(127,60)
  if te.row==1 and te.delok==1 then screen.level(15) else screen.level(2) end
  screen.text_right("OK")

  screen.update()
end

te.refresh = function() te.redraw() end

return te
