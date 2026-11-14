-- SYSTEM > AUDIO in the Windows build (docs/port/phase-m3.md, "UI rule"). ONE rule, the same on every Windows page that has a setting to apply:
--   E2 selects a row.  E3 CHOOSES a value: the row shows it at once with a * at its end (the help says "K3 applies").  K3 APPLIES it: the mark is .. while it works and ok after.  K2 leaves and never applies anything.
-- a boxed help of at most three short lines for the selected row only; messages belong to the row and go when E2 moves; TEST shows its result on its own row. Rows:
--   DRIVER   normal (WASAPI shared: works next to other programs)   exclusive (WASAPI: lowest delay Windows allows, nobody else can use the device)   low latency (ASIO, only in the ASIO build)
--   OUTPUT   the device ("default" follows Windows)      OUT CH   (low latency only) which output pair
--   INPUT    none, or the input device (low latency: the same driver); always OFF at the start, the MIC button switches it on      IN CH   (when an input is chosen) left and right
--   BUFFER   auto = the card's own period (the safe choice), or a block of 64 to 512 frames      TEST   K3: a click out and listened for, or without an input a 2 second self-test
-- under the list ONE short status line: mode, estimated delay of an engine sound, u = scsynth late for a block, x = glitches of the card ("normal  41 ms  u0 x0"); details go to norns.log every 10 s.
local util = require 'util'
local winui = require 'core/menu/winui'

local CONF = "/home/we/audio.conf"
local FAILED = "/home/we/audio.conf.failed"
local BUFFERS = {0, 64, 128, 256, 512}
local ROWS_SHOWN = winui.ROWS -- the rows of a list (winui.lua); under them the status line and the info area at the bottom

local m = {pos = 1, top = 1, tick = 0, extra = {}, devs = {}, hosts = {}, cfg = {}, run = {}, busy = false, status = nil, status_until = 0, test = nil, testing = false}

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
  m.status, m.status_until, m.status_start = text, m.tick + (secs or 24) * 4, m.tick
end

-- the help of a row, in plain words: what the info area at the bottom shows for the selected row when the row's own text is not cut (winui.info wraps it over two lines)
local HELP = {
  DRIVER = "normal shares the card with other programs; exclusive: fastest, alone",
  OUTPUT = "where the sound goes; default follows Windows. some pairs may be unwired",
  ["OUT CH"] = "which two outputs of the ASIO driver",
  INPUT = "sound in; none = off. the MIC button turns it on; SYS needs no input",
  ["IN CH"] = "left and right input channels; 3 mono = channel 3 on both sides",
  BUFFER = "auto is safest; smaller = less delay, more risk of clicks",
  TEST = "K3 sends a click out and listens on the input; no input: a 2 s self-test",
}
-- the text: a chosen value that is not applied yet says what the mark means, first
m.help_text = function(row)
  local h = HELP[row]
  if not h then return nil end
  if row == "INPUT" then
    local inf = _norns.audio_info()
    if inf and inf.sys_available == false then h = "sound in; none = off. SYS: needs WASAPI loopback (not available)" end
  end
  if m.pending and m.pending(row) then h = "* chosen: K3 applies. " .. h end
  return h
end
-- the two lines as drawn (a test reads them)
m.help = function(row)
  local t = m.help_text(row)
  if not t then return nil end
  return winui.wrap2(t, winui.INFO_W)
end
m.help_lines = function() return m.help(rows()[m.pos]) or {} end

local SELFTEST_SHORT = {[0] = "ok", "no card", "no scsynth", "card late", "engine late", "glitches"}
local SELFTEST_LINE = {[0] = "self-test ok", "self-test: no card", "self-test: no scsynth", "self-test: card late", "self-test: engine late", "self-test: glitches"}
-- the details of the self-test go to norns.log, the status line only gets the short result
local function selftest_details(t, why)
  local v = t.verdict
  local text
  if v == 0 then
    text = string.format("self-test ok: card calls every %.1f ms (longest %.1f), engine answered %d blocks, %d late, %d glitches", t.avg_ms, t.max_ms, t.engine_blocks, t.late, t.glitches)
  elseif v == 1 then text = "self-test: no sound card is running"
  elseif v == 2 then text = "self-test: SuperCollider is not attached to norns yet (wait a moment, or restart)"
  elseif v == 3 then text = string.format("self-test: the card calls late (longest %.0f ms, should be %.0f)", t.max_ms, t.expect_ms)
  elseif v == 4 then text = string.format("self-test: the engine was late %d times: raise BUFFER or close other programs", t.late)
  else text = string.format("self-test: the card glitched %d times: try a larger BUFFER", t.glitches) end
  if why then text = text .. " (" .. why .. ")" end
  return text
end

local function value_text(row)
  if row == "DRIVER" then
    for _, d in ipairs(drivers()) do if d.id == m.cfg.driver then return d.name end end
    return "normal"
  elseif row == "OUTPUT" then return cur_out().name
  elseif row == "OUT CH" then return outpairs()[index_where(outpairs(), function(p) return p.first == m.cfg.out_first end)].name
  elseif row == "INPUT" then
    local n = cur_in().name
    local inf = _norns.audio_info()
    if m.cfg.input ~= "" and inf and inf.mode == "device" and not inf.in_active then n = n .. " (not open)" end
    return n
  elseif row == "IN CH" then
    local p = inpairs()[index_where(inpairs(), function(q) return q.l == m.cfg.in_l and q.r == m.cfg.in_r end)]
    return p.name
  elseif row == "BUFFER" then return buffer_text(m.cfg.buffer)
  elseif row == "TEST" then
    if m.selftesting then
      local t = _norns.audio_selftest()
      if t and t.state == 2 then
        m.selftesting = false
        m.test = SELFTEST_SHORT[t.verdict] or "?"
        say(SELFTEST_LINE[t.verdict] or "self-test: ?", 60)
        print("audio: " .. selftest_details(t, m.selftest_why))
      else
        return "testing..."
      end
    elseif m.testing then
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
    return m.test or "K3: test"
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


local function copy(c)
  local t = {}
  for k, v in pairs(c) do t[k] = v end
  return t
end

local function from_running()
  local info = _norns.audio_info()
  local c = parse(info and info.config or read_file(CONF))
  c.driver = driver_of(c)
  m.cfg = c
  m.run = copy(c) -- what runs: the pending choices are the differences
  m.extra = parse(read_file(CONF)).extra
end

-- the rows whose chosen value is not what runs (they say "K3 apply")
local function pending(row)
  local c, r = m.cfg, m.run
  if row == "DRIVER" then return c.driver ~= r.driver
  elseif row == "OUTPUT" then return c.output ~= r.output
  elseif row == "OUT CH" then return c.out_first ~= r.out_first
  elseif row == "INPUT" then return c.input ~= r.input
  elseif row == "IN CH" then return c.in_l ~= r.in_l or c.in_r ~= r.in_r
  elseif row == "BUFFER" then return c.buffer ~= r.buffer end
  return false
end
local function any_pending()
  for _, row in ipairs(rows()) do if pending(row) then return true end end
  return false
end
m.pending = pending

-- messages belong to the row: E2 clears them (and the 'applied' mark and the result of TEST)
local function clear_row_messages()
  m.status, m.applied_row, m.test = nil, nil, nil
  if not m.testing and not m.selftesting then m.test = nil end
end

-- K3: reopen the stream with the choices now on the page. the row says applying... meanwhile, then applied (or the reason it was not)
local function apply()
  local want = m.cfg
  local sel = rows()[m.pos]
  local row = pending(sel) and sel or nil
  if not row then
    for _, r in ipairs(rows()) do if pending(r) then row = r break end end
  end
  m.busy, m.status = true, nil
  _menu.redraw()
  local rc, msg = _norns.audio_apply(conf_text(want))
  m.busy = false
  if rc == 0 then
    local f = io.open(CONF, "w")
    if f then f:write(conf_text(want)) f:close() end
    os.remove(FAILED)
    local asked_driver = want.driver
    from_running() -- what really runs (a busy ASIO driver may have become the normal driver)
    local what = (row or "AUDIO") .. (row and (" " .. (value_text(row) or "")) or "")
    local detail = (msg or ""):match("refused %((.-)%): normal")
    m.applied_row = row
    if detail and asked_driver == "exclusive" then
      -- the exact reason, once: it is also written to norns.log, and audio.conf no longer asks for exclusive on every start
      m.applied_row = nil
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
    m.applied_row = nil
    say(why ~= "" and why or (rc == 2 and "no sound: silence" or "could not open it"), 40)
  end
  if _menu and _menu.show_note and _menu.set_input then
    -- a new device: the input is OFF again (the button state follows)
    _menu.set_input("off", nil, nil, true)
  end
  print("audio: AUDIO page: " .. (rc == 0 and "applied" or (rc == 1 and "reverted" or "silence")) .. (msg ~= "" and (": " .. msg) or ""))
end

m.value_text = value_text
m.init = function()
  read_devices()
  from_running()
  m.pos, m.top, m.tick, m.test, m.testing, m.selftesting, m.busy = 1, 1, 0, nil, false, false, false
  m.status, m.applied_row = nil, nil
  if util.file_exists(FAILED) then say("failed: back to default", 40) end
  -- the menu's own timer (as the other pages use it), not a script metro: a script change must not be able to take it away
  _menu.timer.time = 0.25
  _menu.timer.count = -1
  _menu.timer.event = function() m.timer() end
  _menu.timer:start()
end

-- every quarter of a second while the page is open: the TEST result, the status line, the pages of a long sentence
m.timer = function()
  m.tick = m.tick + 1
  if m.testing or m.selftesting then value_text("TEST") end
  if _menu and _menu.redraw then _menu.redraw() end
end

-- leaving the page never applies anything: a choice that was not applied with K3 is dropped
m.deinit = function()
  _menu.timer:stop()
end

m.key = function(n, z)
  if z ~= 1 then return end
  if n == 2 then
    _menu.set_page("SYSTEM")
  elseif n == 3 and rows()[m.pos] == "TEST" then
    local info = _norns.audio_info()
    m.test, m.testing, m.selftesting, m.selftest_why = nil, false, false, nil
    m.status = nil
    if not info or info.mode ~= "device" then
      m.test = "no card"
      say("no sound card is running (see the status line)", 60)
    elseif not info.in_active then
      -- nothing to listen on: the card and the engine are tested by themselves, no cables needed
      m.selftest_why = m.cfg.input == "" and "no input selected, so no click test" or "the input did not open: choose it again on INPUT; no click test"
      m.selftesting = true
      _norns.audio_selftest_start()
    else
      m.testing = true
      _norns.audio_measure()
    end
    _menu.redraw()
  elseif n == 3 and any_pending() then
    apply()
    _menu.redraw()
  end
end

local function changed()
  m.status, m.applied_row = nil, nil -- a new choice: the old message is about something else
end

local function step(list, i, delta) return util.clamp(i + delta, 1, #list) end

m.enc = function(n, delta)
  if n == 2 then
    local r = rows()
    m.pos = util.clamp(m.pos + delta, 1, #r)
    clear_row_messages()
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
        changed()
      end
    elseif row == "OUTPUT" then
      local l = outputs()
      local i = step(l, index_where(l, function(d) return d.uid == c.output end), delta)
      if l[i].uid ~= c.output then
        c.output, c.out_first = l[i].uid, 1
        if c.driver == "asio" then c.input = "" end
        changed()
      end
    elseif row == "OUT CH" then
      local l = outpairs()
      local i = step(l, index_where(l, function(p) return p.first == c.out_first end), delta)
      if l[i].first ~= c.out_first then c.out_first = l[i].first; changed() end
    elseif row == "INPUT" then
      local l = inputs()
      local i = step(l, index_where(l, function(d) return d.uid == c.input end), delta)
      if l[i].uid ~= c.input then c.input, c.in_l, c.in_r = l[i].uid, 1, math.min(2, math.max(1, l[i].ins or 1)); changed() end
    elseif row == "IN CH" then
      local l = inpairs()
      local i = step(l, index_where(l, function(p) return p.l == c.in_l and p.r == c.in_r end), delta)
      if l[i].l ~= c.in_l or l[i].r ~= c.in_r then c.in_l, c.in_r = l[i].l, l[i].r; changed() end
    elseif row == "BUFFER" then
      local i = step(BUFFERS, index_where(BUFFERS, function(b) return b == c.buffer end), delta)
      if BUFFERS[i] ~= c.buffer then c.buffer = BUFFERS[i]; changed() end
    end
  end
  _menu.redraw()
end

-- one short status line: what is wrong, or the numbers. a message belongs to the selected row; a long sentence goes round in pages of one line
local PAGE_TICKS = 10
local function mode_word(info)
  if (info.host_api or ""):find("ASIO", 1, true) then return "ASIO" end
  if info.exclusive then return "exclusive" end
  return "normal"
end

local function status_line(info)
  if m.busy then return "applying..." end
  if m.status and m.tick < m.status_until then
    local pages = winui.pages(m.status, 124)
    if #pages <= 1 then return pages[1] or m.status end
    return pages[(math.floor((m.tick - (m.status_start or 0)) / PAGE_TICKS) % #pages) + 1]
  end
  if not info then return "" end
  if info.mode == "fallback" and (info.clock_rate or 0) > 0 then
    -- the card is there but another program set its clock: the whole reason, a line at a time (it is the standing state of the card, not a message of a row)
    local pages = winui.pages((info.note or ""):gsub("^no sound: ", ""), 124)
    if #pages == 0 then return "no sound: card clock" end
    return pages[(math.floor(m.tick / PAGE_TICKS) % #pages) + 1]
  elseif info.mode == "fallback" then
    return (info.note:find("busy", 1, true) and "no sound: device busy") or (info.note:find("not found", 1, true) and "no sound: device missing") or "no sound"
  elseif info.mode ~= "device" then
    return "null audio (silent)"
  end
  local line = string.format("%s  %.0f ms  u%d x%d", mode_word(info), info.total_ms or 0, info.underruns or 0, info.xruns or 0)
  -- the rate the card itself runs at, when it is not norns's own: the line then shows the numbers and, in turn, the two rates in plain words (shared mode: Windows converts; exclusive and ASIO follow the card)
  if (info.device_rate or 0) > 0 and math.floor(info.device_rate + 0.5) ~= info.rate then
    local pages = winui.pages(string.format("card %d Hz, norns %d Hz%s", math.floor(info.device_rate + 0.5), info.rate, (info.exclusive or (info.host_api or ""):find("ASIO", 1, true)) and "" or ", converted by Windows"), 124)
    local phase = math.floor(m.tick / PAGE_TICKS) % (#pages + 1) -- 0: the numbers, then the sentence a line at a time
    if phase > 0 then return pages[phase] end
    line = line .. string.format("  card %d Hz", math.floor(info.device_rate + 0.5))
  end
  return line
end
m.status_text = function() return status_line(_norns.audio_info()) end

m.redraw = function()
  screen.clear()
  local info = _norns.audio_info()
  local r = rows()
  -- the rows: the name of the row stays, the value is the full chosen one (cut to fit; no scrolling: the full text is in the info area); the mark at the end: * = chosen, K3 applies; .. = applying; ok = applied
  local list = {}
  for i, row in ipairs(r) do
    local mark
    if i == m.pos and m.busy and (pending(row) or m.applied_row == row) then mark = ".."
    elseif pending(row) then mark = "*"
    elseif m.applied_row == row then mark = "ok" end
    list[i] = {label = row, value = value_text(row), mark = mark}
  end
  local top, full, was_cut = winui.list(list, m.pos)
  m.top = top
  -- under the list: the standing line (what is wrong, or the numbers), then the info area: the full text of the selected row when it was cut, else its help
  winui.status(status_line(info))
  winui.info(was_cut and full or (m.help_text(r[m.pos]) or ""))
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
