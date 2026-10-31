-- MIDI MAP on a computer (Linux desktop): which MIDI control turns E1-E3 and presses K1-K3, and the presets of those six mappings. SYSTEM > MIDI MAP (core/menu/midimap.lua),
-- the layer that acts on messages is core/midimap.lua. docs/port/midi-map-plan.md 2.1, 2.7. the settings live in <norns home>/midimap.conf, key=value lines like ui.conf and box.conf:
--   verdandi-midimap=1   the header (a file without it is still read, with a log line; another number is read as far as understood and warned about)
--   preset=PUSH 2        the name of the preset in use (a label: the mappings below are what counts), CUSTOM when none
--   on_clash=params      params (default): the params MAP gets a CC that both want; both: both react
--   e1.type=cc e1.num=71 e1.dev=ANY e1.ch=0 e1.mode=abs e1.sens=5     one control: e1 e2 e3 (encoders) and k1 k2 k3 (keys; type cc or note, k1.threshold=63 instead of mode and sens)
--   a1.type=cc a1.num=76 a1.dev=ANY a1.ch=0 a1.mode=relob a1.gain=8 a1.accel=off     the four encoders of the virtual arc (a1 to a4: a CC only; gain 1 to 64 ticks per unit; accel off, low, high; docs/port/arc-plan.md)
--   arc_keys=1 arc_keys_accel=0     the keys 5/6 T/Y G/H B/N in the norns window, and the ramp of a held arc key
--      dev: ANY or a device name (core/midimap_value.lua name_matches: `mio` is every port of the mio, `mio 2` that port); ch: 0 = any, 1 to 16
-- unknown keys are ignored with a log line (and kept when the file is written again), missing keys take their defaults, a damaged value falls back to its own default with a log line.
-- presets: built in (NONE, PUSH 2 (unverified), GENERIC REL 2S) and the owner's own, one small file each in <norns home>/midimap-presets/<slug>.midimap
--   verdandi-midimap-preset=1
--   name=My Push
--   e1.type=cc ... (the same keys, without dev and ch, so that a preset moves between computers and does not name a device)

local M = {}

M.PATH = "/home/we/midimap.conf"
M.DIR = "/home/we/midimap-presets/"
M.log = function(s) print("midimap.conf: " .. s) end

M.IDS = {"e1", "e2", "e3", "k1", "k2", "k3"}
M.ARC_IDS = {"a1", "a2", "a3", "a4"} -- the four encoders of the virtual arc (docs/port/arc-plan.md)
M.ALL_IDS = {"e1", "e2", "e3", "k1", "k2", "k3", "a1", "a2", "a3", "a4"}
M.ACCELS = {"off", "low", "high"}
-- the actions (docs/port/midi-actions-plan.md): the buttons of the box and a few utility actions, in the order of the list on the page. there is no quit, no menu navigation, no typing
M.ACTION_IDS = {"mix", "tape", "home", "params", "input", "grid", "arc", "keys", "maiden", "manual", "mute", "detach", "fullscreen", "screenshot"}
M.ACTION_KINDS = {"none", "note", "ccbutton", "step"}
M.REL_MODES = {"rel2c", "relsm", "relob"}
M.MODES = {"abs", "rel2c", "relsm", "relob"}
M.CLASH = {"params", "both"}
M.MAX_PRESETS = 64 -- of his own
M.MAX_NAME = 18
M.MAX_DEV = 80
M.MAX_FILE = 8192  -- the conf
M.MAX_PRESET_FILE = 2048

local function is_enc(id) return id:sub(1, 1) == "e" end
local function is_key(id) return id:sub(1, 1) == "k" end
local function is_arc(id) return id:sub(1, 1) == "a" end

local function new_action() return {type = "none", dev = "ANY", ch = 0, mode = "relob", dir = "up", threshold = 63} end

local function new_ctl(id)
  if is_enc(id) then return {type = "none", dev = "ANY", ch = 0, mode = "abs", sens = 5} end
  if is_arc(id) then return {type = "none", dev = "ANY", ch = 0, mode = "abs", gain = 8, accel = "off"} end
  return {type = "none", dev = "ANY", ch = 0, threshold = 63}
end

local function defaults()
  local st = {preset = "NONE", on_clash = "params", arc_keys = true, arc_keys_accel = false, actions_on = true, ctl = {}, actions = {}, extra = {}}
  for _, id in ipairs(M.ALL_IDS) do st.ctl[id] = new_ctl(id) end
  for _, id in ipairs(M.ACTION_IDS) do st.actions[id] = new_action() end
  return st
end

local function in_list(list, v) for _, x in ipairs(list) do if x == v then return true end end return false end

--- the whole number a value stands for (a number or a numeric text), nil otherwise
local function whole(v)
  if type(v) == "string" then
    if not v:match("^%s*%-?%d+%s*$") then return nil end
    v = tonumber(v)
  end
  if type(v) ~= "number" or v ~= math.floor(v) then return nil end
  return v
end

local function clean_dev(v)
  if type(v) ~= "string" then return nil, "a name" end
  local n = v:match("^%s*(.-)%s*$")
  if n == "" then return nil, "a device name or ANY" end
  if n:find("[%z\1-\31\127]") then return nil, "no control characters" end
  if #n > M.MAX_DEV then return nil, M.MAX_DEV .. " characters at most" end
  if n:lower() == "any" then return "ANY" end
  return n
end

--- check one field of one control: the value in its normal form, or nil and what was wrong
local function check_field(id, field, v)
  if field == "type" then
    if v == "none" or v == "cc" then return v end
    if v == "note" then
      if is_enc(id) then return nil, "a note cannot turn a knob" end
      if is_arc(id) then return nil, "a note cannot turn an arc encoder" end
      return v
    end
    return nil, "none, cc or note"
  elseif field == "num" then
    local n = whole(v)
    if n == nil or n < 0 or n > 127 then return nil, "0 to 127" end
    return n
  elseif field == "dev" then
    return clean_dev(v)
  elseif field == "ch" then
    local n = whole(v)
    if n == nil or n < 0 or n > 16 then return nil, "0 (any) to 16" end
    return n
  elseif field == "mode" then
    if not (is_enc(id) or is_arc(id)) then return nil, "only encoders have a mode" end
    if in_list(M.MODES, v) then return v end
    return nil, "abs, rel2c, relsm or relob"
  elseif field == "sens" then
    if not is_enc(id) then return nil, "only encoders have a sensitivity" end
    local n = whole(v)
    if n == nil or n < 1 or n > 9 then return nil, "1 to 9" end
    return n
  elseif field == "gain" then
    if not is_arc(id) then return nil, "only arc encoders have a gain" end
    local n = whole(v)
    if n == nil or n < 1 or n > 64 then return nil, "1 to 64" end
    return n
  elseif field == "accel" then
    if not is_arc(id) then return nil, "only arc encoders have an acceleration" end
    if in_list(M.ACCELS, v) then return v end
    return nil, "off, low or high"
  elseif field == "threshold" then
    if not is_key(id) then return nil, "only keys have a threshold" end
    local n = whole(v)
    if n == nil or n < 0 or n > 126 then return nil, "0 to 126" end
    return n
  end
  return nil, "unknown field"
end

--- check one field of one action
local function check_action_field(field, v)
  if field == "type" then
    if in_list(M.ACTION_KINDS, v) then return v end
    return nil, "none, note, ccbutton or step"
  elseif field == "num" then
    local n = whole(v)
    if n == nil or n < 0 or n > 127 then return nil, "0 to 127" end
    return n
  elseif field == "dev" then
    return clean_dev(v)
  elseif field == "ch" then
    local n = whole(v)
    if n == nil or n < 0 or n > 16 then return nil, "0 (any) to 16" end
    return n
  elseif field == "mode" then
    if in_list(M.REL_MODES, v) then return v end
    return nil, "rel2c, relsm or relob"
  elseif field == "dir" then
    if v == "up" or v == "down" then return v end
    return nil, "up or down"
  elseif field == "threshold" then
    local n = whole(v)
    if n == nil or n < 0 or n > 126 then return nil, "0 to 126" end
    return n
  end
  return nil, "unknown field"
end

local ACTION_FIELDS = {"type", "num", "dev", "ch", "mode", "dir", "threshold"}

local function finish_action(id, fields, a, prefix)
  for _, field in ipairs(ACTION_FIELDS) do
    local f = fields[field]
    if f ~= nil then
      local v, why = check_action_field(field, f)
      if v ~= nil then a[field] = v
      else M.log(string.format("%sact.%s.%s=%s: %s, using %s", prefix, id, field, tostring(f):sub(1, 40), why, tostring(a[field]))) end
    end
  end
  if a.type ~= "none" and a.num == nil then
    M.log(string.format("%sact.%s: type %s without a number, using none", prefix, id, a.type))
    a.type = "none"
  end
  if a.type == "none" then a.num = nil end
end

-- ---------------------------------------------------------------- the built-in presets
local function preset(name, label, enc_cc, key_cc, unverified)
  local p = {name = name, label = label, builtin = true, unverified = unverified, ctl = {}}
  for i, id in ipairs(M.IDS) do
    local c = new_ctl(id)
    local n = (i <= 3) and enc_cc and enc_cc[i] or (i > 3 and key_cc and key_cc[i - 3])
    if n then
      c.type, c.num = "cc", n
      if is_enc(id) then c.mode = "rel2c" end
    end
    p.ctl[id] = c
  end
  return p
end

-- PUSH 2: from the vendor's MIDI document as I remember it (not read here, no hardware): the track encoders send CC 71-78, the buttons above the display CC 102-109, the encoders
-- are relative (two's complement) and the buttons send 127 and 0. every number must be checked on the Push 2 (User mode) before this preset is called right: UNVERIFIED
M.BUILTIN = {
  preset("NONE", "NONE", nil, nil, false),
  preset("PUSH 2", "PUSH 2 (UNVERIFIED)", {71, 72, 73}, {102, 103, 104}, true),
  preset("GENERIC REL 2S", "GENERIC REL 2S", {16, 17, 18}, {64, 65, 66}, false),
}
local RESERVED = {}
for _, p in ipairs(M.BUILTIN) do RESERVED[p.name:upper()] = true end
RESERVED["CUSTOM"] = true

function M.validate_name(name)
  if type(name) ~= "string" then return nil, "give a name" end
  local n = name:match("^%s*(.-)%s*$")
  if n == "" then return nil, "give a name" end
  if #n > M.MAX_NAME then return nil, M.MAX_NAME .. " characters at most" end
  if n:find("[%z\1-\31\127]") then return nil, "no control characters" end
  if n:find("[\128-\255]") or n:find("[^%w _%.%-]") then return nil, "letters, digits, space, - _ . only" end
  if n:sub(1, 1) == "." then return nil, "cannot start with a dot" end
  if n:find("..", 1, true) then return nil, "no .. in a name" end
  if not n:find("%w") then return nil, "needs a letter or a digit" end
  if RESERVED[n:upper()] then return nil, n:upper() .. " is a built-in name" end
  return n
end

function M.slug(name) return (name:lower():gsub(" ", "-")) end

-- ---------------------------------------------------------------- reading
--- put the fields found in a file into a state. `raw[id][field] = {value, line}`; every bad value is logged and the field keeps its default
local function finish_ctl(id, fields, c, log_prefix)
  for _, field in ipairs({"type", "num", "dev", "ch", "mode", "sens", "threshold", "gain", "accel"}) do
    local f = fields[field]
    if f ~= nil then
      local v, why = check_field(id, field, f)
      if v ~= nil then c[field] = v
      else
        M.log(string.format("%s%s.%s=%s: %s, using %s", log_prefix, id, field, tostring(f):sub(1, 40), why, tostring(c[field])))
      end
    end
  end
  if c.type ~= "none" and c.num == nil then
    M.log(string.format("%s%s: type %s without a number, using none", log_prefix, id, c.type))
    c.type = "none"
  end
  if c.type == "none" then c.num = nil end
end

local function readable(text)
  if text:find("[%z\1-\8\11\12\14-\31\127]") then return false end
  return true
end

--- the key=value lines of a text: calls f(key, value, line) for each, and reports the lines it cannot use
local function each_line(text, f)
  for line in (text .. "\n"):gmatch("(.-)\r?\n") do
    if line:match("%S") then
      local k, v = line:match("^([%w_%.%-]+)=(.*)$")
      if k then f(k, v, line) else M.log("ignored a line without '='") end
    end
  end
end

function M.load()
  local st = defaults()
  M.state = st
  M.version = M.version + 1
  M.reload_presets()
  local f = io.open(M.PATH, "rb")
  if f == nil then
    M.log("not found, using defaults")
    return st
  end
  local text = f:read(M.MAX_FILE + 1) or ""
  f:close()
  if #text > M.MAX_FILE then M.log("too big (over " .. M.MAX_FILE .. " bytes), using defaults") return st end
  if text == "" then M.log("empty, using defaults") return st end
  if not readable(text) then M.log("not a text file, using defaults") return st end
  local first = text:match("^([^\r\n]*)")
  local ver = first:match("^verdandi%-midimap=(.*)$")
  if ver == nil then M.log("does not start with the header verdandi-midimap=1 (read anyway)")
  elseif ver ~= "1" then M.log("version " .. ver .. " is newer than this one knows (read as far as understood)") end
  local fields, afields = {}, {}
  each_line(text, function(k, v, line)
    if k == "verdandi-midimap" then return end
    local id, field = k:match("^([eka]%d)%.(%w+)$")
    if id and M.state.ctl[id] == nil then id = nil end -- a5 and the like are unknown keys
    local aid, afield = k:match("^act%.(%l+)%.(%l+)$")
    if aid and M.state.actions[aid] == nil then aid = nil end -- an action that does not exist (there is no quit): an unknown key
    if k == "preset" then
      if v ~= "" then st.preset = v else M.log("preset= is empty, using NONE") end
    elseif k == "on_clash" then
      if in_list(M.CLASH, v) then st.on_clash = v
      else M.log(string.format("on_clash=%s is not params or both, using params", v:sub(1, 40))) end
    elseif k == "actions" then
      if v == "1" or v == "0" then st.actions_on = v == "1"
      else M.log(string.format("actions=%s is not 0 or 1, using 1", v:sub(1, 40))) end
    elseif aid and in_list(ACTION_FIELDS, afield) then
      afields[aid] = afields[aid] or {}
      afields[aid][afield] = v:match("^%s*(.-)%s*$")
    elseif k == "arc_keys" or k == "arc_keys_accel" then
      if v == "1" or v == "0" then st[k] = v == "1"
      else M.log(string.format("%s=%s is not 0 or 1, using %s", k, v:sub(1, 40), k == "arc_keys" and "1" or "0")) end
    elseif id and in_list({"type", "num", "dev", "ch", "mode", "sens", "threshold", "gain", "accel"}, field) then
      fields[id] = fields[id] or {}
      fields[id][field] = v:match("^%s*(.-)%s*$")
    else
      M.log("unknown key '" .. k .. "' ignored")
      table.insert(st.extra, line)
    end
  end)
  for _, id in ipairs(M.ALL_IDS) do finish_ctl(id, fields[id] or {}, st.ctl[id], "") end
  for _, id in ipairs(M.ACTION_IDS) do finish_action(id, afields[id] or {}, st.actions[id], "") end
  M.last_rel = nil
  for i = #M.ALL_IDS, 1, -1 do
    local c = st.ctl[M.ALL_IDS[i]]
    if M.last_rel == nil and c.mode and c.mode ~= "abs" and c.type ~= "none" then M.last_rel = c.mode end
  end
  if st.preset ~= "CUSTOM" and M.preset_by_name(st.preset) == nil then
    M.log("preset=" .. st.preset .. ": there is no such preset, using CUSTOM (the mappings stay)")
    st.preset = "CUSTOM"
  end
  return st
end

-- ---------------------------------------------------------------- writing
local function write_ctl(f, id, c, with_device)
  local complete = c.type ~= "none" and c.num ~= nil
  f:write(id .. ".type=" .. (complete and c.type or "none") .. "\n")
  if complete then f:write(id .. ".num=" .. c.num .. "\n") end
  if with_device then
    f:write(id .. ".dev=" .. c.dev .. "\n")
    f:write(id .. ".ch=" .. c.ch .. "\n")
  end
  if is_enc(id) then
    f:write(id .. ".mode=" .. c.mode .. "\n")
    f:write(id .. ".sens=" .. c.sens .. "\n")
  elseif is_arc(id) then
    f:write(id .. ".mode=" .. c.mode .. "\n")
    f:write(id .. ".gain=" .. c.gain .. "\n")
    f:write(id .. ".accel=" .. c.accel .. "\n")
  else
    f:write(id .. ".threshold=" .. c.threshold .. "\n")
  end
end

local function write_action(f, id, a, with_device)
  local complete = a.type ~= "none" and a.num ~= nil
  f:write("act." .. id .. ".type=" .. (complete and a.type or "none") .. "\n")
  if not complete then return end
  f:write("act." .. id .. ".num=" .. a.num .. "\n")
  if with_device then
    f:write("act." .. id .. ".dev=" .. a.dev .. "\n")
    f:write("act." .. id .. ".ch=" .. a.ch .. "\n")
  end
  if a.type == "step" then
    f:write("act." .. id .. ".mode=" .. a.mode .. "\n")
    f:write("act." .. id .. ".dir=" .. a.dir .. "\n")
  elseif a.type == "ccbutton" then
    f:write("act." .. id .. ".threshold=" .. a.threshold .. "\n")
  end
end

--- write midimap.conf (through a temporary file, so that a crash never leaves half of it)
function M.save()
  M.version = M.version + 1
  local tmp = M.PATH .. ".tmp"
  local f = io.open(tmp, "w")
  if f == nil then
    M.log("cannot write " .. M.PATH)
    return false
  end
  local st = M.state
  f:write("verdandi-midimap=1\n")
  f:write("preset=" .. st.preset .. "\n")
  f:write("on_clash=" .. st.on_clash .. "\n")
  f:write("arc_keys=" .. (st.arc_keys and "1" or "0") .. "\n")
  f:write("arc_keys_accel=" .. (st.arc_keys_accel and "1" or "0") .. "\n")
  f:write("actions=" .. (st.actions_on and "1" or "0") .. "\n")
  for _, id in ipairs(M.ALL_IDS) do write_ctl(f, id, st.ctl[id], true) end
  for _, id in ipairs(M.ACTION_IDS) do write_action(f, id, st.actions[id], true) end
  for _, line in ipairs(st.extra or {}) do f:write(line .. "\n") end
  f:close()
  if not os.rename(tmp, M.PATH) then
    os.remove(tmp)
    return false
  end
  return true
end

-- ---------------------------------------------------------------- changing
local function modified() M.state.preset = "CUSTOM" end

--- set one field of one control (validated; saved at once): true, or false and why. a change of what the control does makes the label CUSTOM; a device or a channel does not (presets have none)
function M.set(id, field, value)
  local c = M.state.ctl[id]
  if c == nil then return false, "no such control" end
  local v, why = check_field(id, field, value)
  if v == nil then return false, why end
  c[field] = v
  if field == "mode" and v ~= "abs" and (is_enc(id) or is_arc(id)) then M.last_rel = v end -- the format new actions are read with
  if field == "num" and c.type == "none" then c.type = "cc" end
  if field == "type" and v == "none" then c.num = nil end
  if field ~= "dev" and field ~= "ch" then modified() end
  M.save()
  return true
end

--- learn: the CC or note a control was taught (type cc or note, its number); the device goes back to ANY and the channel to any (the message may come from anywhere), the rest stays. one write
function M.assign(id, type_, num)
  local c = M.state.ctl[id]
  if c == nil then return false, "no such control" end
  local t, why = check_field(id, "type", type_)
  if t == nil or t == "none" then return false, why or "cc or note" end
  local n, why2 = check_field(id, "num", num)
  if n == nil then return false, why2 end
  c.type, c.num, c.dev, c.ch = t, n, "ANY", 0
  modified()
  M.save()
  return true
end

--- clear one control (type none, ANY, any channel; the defaults of the rest)
function M.clear(id)
  if M.state.ctl[id] == nil then return false, "no such control" end
  M.state.ctl[id] = new_ctl(id)
  modified()
  M.save()
  return true
end

-- ---------------------------------------------------------------- the actions
function M.count_actions()
  local n = 0
  for _, id in ipairs(M.ACTION_IDS) do if M.state.actions[id].type ~= "none" then n = n + 1 end end
  return n
end

--- the format a new encoder-step action is read with: the format of the last encoder or arc mapping made, else REL OFS (WATCH shows the real one)
function M.last_rel_mode() return M.last_rel or "relob" end

--- learn: a note, a CC button or an encoder step for an action; the device and the channel go back to ANY and any. `extra` for a step: {mode, dir}. one write
function M.assign_action(id, kind, num, extra)
  local a = M.state.actions[id]
  if a == nil then return false, "no such action" end
  if kind ~= "note" and kind ~= "ccbutton" and kind ~= "step" then return false, "note, ccbutton or step" end
  local n, why = check_action_field("num", num)
  if n == nil then return false, why end
  local mode, dir = a.mode, a.dir
  if kind == "step" then
    mode = extra and extra.mode or M.last_rel_mode()
    dir = extra and extra.dir or "up"
    local m2, w2 = check_action_field("mode", mode)
    if m2 == nil then return false, w2 end
    local d2, w3 = check_action_field("dir", dir)
    if d2 == nil then return false, w3 end
  end
  a.type, a.num, a.dev, a.ch, a.mode, a.dir = kind, n, "ANY", 0, mode, dir
  M.save()
  return true
end

--- set one field of an action (validated, saved at once)
function M.set_action(id, field, value)
  local a = M.state.actions[id]
  if a == nil then return false, "no such action" end
  local v, why = check_action_field(field, value)
  if v == nil then return false, why end
  a[field] = v
  if field == "num" and a.type == "none" then a.type = "note" end
  M.save()
  return true
end

function M.clear_action(id)
  if M.state.actions[id] == nil then return false, "no such action" end
  M.state.actions[id] = new_action()
  M.save()
  return true
end

function M.clear_all_actions()
  for _, id in ipairs(M.ACTION_IDS) do M.state.actions[id] = new_action() end
  M.save()
  return true
end

--- the master switch (the page row, the window menu's tick and Ctrl+Shift+M all come here): saved at once
function M.set_actions_on(v)
  if type(v) ~= "boolean" then return false, "on or off" end
  M.state.actions_on = v
  M.save()
  return true
end

function M.set_arc_keys(v)
  if type(v) ~= "boolean" then return false, "on or off" end
  M.state.arc_keys = v
  M.save()
  return true
end

function M.set_arc_keys_accel(v)
  if type(v) ~= "boolean" then return false, "on or off" end
  M.state.arc_keys_accel = v
  M.save()
  return true
end

function M.set_clash(v)
  if not in_list(M.CLASH, v) then return false, "params or both" end
  M.state.on_clash = v
  M.save()
  return true
end

-- ---------------------------------------------------------------- presets
local function read_preset_file(path, file)
  local f = io.open(path, "rb")
  if f == nil then return nil, "cannot be read" end
  local text = f:read(M.MAX_PRESET_FILE + 1) or ""
  f:close()
  if #text > M.MAX_PRESET_FILE then return nil, "too big (over " .. M.MAX_PRESET_FILE .. " bytes)" end
  if text == "" then return nil, "empty" end
  if not readable(text) then return nil, "not a text file" end
  local first = text:match("^([^\r\n]*)")
  if first ~= "verdandi-midimap-preset=1" then
    local v = first:match("^verdandi%-midimap%-preset=(.*)$")
    if v then return nil, "version " .. v .. " is not known (newer?)" end
    return nil, "does not start with verdandi-midimap-preset=1"
  end
  local p = {builtin = false, ctl = {}}
  local fields, afields = {}, {}
  each_line(text, function(k, v)
    local id, field = k:match("^([eka]%d)%.(%w+)$")
    if id and not in_list(M.ALL_IDS, id) then id = nil end
    local aid, afield = k:match("^act%.(%l+)%.(%l+)$")
    if aid and not in_list(M.ACTION_IDS, aid) then aid = nil end
    if aid and in_list({"type", "num", "mode", "dir", "threshold"}, afield) then
      afields[aid] = afields[aid] or {}
      afields[aid][afield] = v:match("^%s*(.-)%s*$")
    elseif k == "name" then p.name = v
    elseif id and in_list({"type", "num", "mode", "sens", "threshold", "gain", "accel"}, field) then
      fields[id] = fields[id] or {}
      fields[id][field] = v:match("^%s*(.-)%s*$")
    end -- a dev or ch line, and anything else, is ignored: a preset names no device
  end)
  local why
  p.name, why = M.validate_name(p.name)
  if p.name == nil then return nil, "name: " .. tostring(why) end
  if M.slug(p.name) .. ".midimap" ~= file then return nil, "the name '" .. p.name .. "' does not match the file name" end
  for _, id in ipairs(M.IDS) do
    p.ctl[id] = new_ctl(id)
    finish_ctl(id, fields[id] or {}, p.ctl[id], "preset " .. file .. ": ")
  end
  -- the arc encoders only if the file has any of their keys (a preset from before them leaves them alone)
  for _, id in ipairs(M.ARC_IDS) do
    if fields[id] ~= nil then
      p.arcs = p.arcs or {}
      p.arcs[id] = new_ctl(id)
      finish_ctl(id, fields[id], p.arcs[id], "preset " .. file .. ": ")
    end
  end
  -- the actions only if the file has any of their keys (a preset from before them leaves them alone)
  for _, id in ipairs(M.ACTION_IDS) do
    if afields[id] ~= nil then
      p.actions = p.actions or {}
      p.actions[id] = new_action()
      finish_action(id, afields[id], p.actions[id], "preset " .. file .. ": ")
    end
  end
  p.label = p.name
  p.file = M.DIR .. file
  return p
end

--- read midimap-presets/ again: his own presets, sorted by name. every file that is not valid is ignored with a log line
function M.reload_presets()
  M.own = {}
  local files = {}
  for _, name in ipairs(util.scandir(M.DIR) or {}) do
    if name:match("%.midimap$") and name:sub(-1) ~= "/" then files[#files + 1] = name end
  end
  table.sort(files)
  for _, file in ipairs(files) do
    if #M.own >= M.MAX_PRESETS then
      M.log("midimap-presets: more than " .. M.MAX_PRESETS .. " presets: " .. file .. " ignored")
    else
      local p, why = read_preset_file(M.DIR .. file, file)
      if p then
        local seen = false
        for _, o in ipairs(M.own) do if M.slug(o.name) == M.slug(p.name) then seen = true end end
        if seen then M.log("midimap-presets: " .. file .. ": the same preset as another file, ignored")
        else M.own[#M.own + 1] = p end
      else
        M.log("midimap-presets: " .. file .. ": " .. why .. ", ignored")
      end
    end
  end
  table.sort(M.own, function(a, b) return a.name:lower() < b.name:lower() end)
end

function M.preset_list()
  local out = {}
  for _, p in ipairs(M.BUILTIN) do out[#out + 1] = p end
  for _, p in ipairs(M.own or {}) do out[#out + 1] = p end
  return out
end

function M.preset_by_name(name)
  if type(name) ~= "string" then return nil end
  for _, p in ipairs(M.preset_list()) do if p.name == name then return p end end
  for _, p in ipairs(M.preset_list()) do if M.slug(p.name) == M.slug(name) then return p end end
  return nil
end

function M.label() return M.state.preset end

--- the six mappings of a preset (not the clash rule); every device becomes ANY and every channel any. saved at once
function M.select_preset(name)
  local p = M.preset_by_name(name)
  if p == nil then return false, "no such preset" end
  for _, id in ipairs(M.IDS) do
    local c = new_ctl(id)
    for k, v in pairs(p.ctl[id]) do c[k] = v end
    c.dev, c.ch = "ANY", 0
    M.state.ctl[id] = c
  end
  if p.arcs ~= nil then
    for _, id in ipairs(M.ARC_IDS) do
      local c = new_ctl(id)
      for k, v in pairs(p.arcs[id] or {}) do c[k] = v end
      c.dev, c.ch = "ANY", 0
      M.state.ctl[id] = c
    end
  end
  if p.actions ~= nil then
    for _, id in ipairs(M.ACTION_IDS) do
      local a = new_action()
      for k, v in pairs(p.actions[id] or {}) do a[k] = v end
      a.dev, a.ch = "ANY", 0
      M.state.actions[id] = a
    end
  end
  M.state.preset = p.name
  M.save()
  return true
end

--- save the six mappings as a preset (no devices): true, or false and why. a name that exists asks first: false, "exists", the name; overwrite = true writes it
function M.save_preset(name, overwrite)
  local n, why = M.validate_name(name)
  if n == nil then return false, why end
  local existing
  for _, o in ipairs(M.own) do if M.slug(o.name) == M.slug(n) then existing = o end end
  if existing and not overwrite then return false, "exists", existing.name end
  if existing == nil and #M.own >= M.MAX_PRESETS then return false, "there are " .. M.MAX_PRESETS .. " presets already (delete one first)" end
  os.execute('mkdir -p "' .. M.DIR:gsub("/$", "") .. '"')
  local file = M.DIR .. M.slug(n) .. ".midimap"
  local tmp = file .. ".tmp"
  local f = io.open(tmp, "w")
  if f == nil then return false, "cannot write " .. file end
  f:write("verdandi-midimap-preset=1\n", "name=" .. n .. "\n")
  for _, id in ipairs(M.ALL_IDS) do write_ctl(f, id, M.state.ctl[id], false) end
  for _, id in ipairs(M.ACTION_IDS) do write_action(f, id, M.state.actions[id], false) end
  f:close()
  if not os.rename(tmp, file) then return false, "cannot write " .. file end
  M.reload_presets()
  M.state.preset = n
  M.save()
  return true
end

--- delete one of his presets (a built-in one never): true, or false and why. the mappings stay and the label reads CUSTOM
function M.delete_preset(name)
  local p = M.preset_by_name(name)
  if p == nil then return false, "no such preset" end
  if p.builtin then return false, p.name .. " is built in" end
  if not os.remove(p.file) then return false, "cannot delete " .. p.file end
  M.reload_presets()
  if M.state.preset == p.name then M.state.preset = "CUSTOM" end
  M.save()
  return true
end

M.version = 0 -- counts every load and save: the layer looks at it to notice a change
M.state = defaults()
M.own = {}

return M
