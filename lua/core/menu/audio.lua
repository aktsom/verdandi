-- SYSTEM > AUDIO (computers only, see core/menu/system.lua): audio device, sample rate and
-- buffer for jackd. the choice goes to ~/audio.conf, and the launcher (macos/norns.sh)
-- restarts jackd with it; if it does not start, the launcher falls back to the macOS
-- defaults and leaves audio.conf.failed.

local util = require 'util'

local CONF = "/home/we/audio.conf"
local FAILED = "/home/we/audio.conf.failed"
local MARK = "/home/we/.norns-restart-audio"
local RATES = {44100, 48000, 88200, 96000}
local PERIODS = {64, 128, 256, 512, 1024}
local ROWS = {"INPUT", "OUTPUT", "RATE", "BUFFER", "APPLY"}

local m = {
  pos = 1,
  inputs = {},  -- {uid=, name=}, first = the macOS default
  outputs = {},
  sel = {},     -- per row: index into its choices
  failed = false,
  applying = false,
}

local function read_conf(path)
  local c = {input = "", output = "", rate = 48000, period = 256}
  local f = io.open(path)
  if f then
    for line in f:lines() do
      local k, v = line:match("^(%w+)=(.*)$")
      if k == "rate" or k == "period" then c[k] = tonumber(v) or c[k]
      elseif k then c[k] = v end
    end
    f:close()
  end
  return c
end

local function devices()
  m.inputs = {{uid = "", name = "default"}}
  m.outputs = {{uid = "", name = "default"}}
  local tool = os.getenv("NORNS_AUDIO_TOOL")
  if tool == nil then return end
  local out = util.os_capture('"' .. tool .. '"', true) or ""
  for line in out:gmatch("[^\n]+") do
    local uid, name, ins, outs = line:match("^([^\t]*)\t([^\t]*)\t(%d+)\t(%d+)")
    if uid and uid ~= "" then
      if tonumber(ins) > 0 then table.insert(m.inputs, {uid = uid, name = name}) end
      if tonumber(outs) > 0 then table.insert(m.outputs, {uid = uid, name = name}) end
    end
  end
end

local function index_of(list, pred)
  for i, v in ipairs(list) do if pred(v) then return i end end
  return 1
end

local function choices(row)
  if row == 1 then return m.inputs
  elseif row == 2 then return m.outputs
  elseif row == 3 then return RATES
  elseif row == 4 then return PERIODS end
end

local function value_text(row)
  local i = m.sel[row]
  if row == 1 then return m.inputs[i].name
  elseif row == 2 then return m.outputs[i].name
  elseif row == 3 then return tostring(RATES[i])
  elseif row == 4 then
    local ms = PERIODS[i] / RATES[m.sel[3]] * 1000
    return string.format("%d  %.1fms", PERIODS[i], ms)
  end
  return ""
end

-- cut text (utf-8 aware) to fit w pixels
local function fit(s, w)
  if screen.text_extents(s) <= w then return s end
  local n = utf8.len(s) or #s
  while n > 1 do
    n = n - 1
    local cut = s:sub(1, (utf8.offset(s, n + 1) or (#s + 1)) - 1) .. ".."
    if screen.text_extents(cut) <= w then return cut end
  end
  return ".."
end

local function apply()
  local f = io.open(CONF, "w")
  if f == nil then return end
  f:write("input=" .. m.inputs[m.sel[1]].uid .. "\n")
  f:write("output=" .. m.outputs[m.sel[2]].uid .. "\n")
  f:write("rate=" .. RATES[m.sel[3]] .. "\n")
  f:write("period=" .. PERIODS[m.sel[4]] .. "\n")
  f:close()
  os.remove(FAILED)
  local mark = io.open(MARK, "w")
  if mark then mark:close() end
  m.applying = true
  _menu.redraw()
  _norns.restart()
end

m.init = function()
  devices()
  m.failed = util.file_exists(FAILED)
  local c = read_conf(m.failed and FAILED or CONF)
  m.sel[1] = index_of(m.inputs, function(d) return d.uid == c.input end)
  m.sel[2] = index_of(m.outputs, function(d) return d.uid == c.output end)
  m.sel[3] = index_of(RATES, function(r) return r == c.rate end)
  m.sel[4] = index_of(PERIODS, function(p) return p == c.period end)
  m.applying = false
end

m.deinit = norns.none

m.key = function(n, z)
  if z ~= 1 or m.applying then return end
  if n == 2 then
    _menu.set_page("SYSTEM")
  elseif n == 3 and ROWS[m.pos] == "APPLY" then
    apply()
  end
end

m.enc = function(n, delta)
  if m.applying then return end
  if n == 2 then
    m.pos = util.clamp(m.pos + delta, 1, #ROWS)
  elseif n == 3 and m.pos <= 4 then
    m.sel[m.pos] = util.clamp(m.sel[m.pos] + delta, 1, #choices(m.pos))
  end
  _menu.redraw()
end

m.redraw = function()
  screen.clear()
  for i, row in ipairs(ROWS) do
    screen.level(i == m.pos and 15 or 4)
    screen.move(0, 10 * i)
    screen.text(row)
    if i <= 4 then
      screen.move(127, 10 * i)
      screen.text_right(fit(value_text(i), 84))
    end
  end
  screen.level(m.applying and 10 or 2)
  screen.move(0, 62)
  if m.applying then
    screen.text("restarting audio.")
  elseif m.failed then
    screen.text("failed: back to default")
  else
    screen.text("K3 on APPLY restarts audio")
  end
  screen.update()
end

return m
