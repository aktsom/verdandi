-- SYSTEM > AUDIO in the Windows build (docs/port/phase-m3.md). The program (norns.exe) owns the sound card through PortAudio: WASAPI (shared mode, always there) or ASIO (only in the ASIO build, and
-- only when the driver is free). The choices go to ~/audio.conf and APPLY restarts norns (the launcher starts it again with them):
--   output=<uid>  input=<uid>  rate=  period=  out_first=  in_l=  in_r=     (uid: "wasapi:<name>" or "asio:<name>"; no output= line = the Windows default device)
-- rows: HOST OUTPUT OUT CH INPUT IN L IN R RATE BUFFER APPLY TEST, then three read-only numbers: LATENCY (what the driver reports + the block of the bridge to SuperCollider), MEASURED (TEST: a click goes
-- out and is heard on the input, so it needs a cable or TotalMix Loopback from the output back to an input) and LEVEL (the input). The bottom lines: what runs, or why it does not (plain words).
local util = require 'util'

local CONF = "/home/we/audio.conf"
local FAILED = "/home/we/audio.conf.failed"
local MARK = "/home/we/.norns-restart-audio"
local RATES = {44100, 48000, 88200, 96000}
local PERIODS = {64, 128, 256, 512, 1024}
local DEFAULT_PERIOD = 512 -- the safe default: 10.7 ms at 48 kHz; 128 and 256 are for the owner to try (underruns are counted and shown)
local ROWS = {"HOST", "OUTPUT", "OUT CH", "INPUT", "IN L", "IN R", "RATE", "BUFFER", "APPLY", "TEST", "LATENCY", "MEASURED", "LEVEL"}
local R = {HOST = 1, OUTPUT = 2, OUTCH = 3, INPUT = 4, INL = 5, INR = 6, RATE = 7, BUFFER = 8, APPLY = 9, TEST = 10, LATENCY = 11, MEASURED = 12, LEVEL = 13}
local VISIBLE = 5

local m = {pos = 1, top = 1, hosts = {}, devs = {}, sel = {}, extra = {}, failed = false, applying = false}

local function read_conf(path)
  local c = {input = "", output = "", rate = 48000, period = DEFAULT_PERIOD, out_first = 1, in_l = 1, in_r = 2, extra = {}}
  local f = io.open(path)
  if f then
    for line in f:lines() do
      local k, v = line:match("^([%w_]+)=(.*)$")
      if k == "rate" or k == "period" or k == "out_first" or k == "in_l" or k == "in_r" then c[k] = tonumber(v) or c[k]
      elseif k == "input" or k == "output" then c[k] = v
      elseif k then table.insert(c.extra, line) end
    end
    f:close()
  end
  return c
end

-- the device list of the program: uid, name, inputs, outputs, api, low_out_ms, low_in_ms, loopback
local function read_devices()
  m.devs = {}
  for line in (_norns.audio_devices() or ""):gmatch("[^\n]+") do
    local f = {}
    for v in (line .. "\t"):gmatch("([^\t]*)\t") do f[#f + 1] = v end
    if f[1] and f[1] ~= "" then
      table.insert(m.devs, {uid = f[1], name = f[2] or f[1], ins = tonumber(f[3]) or 0, outs = tonumber(f[4]) or 0, api = f[5] or "WASAPI",
        low_out = tonumber(f[6]) or 0, low_in = tonumber(f[7]) or 0, loopback = f[8] == "1"})
    end
  end
  -- the host APIs of this build: WASAPI always, ASIO only in the ASIO build
  m.hosts = {"WASAPI"}
  local info = _norns.audio_info()
  if info and (info.host_apis or ""):find("ASIO", 1, true) then table.insert(m.hosts, "ASIO") end
end

local function host() return m.hosts[m.sel[R.HOST]] or "WASAPI" end

local function outputs()
  local l = {}
  if host() == "WASAPI" then table.insert(l, {uid = "", name = "default", outs = 2}) end
  for _, d in ipairs(m.devs) do
    if d.api == host() and d.outs > 0 then table.insert(l, d) end
  end
  return l
end

local function out_dev() return outputs()[m.sel[R.OUTPUT]] or {uid = "", name = "default", outs = 2} end

-- ASIO takes its input from the device of the output (one driver, one stream); WASAPI can use any capture device
local function inputs()
  local l = {{uid = "", name = "none", ins = 0}}
  if host() == "ASIO" then
    local o = out_dev()
    if o.uid ~= "" and (o.ins or 0) > 0 then table.insert(l, o) end
  else
    for _, d in ipairs(m.devs) do
      if d.api == "WASAPI" and d.ins > 0 and not d.loopback then table.insert(l, d) end
    end
  end
  return l
end

local function in_dev() return inputs()[m.sel[R.INPUT]] or {uid = "", name = "none", ins = 0} end

-- first channel of the output pair: ASIO has many outputs (1+2, 3+4 ...), WASAPI one pair
local function outch_list()
  local l, o = {}, out_dev()
  local n = host() == "ASIO" and (o.outs or 2) or 2
  for first = 1, math.max(1, n - 1), 2 do table.insert(l, first) end
  if #l == 0 then l = {1} end
  return l
end

local function inch_list()
  local n = in_dev().ins or 0
  local l = {}
  for c = 1, math.max(n, 1) do l[c] = c end
  return l
end

local function choices(row)
  if row == R.HOST then return m.hosts
  elseif row == R.OUTPUT then return outputs()
  elseif row == R.OUTCH then return outch_list()
  elseif row == R.INPUT then return inputs()
  elseif row == R.INL or row == R.INR then return inch_list()
  elseif row == R.RATE then return RATES
  elseif row == R.BUFFER then return PERIODS end
end

local function fix_sel()
  for _, row in ipairs({R.OUTPUT, R.OUTCH, R.INPUT, R.INL, R.INR}) do
    local n = #choices(row)
    m.sel[row] = util.clamp(m.sel[row] or 1, 1, math.max(n, 1))
  end
end

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

local function ms(x) return string.format("%.0f", x) end

local function latency_text(info)
  if not info or info.mode ~= "device" then return "no sound card" end
  local t = "out " .. ms(info.out_latency_ms)
  if info.in_active then t = t .. " in " .. ms(info.in_latency_ms) end
  return t .. " +" .. ms(info.engine_ms) .. " ms"
end

local function value_text(row)
  local info = _norns.audio_info()
  local i = m.sel[row]
  if row == R.HOST then return host()
  elseif row == R.OUTPUT then return outputs()[i].name
  elseif row == R.OUTCH then
    local f = outch_list()[i]
    return f .. "+" .. (f + 1)
  elseif row == R.INPUT then return inputs()[i].name
  elseif row == R.INL or row == R.INR then
    if (in_dev().ins or 0) == 0 then return "-" end
    return tostring(inch_list()[i])
  elseif row == R.RATE then return tostring(RATES[i])
  elseif row == R.BUFFER then
    return string.format("%d  %.1fms", PERIODS[i], PERIODS[i] / RATES[m.sel[R.RATE]] * 1000)
  elseif row == R.APPLY then return ""
  elseif row == R.TEST then return ""
  elseif row == R.LATENCY then return latency_text(info)
  elseif row == R.MEASURED then
    if not info or info.measured_ms == -1 then return "press TEST"
    elseif info.measured_ms == -2 then return "no signal"
    else return ms(info.measured_ms) .. " ms" end
  elseif row == R.LEVEL then
    if not info or info.input == "off" or not info.in_active then return "input off" end
    if info.peak_db <= -100 then return "silent" end
    return string.format("%.0f dB", info.peak_db)
  end
  return ""
end

local function apply()
  local f = io.open(CONF, "w")
  if f == nil then return end
  for _, line in ipairs(m.extra) do f:write(line .. "\n") end
  local o, inp = out_dev(), in_dev()
  f:write("input=" .. inp.uid .. "\n")
  -- "default" is no output= line at all: the program then follows the Windows default device, whichever it is at the time
  if o.uid ~= "" then f:write("output=" .. o.uid .. "\n") end
  f:write("rate=" .. RATES[m.sel[R.RATE]] .. "\n")
  f:write("period=" .. PERIODS[m.sel[R.BUFFER]] .. "\n")
  f:write("out_first=" .. outch_list()[m.sel[R.OUTCH]] .. "\n")
  f:write("in_l=" .. inch_list()[m.sel[R.INL]] .. "\n")
  f:write("in_r=" .. inch_list()[m.sel[R.INR]] .. "\n")
  f:close()
  os.remove(FAILED)
  local mark = io.open(MARK, "w")
  if mark then mark:close() end
  m.applying = true
  _menu.redraw()
  _norns.restart()
end

local timer
m.init = function()
  read_devices()
  m.failed = util.file_exists(FAILED)
  local c = read_conf(m.failed and FAILED or CONF)
  m.extra = c.extra
  local function index_of(list, pred)
    for i, v in ipairs(list) do if pred(v) then return i end end
    return 1
  end
  -- the host is the one of the stored output (or input); WASAPI when there is none
  local uid = c.output ~= "" and c.output or c.input
  local h = uid:match("^(%a+):") == "asio" and "ASIO" or "WASAPI"
  m.sel[R.HOST] = index_of(m.hosts, function(x) return x == h end)
  m.sel[R.OUTPUT] = 1
  m.sel[R.OUTPUT] = index_of(outputs(), function(d) return d.uid == c.output end)
  m.sel[R.OUTCH] = 1
  m.sel[R.INPUT] = 1
  m.sel[R.INPUT] = index_of(inputs(), function(d) return d.uid == c.input end)
  m.sel[R.INL], m.sel[R.INR] = 1, 1
  fix_sel()
  m.sel[R.OUTCH] = index_of(outch_list(), function(f) return f == c.out_first end)
  m.sel[R.INL] = index_of(inch_list(), function(x) return x == c.in_l end)
  m.sel[R.INR] = index_of(inch_list(), function(x) return x == c.in_r end)
  m.sel[R.RATE] = index_of(RATES, function(r) return r == c.rate end)
  m.sel[R.BUFFER] = index_of(PERIODS, function(p) return p == c.period end)
  m.applying = false
  m.pos, m.top = 1, 1
  -- the level and the measurement change while the page is open
  if metro and metro.init and not timer then
    timer = metro.init(function() if not m.applying then _menu.redraw() end end, 0.25, -1)
  end
  if timer then timer:start() end
end

m.deinit = function() if timer then timer:stop() end end

m.key = function(n, z)
  if z ~= 1 or m.applying then return end
  if n == 2 then
    _menu.set_page("SYSTEM")
  elseif n == 3 and m.pos == R.APPLY then
    apply()
  elseif n == 3 and m.pos == R.TEST then
    _norns.audio_measure()
    _menu.redraw()
  end
end

m.enc = function(n, delta)
  if m.applying then return end
  if n == 2 then
    m.pos = util.clamp(m.pos + delta, 1, #ROWS)
    if m.pos < m.top then m.top = m.pos end
    if m.pos > m.top + VISIBLE - 1 then m.top = m.pos - VISIBLE + 1 end
  elseif n == 3 and m.pos <= R.BUFFER then
    local row = m.pos
    local c = choices(row)
    local before = m.sel[row]
    m.sel[row] = util.clamp(m.sel[row] + delta, 1, math.max(#c, 1))
    if m.sel[row] ~= before then
      -- a new host or device: what depends on it starts again from its first entry
      if row == R.HOST then m.sel[R.OUTPUT], m.sel[R.OUTCH], m.sel[R.INPUT] = 1, 1, 1
      elseif row == R.OUTPUT then m.sel[R.OUTCH] = 1; m.sel[R.INPUT] = 1 end
      if row == R.HOST or row == R.OUTPUT or row == R.INPUT then m.sel[R.INL], m.sel[R.INR] = 1, math.min(2, #inch_list()) end
      fix_sel()
    end
  end
  _menu.redraw()
end

-- the plain words under the list: why there is no sound, or what runs
local function bottom(info)
  if m.applying then return "restarting audio.", 10 end
  if m.failed then return "failed: back to default", 15 end
  if not info then return "", 2 end
  if info.mode == "fallback" then
    if info.note:find("busy", 1, true) then return "no sound: device busy, null audio", 15 end
    if info.note:find("not found", 1, true) then return "no sound: device missing, null audio", 15 end
    return "no sound: null audio", 15
  end
  if info.note ~= "" then return info.note, 15 end
  if info.mode == "device" then
    local t = info.device .. " " .. info.host_api:gsub("^Windows ", "")
    return "playing: " .. t, 2
  end
  return string.format("null audio (silent) %d Hz", info.rate), 2
end

m.redraw = function()
  screen.clear()
  local info = _norns.audio_info()
  for k = 0, VISIBLE - 1 do
    local i = m.top + k
    if ROWS[i] then
      local y = 8 + 9 * k
      screen.level(i == m.pos and 15 or 4)
      screen.move(0, y)
      screen.text(ROWS[i])
      screen.move(127, y)
      screen.text_right(fit(value_text(i), 84))
    end
  end
  -- the second line: the counts of the stream or the hint for the row
  screen.level(2)
  screen.move(0, 53)
  local hint
  if m.pos == R.APPLY then hint = "K3 restarts audio"
  elseif m.pos == R.TEST then hint = "K3: click out, heard in"
  elseif info and info.mode == "device" then
    hint = string.format("%d Hz  %d frames  under %d  xrun %d", info.rate, info.frames, info.underruns, info.xruns or 0)
  else hint = "" end
  screen.text(fit(hint, 128))
  local text, level = bottom(info)
  screen.level(level)
  screen.move(0, 62)
  screen.text(fit(text, 128))
  screen.update()
end

return m
