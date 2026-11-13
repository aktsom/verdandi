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
  screen.level(15)
  screen.move(2, 8)
  screen.text("EXT FOLDERS")
  local r = rows()
  local first = math.max(1, math.min(m.pos - 1, #r - 3))
  for i = 0, 3 do
    local row = r[first + i]
    if row then
      local y = 19 + i * 10
      local sel = (first + i == m.pos)
      if row.add then
        winui.row(y, "ADD FOLDER", "", sel, m.tick, nil)
      else
        winui.row(y, winui.fit(row.name, 70, false), row.path, sel, m.tick, MARKS[row.state])
      end
    end
  end
  local note = m.msg
  if not note then
    local row = r[m.pos]
    note = (row and row.add) and "K3: choose a folder" or "K3: remove the shortcut"
  end
  -- two lines at a time at the bottom; a longer sentence turns to its next two lines every three seconds
  local lines = winui.pages(note, 124)
  local chunks = math.max(1, math.ceil(#lines / 2))
  local c = m.msg and (math.floor((m.tick - (m.msg_at or 0)) / 12) % chunks) or 0
  local a, b = lines[c * 2 + 1], lines[c * 2 + 2]
  screen.level(10)
  screen.move(2, b and 54 or 62)
  screen.text(a or "")
  if b then
    screen.move(2, 62)
    screen.text(b)
  end
  screen.update()
end

return m
