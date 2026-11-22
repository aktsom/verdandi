-- SYSTEM > EXT FOLDERS (Windows since docs/port/phase-m8.md, Linux since M27, docs/port/phase-m27.md; one page, the same words on both): folders anywhere on the computer whose samples show up in norns's file browser and on the tape page,
-- next to the dust folders, as "[ext] <name>".
--   ADD FOLDER first (M33), then the folders already added, one per row, A to Z and numbers in number order (name, the folder, and a mark when it is not reachable: MISSING for an unplugged drive or a renamed folder,
--   BLOCKED when a real folder in dust has the name), then (Linux and macOS-made imports only) the links an older "Import" made in dust/audio/mac, marked IMPORT, sorted the same way, so that they can be removed here too. a line under the list says what K3 and K2 do for the selected row.
--   E2 chooses a row. K3 on ADD FOLDER opens the folder window (Windows: its own; Linux: the desktop's, or zenity or kdialog). K3 on a folder asks (a warning in plain words); K3 again removes the SHORTCUT, K2 cancels. K2 goes back.
--   a folder dropped on the window is added the same way (_norns.ext_dropped); a dropped file is refused by the window code.
-- a removal only takes away the shortcut in dust/audio; the files in the folder are never touched (platform/common/extfolders.c checks that the entry is really a link first).
local winui = require 'core/menu/winui'

local m = {pos = 1, items = {}, legacy = {}, confirm = nil, msg = nil, waiting = false, tick = 0}

-- M33: the order of names. case is ignored; a name is cut into runs of digits and runs of other characters; two digit runs are compared as numbers (2 before 10; the same number: the shorter run first, so 2 before 02);
-- a digit run comes before a text run (a name that starts with a digit comes before one that starts with a letter); text runs compare as lower case; a tie ends with the exact text, so the order is always the same
local function runs(name)
  local out = {}
  for digits, text in tostring(name):gmatch("(%d*)(%D*)") do
    if digits ~= "" then out[#out + 1] = {digit = true, text = digits} end
    if text ~= "" then out[#out + 1] = {digit = false, text = text:lower()} end
  end
  return out
end

function m.natural_less(a, b)
  local ra, rb = runs(a), runs(b)
  for i = 1, math.min(#ra, #rb) do
    local x, y = ra[i], rb[i]
    if x.digit ~= y.digit then return x.digit end
    if x.digit then
      local nx, ny = tonumber(x.text), tonumber(y.text)
      if nx ~= ny then return nx < ny end
      if #x.text ~= #y.text then return #x.text < #y.text end
    elseif x.text ~= y.text then
      return x.text < y.text
    end
  end
  if #ra ~= #rb then return #ra < #rb end
  return tostring(a) < tostring(b)
end

local function by_name(x, y) return m.natural_less(x.name, y.name) end

local function load()
  m.items = (_norns.ext_list and _norns.ext_list()) or {}
  table.sort(m.items, by_name)
  -- the links an older Import made (dust/audio/mac): nothing on Windows
  m.legacy = {}
  for _, it in ipairs((_norns.ext_legacy_list and _norns.ext_legacy_list()) or {}) do
    it.legacy = true
    m.legacy[#m.legacy + 1] = it
  end
  table.sort(m.legacy, by_name)
end

local MARKS = {missing = "MISSING", blocked = "BLOCKED", nolink = "NO LINK"}
local LEGACY_MARKS = {ok = "IMPORT", missing = "IMPORT GONE"}

-- ADD FOLDER first (M33: the way to add is always on the first row), then the folders, then the old import links; each group sorted by name
local function rows()
  local r = {{add = true}}
  for _, it in ipairs(m.items) do r[#r + 1] = it end
  for _, it in ipairs(m.legacy) do r[#r + 1] = it end
  return r
end

m.rows = rows -- (for the test: the rows in the order they are shown)

-- the selection goes to the folder that was just added, at its place in the sorted list
local function select_named(name)
  for i, row in ipairs(rows()) do
    if not row.add and not row.legacy and row.name == name then m.pos = i; return end
  end
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
  if ok and name and name ~= "" then select_named(name) end
  say(text)
end

-- a folder was dropped on the window (platform code: only folders come here, a file is refused there): added like a chosen one, the answer on the page when it is open and as a message on the window
_norns.ext_dropped = function(path)
  local ok, text, name = _norns.ext_add(path)
  load()
  if ok and name and name ~= "" then select_named(name) end
  say(text)
  if _norns.toast then _norns.toast(text) end
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
      local ok, text
      if m.confirm.legacy then ok, text = _norns.ext_legacy_remove(m.confirm.name) else ok, text = _norns.ext_remove(m.confirm.name) end
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
  local text
  if it.legacy then
    text = string.format("This removes the import link %s from dust. The file it points to (%s) is NOT deleted.", it.name, it.path)
  else
    text = string.format("This removes the shortcut %s from dust. Your files in %s are NOT deleted.", it.name, it.path)
  end
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
    elseif row.legacy then list[i] = {label = row.name, value = row.path, mark = LEGACY_MARKS[row.state] or "IMPORT"}
    else list[i] = {label = row.name, value = row.path, mark = MARKS[row.state]} end
  end
  local top, full, was_cut = winui.list(list, m.pos)
  m.top = top
  local sel = r[m.pos]
  -- the standing line is always the hint: what K3 does for the selected row, and that K2 goes back
  winui.status(sel and sel.add and "K3 ADD A FOLDER  K2 BACK" or "K3 REMOVE  K2 BACK")
  local text = m.msg
  if not text then
    if was_cut then text = full
    elseif sel and sel.add then text = "Choose a folder with samples: it shows in the file browser as [ext] and its name."
    elseif sel and sel.legacy then text = "An old import link: removing it takes away the link only, never the file."
    else text = "Removing takes away the shortcut only: your files stay." end
  end
  -- a long message turns to its next two lines every three seconds (the result of an add or a remove; nothing in the list scrolls)
  if m.msg then winui.info_lines(winui.help_pages(m.msg, m.tick - (m.msg_at or 0), 12)) else winui.info(text) end
  screen.update()
end

return m
