-- midiwin.lua: SYSTEM > DEVICES > "midi routes" (Windows build only, docs/port/phase-m4.md). one short list as on a norns: E2 selects a row, K2 goes back, K3 starts a test.
--   a row for each MIDI device that another program holds (named by the device, plain words in the help, whatever the program is),
--   CABLES   virtual MIDI ports found (loopMIDI, Windows MIDI Services loopback, any other program's): how to get one when there is none,
--   OSC IN   the control input on 127.0.0.1 (any program that can send OSC), TEST OSC / TEST <cable>: round trip and jitter of that route, on the row itself, then RESULTS: the quickest route.
-- everything shown comes from _norns.midi_status (key=value lines from the MIDI layer). a message belongs to its row and goes when E2 moves.
local winui = require 'core/menu/winui'

local m = {pos = 1, top = 1, tick = 0, st = {}, testing = nil, results = {}, order = {}, shown = {}}
local ROWS_SHOWN = winui.ROWS
local PAGE_TICKS = 12 -- a page of the help for 3 seconds

local function parse(text)
  local st = {note_list = {}, cable_list = {}, open_list = {}}
  for line in tostring(text or ""):gmatch("[^\n]+") do
    local k, v = line:match("^([%w_]+)=(.*)$")
    if k == "note" then st.note_list[#st.note_list + 1] = v
    elseif k == "cable" then st.cable_list[#st.cable_list + 1] = v
    elseif k == "open" then st.open_list[#st.open_list + 1] = v
    elseif k then st[k] = v end
  end
  st.osc_port = tonumber(st.osc_port or "0") or 0
  st.osc_used = tonumber(st.osc_used or "0") or 0
  return st
end

local function refresh() m.st = parse(_norns.midi_status and _norns.midi_status() or "") end

-- the rows: {label, value, kind, help}
local function rows()
  local st, r = m.st, {}
  for _, n in ipairs(st.note_list) do
    local name, why = n:match("^(.-): (.*)$")
    name = name or n
    r[#r + 1] = {kind = "note", label = name, value = "held", help = (why or n) .. ". Another program has this MIDI port. Close the port in that program, or put the device's name in midi_ignore= in audio.conf so that Verdandi leaves it alone. Then plug it in again."}
  end
  local nc = #st.cable_list
  r[#r + 1] = {kind = "info", label = "CABLES", value = nc == 0 and "none" or (nc .. " found"),
    help = nc == 0 and "No virtual MIDI port found. To connect another program install loopMIDI (free) and add a port, or use the loopback ports of Windows MIDI Services (Windows 11). Details: windows\\README.md, MIDI."
      or "Virtual ports are ordinary devices: give one a vport on DEVICES > MIDI, and the other program uses the same port. K3 on its TEST row measures the delay."}
  if st.osc_port > 0 then
    r[#r + 1] = {kind = "info", label = "OSC IN", value = "127.0.0.1:" .. st.osc_port .. (st.osc_used > 0 and (" (" .. st.osc_used .. ")") or ""),
      help = "Control values by UDP: /cc channel number value to 127.0.0.1 port " .. st.osc_port .. ". Any program can send them. They appear as the device osc in DEVICES > MIDI. Only this computer can reach it."}
  else
    r[#r + 1] = {kind = "info", label = "OSC IN", value = "off", help = "The OSC input is off (osc_in_port=0 in audio.conf). Set a port such as 9201 and restart to use it."}
  end
  if st.osc_port > 0 then
    r[#r + 1] = {kind = "test", test = "osc", label = "TEST OSC", value = "", key = "TEST OSC", help = "K3 measures the OSC route: round trip and jitter on this computer (about 3 seconds). The program that sends adds its own delay."}
  end
  for _, c in ipairs(st.cable_list) do
    r[#r + 1] = {kind = "test", test = "midi", device = c, label = "TEST " .. c, value = "", key = "TEST " .. c,
      help = "K3 sends test messages out of " .. c .. " and counts the time until they come back in (about 3 seconds). The port must be open here. Scripts may see control change 119 on channel 16."}
  end
  if #m.order > 0 then
    r[#r + 1] = {kind = "results", label = "RESULTS", value = tostring(#m.order), help = nil}
  end
  return r
end
m.rows = rows

-- "label: 0.04 ms round trip (mean), 0.09 worst, jitter 0.01, 200 of 200" -> label, mean, jitter
local function parse_route(line)
  local label, mean, jit = tostring(line or ""):match("^(.-): ([%d%.]+) ms round trip %(mean%), [%d%.]+ worst, jitter ([%d%.]+)")
  return label, tonumber(mean), tonumber(jit)
end

local function recommendation()
  local best, rest = nil, {}
  for _, label in ipairs(m.order) do
    local r = m.results[label]
    if not best or r.mean + r.jit < best.mean + best.jit then best = r end
  end
  if not best then return "" end
  local t = "Lowest: " .. best.label .. ", " .. string.format("%.2f", best.mean) .. " ms (jitter " .. string.format("%.2f", best.jit) .. ")."
  for _, label in ipairs(m.order) do
    if label ~= best.label then t = t .. " " .. label .. " " .. string.format("%.2f", m.results[label].mean) .. " ms." end
  end
  return t .. " Round trip on this computer; the other program adds its own buffer."
end

local function help_text(row)
  if not row then return "" end
  if row.kind == "results" then return recommendation() end
  return row.help or ""
end

m.help_full = function() return help_text(rows()[m.pos]) end

m.help_lines = function()
  local r = rows()
  return winui.help_pages(help_text(r[m.pos]), m.tick, PAGE_TICKS)
end

local function short(line)
  local label, mean, jit = parse_route(line)
  if mean then return string.format("%.2f ms  j %.2f", mean, jit) end
  return "failed"
end

m.init = function()
  refresh()
  m.pos, m.top, m.tick, m.testing, m.shown = 1, 1, 0, nil, {}
  _menu.timer.time = 0.25
  _menu.timer.count = -1
  _menu.timer.event = function() m.timer() end
  _menu.timer:start()
end

m.deinit = function() _menu.timer:stop() end

m.timer = function()
  m.tick = m.tick + 1
  refresh()
  if m.testing then
    local s = m.st.route_state
    if s == "done" or s == "failed" then
      local label, mean, jit = parse_route(m.st.route)
      if mean then
        if not m.results[label] then m.order[#m.order + 1] = label end
        m.results[label] = {label = label, mean = mean, jit = jit}
      end
      m.shown[m.testing.key] = short(m.st.route)
      m.fail_text = s == "failed" and m.st.route or nil
      m.testing = nil
    end
  end
  _menu.redraw()
end

m.key = function(n, z)
  if z ~= 1 then return end
  if n == 2 then
    return "back"
  elseif n == 3 then
    local row = rows()[m.pos]
    if row and row.kind == "test" and not m.testing then
      local rc, msg = _norns.midi_route_test(row.test, row.device or "")
      if rc == 0 then
        m.testing = row
        m.shown[row.key] = nil
      else
        m.shown[row.key] = "failed"
        m.fail_text = msg
      end
      _menu.redraw()
    end
  end
end

m.enc = function(n, delta)
  if n == 2 then
    local r = rows()
    m.pos = util.clamp(m.pos + delta, 1, math.max(1, #r))
    m.shown = {} -- a result belongs to its row and goes when E2 moves
    m.fail_text = nil
    m.tick = 0
    _menu.redraw()
  end
end

local function value_of(row)
  if row.kind == "test" then
    if m.testing and m.testing.key == row.key then return "testing..." end
    return m.shown[row.key] or "K3"
  end
  return row.value
end

m.redraw = function()
  screen.clear()
  local r = rows()
  local list = {}
  for i, row in ipairs(r) do list[i] = {label = row.label, value = value_of(row)} end
  local top, full, was_cut = winui.list(list, m.pos)
  m.top = top
  -- the standing line under the list, then the info area: the full text of the selected row when it was cut, else its help, two lines at a time
  winui.status(m.fail_text or string.format("%s  %s devices", m.st.backend or "WinMM", m.st.devices or "0"))
  if was_cut then winui.info(full) else winui.info_lines(winui.help_pages(help_text(r[m.pos]), m.tick, PAGE_TICKS)) end
  screen.update()
end

return m
