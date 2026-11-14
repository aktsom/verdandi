-- SYSTEM > EXT FOLDERS (Windows build; docs/port/phase-m8.md): folders anywhere on the computer whose samples show up in norns's file browser and on the tape page, next to the dust folders, as "[ext] <name>".
--   the folders already added, one per row (name, the folder, and a mark when it is not reachable: MISSING for an unplugged drive or a renamed folder, BLOCKED when a real folder in dust has the name), then ADD FOLDER.
--   E2 chooses a row. K3 on ADD FOLDER opens Windows's folder window. K3 on a folder asks (a warning in plain words); K3 again removes the SHORTCUT, K2 cancels. K2 goes back.
-- a removal only takes away the shortcut in dust\audio; the files in the folder are never touched (platform/common/extfolders.c checks that the entry is really a link first).
local winui = require 'core/menu/winui'

local m = {pos = 1, items = {}, confirm = nil, msg = nil, waiting = false, tick = 0}

local function load()
  m.items = (_norns.ext_list and _norns.ext_list()) or {}
end

local MARKS = {missing = "MISSING", blocked = "BLOCKED", nolink = "NO LINK"}

local function rows()
  local r = {}
  for _, it in ipairs(m.items) do r[#r + 1] = it end
  r[#r + 1] = {add = true}
  return r
end

local function setmsg(s)
  m.msg, m.msg_at = s, m.tick
end

local function say(s)
  setmsg(s)
  if _menu.page == "EXTRA" then _menu.redraw() end
end

-- the picker window answered ("" = cancelled)
-- (path, err): a path = chosen; "" and no err = the user pressed Cancel; "" and an err = the window could not open: the error is shown with its code
_norns.ext_folder_chosen = function(path, err)
  m.waiting = false
  if err ~= nil and err ~= "" then
    print("ext folders: " .. err)
    say(err)
    return
  end
  if path == nil or path == "" then
    say("cancelled")
    return
  end
  local ok, text, name = _norns.ext_add(path)
  load()
  if ok and name and name ~= "" then
    for i, it in ipairs(m.items) do
      if it.name == name then m.pos = i end
    end
  end
  say(text)
end

-- the menu item "Ext folders" of the window
_norns.open_extra_folders = function()
  if not _menu.mode then _menu.set_mode(true) end
  _menu.set_page("EXTRA")
end

m.init = function()
  load()
  m.confirm, m.msg, m.waiting = nil, nil, false
  local r = rows()
  m.pos = util.clamp(m.pos, 1, #r)
  m.tick = 0
  -- the menu's own timer (as the other pages use it): the marquee of the selected row's folder
  _menu.timer.time = 0.25
  _menu.timer.count = -1
  _menu.timer.event = function() m.tick = m.tick + 1; _menu.redraw() end
  _menu.timer:start()
end

m.deinit = function()
  _menu.timer:stop()
  m.confirm = nil
end

m.key = function(n, z)
  if z ~= 1 then return end
  if m.confirm then
    if n == 3 then
      local ok, text = _norns.ext_remove(m.confirm.name)
      m.confirm = nil
      load()
      m.pos = util.clamp(m.pos, 1, #rows())
      setmsg(text)
    elseif n == 2 then
      m.confirm = nil
      setmsg("cancelled: nothing was removed")
    end
    _menu.redraw()
    return
  end
  if n == 2 then
    _menu.set_page("SYSTEM")
  elseif n == 3 then
    local row = rows()[m.pos]
    if row == nil then return end
    if row.add then
      if m.waiting then return end
      m.waiting = true
      setmsg("choose a folder in the window")
      _norns.ext_pick()
    else
      m.confirm = row
      m.msg = nil
    end
    _menu.redraw()
  end
end

m.enc = function(n, delta)
  if m.confirm then return end
  if n == 2 then
    m.pos = util.clamp(m.pos + (delta > 0 and 1 or -1), 1, #rows())
    m.msg = nil
    _menu.redraw()
  end
end

local function warning_lines(it)
  local text = string.format("This removes the shortcut %s from dust. Your files in %s are NOT deleted.", it.name, it.path)
  return winui.pages(text, 124)
end

m.redraw = function()
  screen.clear()
  if m.confirm then
    -- the warning: all of the screen, the keys named at the bottom
    local lines = warning_lines(m.confirm)
    for i = 1, math.min(#lines, 5) do
      screen.level(15)
      screen.move(2, 8 + (i - 1) * 9)
      screen.text(lines[i])
    end
    screen.level(10)
    screen.move(2, 62)
    screen.text("K3 again: remove  K2: cancel")
    screen.update()
    return
  end
  -- the list (the same rows and place as the other list pages), the standing line under it, the info area at the bottom: the full text of the selected row when it was cut, else what K3 does or the last message
  local r = rows()
  local list = {}
  for i, row in ipairs(r) do
    if row.add then list[i] = {label = "ADD FOLDER", value = ""}
    else list[i] = {label = row.name, value = row.path, mark = MARKS[row.state]} end
  end
  local top, full, was_cut = winui.list(list, m.pos)
  m.top = top
  winui.status("EXT FOLDERS  " .. #m.items)
  local sel = r[m.pos]
  local text = m.msg
  if not text then
    if was_cut then text = full
    elseif sel and sel.add then text = "K3: choose a folder to add"
    else text = "K3: remove the shortcut (your files stay)" end
  end
  -- a long message turns to its next two lines every three seconds (the result of an add or a remove; nothing in the list scrolls)
  if m.msg then winui.info_lines(winui.help_pages(m.msg, m.tick - (m.msg_at or 0), 12)) else winui.info(text) end
  screen.update()
end

return m
