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

local function keycode(c,value)
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
    return -- one entry at a time: the keys are the open entry's, and its restore must stay the page's
  end
  te.active = true
  te.accept = desktop and opts and opts.accept or nil
  te.refuse = desktop and opts and opts.refuse or nil
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
  te_kbd_cb.code = keycode
  te_kbd_cb.char = keychar

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
  te.redraw()
end

te.exit = function()
  if desktop and not te.active then
    return -- nothing is open: nothing to give back
  end
  te.active = false
  te_kbd_cb.code = nil
  te_kbd_cb.char = nil

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
