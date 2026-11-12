-- gridwin.lua: SYSTEM > DEVICES > "grid ports" (Windows build only, docs/port/phase-m5.md). one short list as on a norns: E2 selects a row, K2 goes back.
--   a row for each grid that is in the list (its name, size and serial; the port it is on), a row for each problem (a port another program holds, a monome that did not answer) with the help in plain words,
--   a row for each serial port that is NOT a monome and was left alone. everything comes from _norns.grid_status (key=value lines from the grid monitor).
local winui = require 'core/menu/winui'

local m = {pos = 1, top = 1, tick = 0, st = {}}
local ROWS_SHOWN = 3
local PAGE_TICKS = 12

local function parse(text)
  local st = {grids = {}, notes = {}, others = {}}
  for line in tostring(text or ""):gmatch("[^\n]+") do
    local k, v = line:match("^([%w_]+)=(.*)$")
    if k == "grid" then
      local port, serial, name, cols, rows = v:match("^(.-)\t(.-)\t(.-)\t(%d+)\t(%d+)$")
      if port then st.grids[#st.grids + 1] = {port = port, serial = serial, name = name, cols = tonumber(cols), rows = tonumber(rows)} end
    elseif k == "note" then st.notes[#st.notes + 1] = v
    elseif k == "other" then st.others[#st.others + 1] = v end
  end
  return st
end

-- M6: serialosc (a process or a service) holds grid ports: what Windows says about it
local function parse_so(text)
  local so = {running = false, procs = {}, services = {}}
  for line in tostring(text or ""):gmatch("[^\n]+") do
    local k, v = line:match("^([%w_]+)=(.*)$")
    if k == "running" then so.running = v == "1"
    elseif k == "so_note" then so.note = v
    elseif k == "so_prevent" then so.prevent = v
    elseif k == "so_admin" then so.admin = v
    elseif k == "so_last" then so.last = v
    elseif k == "so_proc" then so.procs[#so.procs + 1] = v
    elseif k == "so_service" then so.services[#so.services + 1] = v end
  end
  return so
end

local CONF = "/home/we/audio.conf"
-- one key of audio.conf (the pages keep keys they do not know)
function m.read_setting(key)
  local f = io.open(CONF)
  if not f then return nil end
  local v
  for line in f:lines() do
    local k, val = line:match("^([%w_]+)=(.*)$")
    if k == key then v = val end
  end
  f:close()
  return v
end
function m.save_setting(key, value)
  local lines, found = {}, false
  local f = io.open(CONF)
  if f then
    for line in f:lines() do
      local k = line:match("^([%w_]+)=")
      if k == key then lines[#lines + 1] = key .. "=" .. value; found = true else lines[#lines + 1] = line end
    end
    f:close()
  end
  if not found then lines[#lines + 1] = key .. "=" .. value end
  local tmp = CONF .. ".tmp"
  local o = io.open(tmp, "w")
  if not o then return false end
  o:write(table.concat(lines, "\n"), "\n")
  o:close()
  return os.rename(tmp, CONF)
end

local function refresh()
  m.st = parse(_norns.grid_status and _norns.grid_status() or "")
  m.so = parse_so(_norns.serialosc_status and _norns.serialosc_status() or "")
end

local function rows()
  local r = {}
  for _, n in ipairs(m.st.notes) do
    local port, why = n:match("^(.-): (.*)$")
    r[#r + 1] = {kind = "note", label = port or n, value = "problem", help = why or n}
  end
  if m.so and m.so.running then
    local h = (m.so.note or "serialosc is running.")
    if m.so.admin then
      h = h .. " It needs administrator rights to stop: type this in an administrator Command Prompt: " .. m.so.admin
    end
    if m.so.last then h = h .. " Last time: " .. m.so.last end
    h = h .. " " .. (m.so.prevent or "")
    r[#r + 1] = {kind = "serialosc", label = "SERIALOSC", value = m.asked and "K3 AGAIN" or (m.so_msg or "running"), help = h}
  end
  for _, g in ipairs(m.st.grids) do
    local size = g.cols == 0 and "arc" or (g.cols .. "x" .. g.rows)
    r[#r + 1] = {kind = "grid", label = g.name, value = g.port,
      help = string.format("%s, %s, serial %s, on %s. Give it a vport in SYSTEM > DEVICES > %s. It keeps its name and serial when it is moved to another USB socket.", g.name, size, g.serial ~= "" and g.serial or "none", g.port, g.cols == 0 and "ARC" or "GRID")}
  end
  r[#r + 1] = {kind = "info", label = "GRIDS", value = (#m.st.grids == 0) and "none" or (#m.st.grids .. " found"),
    help = (#m.st.grids == 0) and "No grid found. Plug it in with its USB cable. A serial port that is not a monome is left alone (see below); to use one anyway put its serial in monome_serial= in audio.conf." or "Every grid listed above is open. Plug in or pull out as you like: the list follows."}
  if _norns.serialosc_status then
    local on = m.read_setting("serialosc_autostop") == "1"
    if m.autostop ~= nil then on = m.autostop end
    r[#r + 1] = {kind = "autostop", label = "AUTO STOP", value = on and "on" or "off",
      help = "E3 on: when Verdandi finds a grid's port held by serialosc, it stops serialosc by itself (at most once a minute) and opens the grid. Only serialosc's own programs and service are ever stopped, never anything else. Off by default."}
  end
  for _, o in ipairs(m.st.others) do
    local port, why = o:match("^(.-): (.*)$")
    r[#r + 1] = {kind = "other", label = port or o, value = "not a monome", help = why or o}
  end
  return r
end
m.rows = rows

local function help_text(row) return row and row.help or "" end
m.help_full = function() return help_text(rows()[m.pos]) end
m.help_lines = function()
  local pages = winui.pages(help_text(rows()[m.pos]), 118)
  if #pages == 0 then return {} end
  local first = (math.floor(m.tick / PAGE_TICKS) % math.ceil(#pages / 3)) * 3
  local out = {}
  for i = first + 1, math.min(first + 3, #pages) do out[#out + 1] = pages[i] end
  return out
end

m.init = function()
  refresh()
  m.pos, m.top, m.tick, m.asked, m.so_msg, m.autostop = 1, 1, 0, false, nil, nil
  _menu.timer.time = 0.5
  _menu.timer.count = -1
  _menu.timer.event = function() m.timer() end
  _menu.timer:start()
end
m.deinit = function() _menu.timer:stop() end
m.timer = function()
  m.tick = m.tick + 1
  refresh()
  local n = #rows()
  if m.pos > n then m.pos = n end
  _menu.redraw()
end

m.key = function(n, z)
  if z == 1 and n == 2 then return "back" end
  if z == 1 and n == 3 then
    local row = rows()[m.pos]
    if row and row.kind == "serialosc" then
      if not m.asked then
        m.asked = true -- asks once: the second K3 does it
      else
        m.asked = false
        local left = _norns.serialosc_stop and _norns.serialosc_stop() or 0
        m.so_msg = left == 0 and "stopped" or "not stopped"
        refresh()
      end
      _menu.redraw()
    end
  end
end

m.enc = function(n, delta)
  if n == 3 then
    local row = rows()[m.pos]
    if row and row.kind == "autostop" then
      m.autostop = delta > 0
      m.save_setting("serialosc_autostop", m.autostop and "1" or "0")
      _menu.redraw()
    end
  elseif n == 2 then
    m.pos = util.clamp(m.pos + delta, 1, math.max(1, #rows()))
    m.asked, m.so_msg = false, nil -- a question and a result belong to their row
    m.tick = 0
    _menu.redraw()
  end
end

m.redraw = function()
  screen.clear()
  local r = rows()
  m.top = util.clamp(m.pos - 1, 1, math.max(1, #r - ROWS_SHOWN + 1))
  for k = 0, ROWS_SHOWN - 1 do
    local row = r[m.top + k]
    if row then
      local sel = (m.top + k) == m.pos
      winui.row(8 + 9 * k, winui.fit(row.label, 72, sel, m.tick), row.value, sel, m.tick)
    end
  end
  local lines = m.help_lines()
  if #lines > 0 then
    screen.level(0)
    screen.rect(0, 31, 128, 26)
    screen.fill()
    screen.level(15)
    screen.line_width(1)
    screen.rect(0.5, 31.5, 127, 25)
    screen.stroke()
    for k, l in ipairs(lines) do
      screen.level(15)
      screen.move(3, 39 + 8 * (k - 1))
      screen.text(l)
    end
  end
  screen.level(15)
  screen.move(2, 63)
  screen.text(winui.fit(string.format("%d grid%s", #m.st.grids, #m.st.grids == 1 and "" or "s"), 124, false, 0))
  screen.update()
end

return m
