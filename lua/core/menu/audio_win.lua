-- SYSTEM > AUDIO in the Windows build (docs/port/phase-m3.md). One short list as on a norns: E2 selects a row, E3 changes it, K2 goes back. Every change applies at once (about a second after the last
-- turn of E3): only the sound stream is reopened, norns and the running script are not restarted. Rows:
--   DRIVER   normal (WASAPI shared: works next to other programs)   exclusive (WASAPI: lowest delay Windows allows, nobody else can use the device)   low latency (ASIO, only in the ASIO build)
--   OUTPUT   the device (normal / exclusive: "default" follows Windows; low latency: the ASIO driver)
--   OUT CH   (low latency only) which output pair
--   INPUT    none, or the input device (low latency: the same driver); the input is always OFF at the start, the MIC button switches it on
--   IN CH    (when an input is chosen) which input channels are left and right
--   BUFFER   auto = the card's own period (the safe choice), or a block of 64 to 512 frames
--   TEST     K3: a click goes out and is listened for on the input
-- under the list ONE short status line: estimated delay of an engine sound, u = scsynth late for a block, x = glitches of the card ("34 ms  u0 x0"); details go to norns.log every 10 s.
local util = require 'util'
local winui = require 'core/menu/winui'

local CONF = "/home/we/audio.conf"
local FAILED = "/home/we/audio.conf.failed"
local BUFFERS = {0, 64, 128, 256, 512}
local ROWS_SHOWN = 6
local APPLY_AFTER = 4 -- redraw ticks (4 a second) after the last change before the stream is reopened

local m = {pos = 1, top = 1, tick = 0, extra = {}, devs = {}, hosts = {}, cfg = {}, pending = nil, status = nil, status_until = 0, test = nil, testing = false}

-- ---- the device list of the program: uid, name, inputs, outputs, api, low_out_ms, low_in_ms, loopback ----
local function read_devices()
  m.devs = {}
  for line in (_norns.audio_devices() or ""):gmatch("[^\n]+") do
    local f = {}
    for v in (line .. "\t"):gmatch("([^\t]*)\t") do f[#f + 1] = v end
    if f[1] and f[1] ~= "" then
      table.insert(m.devs, {uid = f[1], name = (f[2] or f[1]):gsub(" %(default%)$", ""), ins = tonumber(f[3]) or 0, outs = tonumber(f[4]) or 0, api = f[5] or "WASAPI", loopback = f[8] == "1"})
    end
  end
  m.hosts = {"WASAPI"}
  local info = _norns.audio_info()
  if info and (info.host_apis or ""):find("ASIO", 1, true) then table.insert(m.hosts, "ASIO") end
end

local function has_asio() return m.hosts[2] == "ASIO" end

-- ---- the settings: what runs (info.config), or the file ----
local function parse(text)
  local c = {output = "", input = "", buffer = 0, exclusive = 0, out_first = 1, in_l = 1, in_r = 2, rate = 48000, block = 128, extra = {}}
  for line in (text or ""):gmatch("[^\r\n]+") do
    local k, v = line:match("^([%w_]+)=(.*)$")
    if k == "buffer" then c.buffer = v == "auto" and 0 or (tonumber(v) or 0)
    elseif k == "exclusive" or k == "out_first" or k == "in_l" or k == "in_r" or k == "rate" then c[k] = tonumber(v) or c[k]
    elseif k == "block" then c.block = tonumber(v) or c.block
    elseif k == "output" or k == "input" then c[k] = v
    elseif k == "period" then -- the key of versions up to 0.3: not used any more
    elseif k then table.insert(c.extra, line) end -- keys that are not ours stay in the file
  end
  return c
end

local function read_file(path)
  local f = io.open(path)
  if not f then return "" end
  local t = f:read("a")
  f:close()
  return t or ""
end

local function driver_of(c)
  if c.output:match("^asio:") or c.input:match("^asio:") then return "asio" end
  if c.exclusive == 1 then return "exclusive" end
  return "normal"
end

-- ---- the lists ----
local function drivers()
  local l = {{id = "normal", name = "normal"}, {id = "exclusive", name = "exclusive"}}
  if has_asio() then table.insert(l, {id = "asio", name = "low latency"}) end
  return l
end

local function outputs()
  local l = {}
  if m.cfg.driver ~= "asio" then table.insert(l, {uid = "", name = "default", outs = 2}) end
  for _, d in ipairs(m.devs) do
    if d.outs > 0 and ((m.cfg.driver == "asio") == (d.api == "ASIO")) then table.insert(l, d) end
  end
  return l
end

local function cur_out()
  for _, d in ipairs(outputs()) do if d.uid == m.cfg.output then return d end end
  return outputs()[1] or {uid = "", name = "default", outs = 2}
end

local function inputs()
  local l = {{uid = "", name = "none", ins = 0}}
  if m.cfg.driver == "asio" then
    local o = cur_out()
    if o.uid ~= "" and (o.ins or 0) > 0 then table.insert(l, o) end
  else
    for _, d in ipairs(m.devs) do
      if d.api == "WASAPI" and d.ins > 0 and not d.loopback then table.insert(l, d) end
    end
  end
  return l
end

local function cur_in()
  for _, d in ipairs(inputs()) do if d.uid == m.cfg.input then return d end end
  return inputs()[1]
end

-- the output pair (low latency): 1+2, 3+4 ...
local function outpairs()
  local l, n = {}, cur_out().outs or 2
  for first = 1, math.max(1, n - 1), 2 do table.insert(l, {first = first, name = first .. "+" .. (first + 1)}) end
  return l
end

-- the input channels: pairs (1+2, 3+4 ...), then single channels heard on both sides ("3 mono")
local function inpairs()
  local n, l = cur_in().ins or 0, {}
  for first = 1, n - 1, 2 do table.insert(l, {l = first, r = first + 1, name = first .. "+" .. (first + 1)}) end
  for c = 1, n do table.insert(l, {l = c, r = c, name = c .. " mono"}) end
  if #l == 0 then l = {{l = 1, r = 2, name = "1+2"}} end
  return l
end

local function index_where(list, pred)
  for i, v in ipairs(list) do if pred(v) then return i end end
  return 1
end

-- ---- the rows, as they are now ----
local function rows()
  local r = {"DRIVER", "OUTPUT"}
  if m.cfg.driver == "asio" then table.insert(r, "OUT CH") end
  table.insert(r, "INPUT")
  if m.cfg.input ~= "" then table.insert(r, "IN CH") end
  table.insert(r, "BUFFER")
  table.insert(r, "TEST")
  return r
end

local function buffer_text(b)
  if b == 0 then return "auto" end
  return string.format("%d  %.1f ms", b, b / (m.cfg.rate or 48000) * 1000)
end

local function say(text, secs)
  m.status, m.status_until = text, m.tick + (secs or 24) * 4
end

local function value_text(row)
  if row == "DRIVER" then
    for _, d in ipairs(drivers()) do if d.id == m.cfg.driver then return d.name end end
    return "normal"
  elseif row == "OUTPUT" then return cur_out().name
  elseif row == "OUT CH" then return outpairs()[index_where(outpairs(), function(p) return p.first == m.cfg.out_first end)].name
  elseif row == "INPUT" then return cur_in().name
  elseif row == "IN CH" then
    local p = inpairs()[index_where(inpairs(), function(q) return q.l == m.cfg.in_l and q.r == m.cfg.in_r end)]
    return p.name
  elseif row == "BUFFER" then return buffer_text(m.cfg.buffer)
  elseif row == "TEST" then
    if m.testing then
      local info = _norns.audio_info()
      local ms = info and info.measured_ms or -1
      if ms == -2 then
        m.testing, m.test = false, "no click heard"
        say("no click heard (is an output wired to the input?)", 60)
      elseif ms >= 0 then
        m.testing, m.test = false, string.format("%.0f ms", ms)
        say(string.format("round trip %.0f ms (click out, heard in)", ms), 60)
      else return "listening..." end
    end
    return m.test or "K3: click out, heard in"
  end
  return ""
end

-- ---- the file and the apply ----
local function conf_text(c)
  local t = {}
  for _, line in ipairs(m.extra) do t[#t + 1] = line end
  if c.output ~= "" then t[#t + 1] = "output=" .. c.output end
  t[#t + 1] = "input=" .. c.input
  t[#t + 1] = "rate=" .. c.rate
  t[#t + 1] = "block=" .. c.block
  t[#t + 1] = "buffer=" .. (c.buffer == 0 and "auto" or c.buffer)
  t[#t + 1] = "exclusive=" .. (c.driver == "exclusive" and 1 or 0)
  t[#t + 1] = "out_first=" .. c.out_first
  t[#t + 1] = "in_l=" .. c.in_l
  t[#t + 1] = "in_r=" .. c.in_r
  return table.concat(t, "\n") .. "\n"
end

-- the plain short line for a reason the program gave (the whole sentence is in norns.log and on the window)
local function short(msg)
  msg = msg or ""
  if msg:find("busy", 1, true) then return "busy: another program has it" end
  if msg:find("not found", 1, true) then return "device not found" end
  if msg:find("Hz", 1, true) then return (msg:match("runs at (%d+ Hz)") and ("needs " .. msg:match("runs at (%d+ Hz)")) or "wrong sample rate") end
  if msg:find("exclusive", 1, true) then return "exclusive refused: normal mode" end
  if msg:find("Using WASAPI", 1, true) then return "ASIO busy: using normal driver" end
  if msg ~= "" then return "could not open it" end
  return ""
end


local function from_running()
  local info = _norns.audio_info()
  local c = parse(info and info.config or read_file(CONF))
  c.driver = driver_of(c)
  m.cfg = c
  m.extra = parse(read_file(CONF)).extra
end

-- reopen the stream with the choices now on the page
local function apply()
  m.pending = nil
  local want = m.cfg
  say("applying...", 30)
  if _menu and _menu.redraw then _menu.redraw() end
  local rc, msg = _norns.audio_apply(conf_text(want))
  if rc == 0 then
    local f = io.open(CONF, "w")
    if f then f:write(conf_text(want)) f:close() end
    os.remove(FAILED)
    local asked_driver = want.driver
    from_running() -- what really runs (a busy ASIO driver may have become the normal driver)
    local row = m.changed_row or "AUDIO"
    local what = row .. (row == "AUDIO" and "" or (" " .. (value_text(row) or "")))
    local detail = (msg or ""):match("refused %((.-)%): normal")
    if detail and asked_driver == "exclusive" then
      -- the exact reason, once: it is also written to norns.log, and audio.conf no longer asks for exclusive on every start
      say("exclusive refused: " .. detail .. " - normal mode is used", 60)
    elseif short(msg) ~= "" then
      say(what .. " applied; " .. short(msg), 40)
    elseif row == "OUTPUT" then
      say(what .. " applied (pairs on the interface may not be wired to anything)", 40)
    else
      say(what .. " applied", 20)
    end
  else
    -- it did not work: the page shows what runs again, and says why in one line
    local why = short(msg)
    from_running()
    say(why ~= "" and why or (rc == 2 and "no sound: silence" or "could not open it"), 40)
  end
  if _menu and _menu.show_note and _menu.set_input then
    -- a new device: the input is OFF again (the button state follows)
    _menu.set_input("off", nil, nil, true)
  end
  print("audio: AUDIO page: " .. (rc == 0 and "applied" or (rc == 1 and "reverted" or "silence")) .. (msg ~= "" and (": " .. msg) or ""))
end

local timer
m.init = function()
  read_devices()
  from_running()
  m.pos, m.top, m.tick, m.pending, m.test, m.testing = 1, 1, 0, nil, nil, false
  m.status = nil
  local failed = util.file_exists(FAILED)
  if failed then say("failed: back to default", 40) end
  if metro and metro.init and not timer then
    timer = metro.init(function() m.timer() end, 0.25, -1)
  end
  if timer then timer:start() end
end

-- every quarter of a second while the page is open: the marquee, the pending apply, the numbers
m.timer = function()
  m.tick = m.tick + 1
  if m.pending and m.tick >= m.pending then apply() end
  if _menu and _menu.redraw then _menu.redraw() end
end

m.deinit = function()
  if timer then timer:stop() end
  if m.pending then apply() end
end

m.key = function(n, z)
  if z ~= 1 then return end
  if n == 2 then
    _menu.set_page("SYSTEM")
  elseif n == 3 and rows()[m.pos] == "TEST" then
    local info = _norns.audio_info()
    if not info or info.mode ~= "device" then
      m.test, m.testing = "no sound card", false
      say("no sound card is running (see the status line)", 60)
    elseif not info.in_active then
      if m.cfg.input == "" then
        m.test, m.testing = "no input selected", false
        say("no input selected: choose one on INPUT", 60)
      else
        m.test, m.testing = "input not open", false
        say("the input did not open: choose it again on INPUT", 60)
      end
    else
      m.test, m.testing = nil, true
      _norns.audio_measure()
    end
    _menu.redraw()
  end
end

local function changed(row)
  m.pending = m.tick + APPLY_AFTER
  m.status = nil
  m.changed_row = row -- for the confirmation: "BUFFER 256 applied"
end

local function step(list, i, delta) return util.clamp(i + delta, 1, #list) end

m.enc = function(n, delta)
  if n == 2 then
    local r = rows()
    if m.pending then apply() end -- leaving a row: what was changed runs now
    m.pos = util.clamp(m.pos + delta, 1, #r)
    if m.pos < m.top then m.top = m.pos end
    if m.pos > m.top + ROWS_SHOWN - 1 then m.top = m.pos - ROWS_SHOWN + 1 end
    m.tick = 0
  elseif n == 3 then
    local row = rows()[m.pos]
    local c = m.cfg
    if row == "DRIVER" then
      local l = drivers()
      local i = step(l, index_where(l, function(d) return d.id == c.driver end), delta)
      if l[i].id ~= c.driver then
        c.driver, c.output, c.input, c.out_first, c.in_l, c.in_r, c.buffer = l[i].id, "", "", 1, 1, 2, 0
        if c.driver == "asio" then local o = outputs()[1]; c.output = o and o.uid or "" end
        changed("DRIVER")
      end
    elseif row == "OUTPUT" then
      local l = outputs()
      local i = step(l, index_where(l, function(d) return d.uid == c.output end), delta)
      if l[i].uid ~= c.output then
        c.output, c.out_first = l[i].uid, 1
        if c.driver == "asio" then c.input = "" end
        changed("OUTPUT")
      end
    elseif row == "OUT CH" then
      local l = outpairs()
      local i = step(l, index_where(l, function(p) return p.first == c.out_first end), delta)
      if l[i].first ~= c.out_first then c.out_first = l[i].first; changed("OUT CH") end
    elseif row == "INPUT" then
      local l = inputs()
      local i = step(l, index_where(l, function(d) return d.uid == c.input end), delta)
      if l[i].uid ~= c.input then c.input, c.in_l, c.in_r = l[i].uid, 1, math.min(2, math.max(1, l[i].ins or 1)); changed("INPUT") end
    elseif row == "IN CH" then
      local l = inpairs()
      local i = step(l, index_where(l, function(p) return p.l == c.in_l and p.r == c.in_r end), delta)
      if l[i].l ~= c.in_l or l[i].r ~= c.in_r then c.in_l, c.in_r = l[i].l, l[i].r; changed("IN CH") end
    elseif row == "BUFFER" then
      local i = step(BUFFERS, index_where(BUFFERS, function(b) return b == c.buffer end), delta)
      if BUFFERS[i] ~= c.buffer then c.buffer = BUFFERS[i]; changed("BUFFER") end
    end
    m.tick = 0
  end
  _menu.redraw()
end

-- one short status line: what is wrong, or the numbers
local function status_line(info)
  if m.pending then return "..." end
  if m.status and m.tick < m.status_until then return m.status end
  if not info then return "" end
  if info.mode == "fallback" then
    return (info.note:find("busy", 1, true) and "no sound: device busy") or (info.note:find("not found", 1, true) and "no sound: device missing") or "no sound"
  elseif info.mode ~= "device" then
    return "null audio (silent)"
  end
  local line = string.format("%.0f ms  u%d x%d", info.total_ms or 0, info.underruns or 0, info.xruns or 0)
  -- the rate the card itself runs at, when it is not norns's own (shared mode: Windows converts; exclusive and ASIO: the clock of the card)
  if (info.device_rate or 0) > 0 and math.floor(info.device_rate + 0.5) ~= info.rate then
    line = line .. string.format("  card %d Hz", math.floor(info.device_rate + 0.5))
  end
  return line
end

m.redraw = function()
  screen.clear()
  local info = _norns.audio_info()
  local r = rows()
  for k = 0, ROWS_SHOWN - 1 do
    local i = m.top + k
    if r[i] then winui.row(8 + 9 * k, r[i], value_text(r[i]), i == m.pos, m.tick) end
  end
  screen.level(15)
  screen.move(2, 62)
  screen.text(winui.fit(status_line(info), 124, true, m.tick)) -- a longer sentence runs slowly (the same marquee as on the selected row)
  screen.update()
end

-- at the start: exclusive mode was asked for in audio.conf but the device refused it. the reason is written once to norns.log and audio.conf says exclusive=0 from now on, so that it is not tried (and
-- refused) again on every start. called by lua/core/menu.lua after the start-up
m.forget_exclusive = function(info)
  info = info or _norns.audio_info()
  if not info or not (info.note or ""):find("exclusive mode was refused", 1, true) then return false end
  local text = read_file(CONF)
  if not text:find("exclusive=1", 1, true) then return false end
  local f = io.open(CONF, "w")
  if not f then return false end
  f:write((text:gsub("exclusive=1", "exclusive=0")))
  f:close()
  print("audio: " .. info.note)
  print("audio: audio.conf now says exclusive=0 (it will not be asked for again at every start; choose DRIVER exclusive on the AUDIO page to try again)")
  return true
end

-- the numbers of the last ten seconds, for norns.log (called by lua/core/menu.lua every 10 s)
m.log_line = function(prev)
  local info = _norns.audio_info()
  if not info then return nil end
  local line = string.format("audio: %s %s %s | norns %d Hz (device %d Hz) engine block %d card %d hold-back %d (grew %d x) | delay ~%.1f ms (out %.1f in %.1f engine %.1f) | scsynth late %d (+%d) glitches %d (+%d) input %s level %.0f dB",
    info.mode, info.host_api ~= "" and info.host_api or "-", info.device ~= "" and info.device or "-", info.rate, math.floor((info.device_rate or 0) + 0.5), info.frames, info.card_frames or 0, info.engine_lag or 0, info.lag_raises or 0, info.total_ms or 0, info.out_latency_ms,
    info.in_latency_ms, info.engine_ms or 0, info.underruns, info.underruns - ((prev or {}).underruns or 0), info.xruns or 0, (info.xruns or 0) - ((prev or {}).xruns or 0), info.input, info.peak_db or -120)
  return line, info
end

return m
