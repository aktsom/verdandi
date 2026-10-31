-- MIDI MAP, the pure value functions (Linux desktop): absolute and relative CC to encoder steps, keys, the format suggestion and device names. docs/port/midi-map-plan.md 2.1a, 2.3.
-- no norns, no files, no clock of its own (the caller passes the time): lua/core/midimap.lua uses these, linux/tests/midimap_value_test.lua tests them.

local V = {}

V.JUMP = 40   -- an absolute change bigger than this is a controller catching up, not a turn: a new baseline, no steps
V.PAUSE = 1.5 -- seconds: after more than this without a message the next one is a new baseline (a hand taking the knob again)

--- steps per CC value for an absolute knob: 1 step per 2 values at sens 5, a log scale (sens 1 = one per 8, sens 9 = two per value)
function V.factor_abs(sens) return 0.5 * 2 ^ ((sens - 5) / 2) end
--- steps per unit for a relative encoder: 1 at sens 5
function V.factor_rel(sens) return 2 ^ ((sens - 5) / 2) end

local function trunc(x) return x >= 0 and math.floor(x) or -math.floor(-x) end

-- ---------------------------------------------------------------- absolute
function V.abs_new() return {last = nil, acc = 0, t = nil} end
function V.abs_reset(st) st.last, st.acc, st.t = nil, 0, nil end

--- one absolute message (v 0-127, now in seconds): the whole steps to turn the encoder by. the first message, the first after a pause and a jump only set the baseline
function V.abs_step(st, v, sens, now)
  local last, t = st.last, st.t
  st.last, st.t = v, now
  if last == nil or t == nil or now - t > V.PAUSE or math.abs(v - last) > V.JUMP then
    st.acc = 0
    return 0
  end
  st.acc = st.acc + (v - last) * V.factor_abs(sens)
  local n = trunc(st.acc)
  st.acc = st.acc - n
  return n
end

-- ---------------------------------------------------------------- relative
function V.rel_new() return {acc = 0} end
function V.rel_reset(st) st.acc = 0 end

--- the signed amount of one relative message in a format: rel2c two's complement, relsm sign-magnitude (bit 6 = sign), relob offset binary (64 = nothing)
function V.rel_decode(mode, v)
  if mode == "rel2c" then
    if v >= 1 and v <= 63 then return v end
    if v >= 65 and v <= 127 then return v - 128 end
    return 0
  elseif mode == "relsm" then
    if v >= 1 and v <= 63 then return v end
    if v >= 65 and v <= 127 then return -(v - 64) end
    return 0
  elseif mode == "relob" then
    return v - 64
  end
  return 0
end

function V.rel_step(st, mode, v, sens)
  local r = V.rel_decode(mode, v)
  if r == 0 then return 0 end
  st.acc = st.acc + r * V.factor_rel(sens)
  local n = trunc(st.acc)
  st.acc = st.acc - n
  return n
end

-- ---------------------------------------------------------------- the suggestion made at learn
local function all_in(list, ...)
  local ranges = {...}
  for _, v in ipairs(list) do
    local ok = false
    for i = 1, #ranges, 2 do
      if v >= ranges[i] and v <= ranges[i + 1] then ok = true end
    end
    if not ok then return false end
  end
  return true
end
local function any_in(list, lo, hi)
  for _, v in ipairs(list) do if v >= lo and v <= hi then return true end end
  return false
end

--- from the first messages of one CC: "rel2c", "relsm", "relob", "abs", or nil and a short reason. only a suggestion: three signatures overlap in one direction, an absolute knob
--- near its middle looks like offset binary, so it takes at least four messages and, for the relative formats, both directions
function V.suggest(list)
  if #list < 4 then return nil, "TURN IT SOME MORE" end
  if all_in(list, 1, 16, 112, 127) and any_in(list, 1, 16) and any_in(list, 112, 127) then return "rel2c" end
  if all_in(list, 1, 16, 65, 80) and any_in(list, 1, 16) and any_in(list, 65, 80) then return "relsm" end
  if all_in(list, 48, 80) and not any_in(list, 64, 64) and any_in(list, 48, 63) and any_in(list, 65, 80) then return "relob" end
  if all_in(list, 1, 16) or all_in(list, 112, 127) then return nil, "TURN IT BOTH WAYS" end
  if #list >= 5 and not all_in(list, 48, 80) then
    local up, down, distinct, seen = true, true, 0, {}
    for i, v in ipairs(list) do
      if not seen[v] then seen[v] = true; distinct = distinct + 1 end
      if i > 1 then
        if v < list[i - 1] then up = false end
        if v > list[i - 1] then down = false end
        if math.abs(v - list[i - 1]) > 8 then up, down = false, false end
      end
    end
    if (up or down) and distinct >= 4 then return "abs" end
  end
  return nil, "NOT SURE: SET THE MODE"
end

-- ---------------------------------------------------------------- keys
function V.key_new() return {down = false} end
function V.key_held(st) return st.down end
function V.key_reset(st) local was = st.down; st.down = false; return was end

--- a CC: "press" when the value is above the threshold and the key is up, "release" at 0 while it is down, else nil
function V.key_cc(st, v, threshold)
  if not st.down and v > threshold then
    st.down = true
    return "press"
  elseif st.down and v == 0 then
    st.down = false
    return "release"
  end
  return nil
end

--- a note: kind "on" or "off", the velocity; a note on with velocity 0 is a note off
function V.key_note(st, kind, vel)
  if kind == "on" and vel > 0 then
    if st.down then return nil end
    st.down = true
    return "press"
  end
  if st.down then
    st.down = false
    return "release"
  end
  return nil
end

-- ---------------------------------------------------------------- device names (docs/port/midi-map-plan.md 2.1a)
--- trim, collapse blanks, lower case, no control characters, no trailing "(ABSENT)"
function V.norm_name(s)
  if type(s) ~= "string" then return "" end
  s = s:gsub("[%z\1-\31\127]", "")
  s = s:gsub("%s+", " "):match("^ ?(.-) ?$")
  s = s:lower()
  s = s:gsub(" ?%(absent%)$", "")
  return s
end

--- does the stored name mean this device? the same name, or the stored name followed by a blank and digits only (an interface name means every port: `mio` is `mio`, `mio 1`, `mio 2`);
--- a stored port name means that port only
function V.name_matches(stored, device)
  local s, d = V.norm_name(stored), V.norm_name(device)
  if s == "" or d == "" then return false end
  if s == d then return true end
  if #d > #s + 1 and d:sub(1, #s + 1) == s .. " " and d:sub(#s + 2):match("^%d+$") then return true end
  return false
end

--- the devices that ANY never takes: the keys window and monome iii devices (a grid or an arc sends notes that are no controller's)
function V.is_non_controller(name)
  local n = V.norm_name(name)
  if n == "verdandi keys" then return true end
  return n == "iii" or n:sub(1, 4) == "iii "
end


-- ---------------------------------------------------------------- the virtual arc (docs/port/arc-plan.md 3.2, 3.3)
V.ARC_TICKS_PER_TURN = 1024 -- as the hardware (monome docs)
V.ARC_KEY_TICKS = 16        -- one press of an arc key: 1/64 of a turn, one LED of the ring
V.ARC_KEY_SHIFT_TICKS = 4

function V.arc_new() return {acc = 0, t = nil} end
function V.arc_reset(st) st.acc, st.t = 0, nil end

--- one message worth `units` (a relative amount, or the change of an absolute value) at `gain` ticks per unit: the whole ticks to turn the arc by (the fraction is carried). accel "off" (linear, like an arc), "low" or "high":
--- the ticks are multiplied by 1 + a (|units| - 1), a = 0.25 or 0.5, and by 2, 3 or 4 when the last message came less than 20, 10 or 5 ms ago (the thresholds of norns's own encoder acceleration). a delta of 0 is nothing
function V.arc_step(st, units, gain, accel, now)
  if units == 0 then return 0 end
  local mult = 1
  if accel == "low" or accel == "high" then
    mult = 1 + (accel == "high" and 0.5 or 0.25) * (math.abs(units) - 1)
    if st.t ~= nil then
      local dt = now - st.t
      if dt < 0.005 then mult = mult * 4 elseif dt < 0.01 then mult = mult * 3 elseif dt < 0.02 then mult = mult * 2 end
    end
  end
  st.t = now
  st.acc = st.acc + units * gain * mult
  local n = trunc(st.acc)
  st.acc = st.acc - n
  return n
end

--- the change of an absolute value (0 for the first message, after a pause of more than V.PAUSE seconds and after a jump of more than V.JUMP: those only set the baseline)
function V.abs_delta(st, v, now)
  local last, t = st.last, st.t
  st.last, st.t = v, now
  if last == nil or t == nil or now - t > V.PAUSE or math.abs(v - last) > V.JUMP then return 0 end
  return v - last
end

--- ONE TURN: the units counted while the knob was turned once round -> ticks per unit (1024 / units, whole, 1 to 64), nil without units
function V.gain_from_turn(units)
  if type(units) ~= "number" or units <= 0 then return nil end
  local g = math.floor(V.ARC_TICKS_PER_TURN / units + 0.5)
  return math.max(1, math.min(64, g))
end

--- the ticks of an arc key event: value 1 press, 2 repeat (0 release and anything else is nothing: a release never steps); shift is finer; the optional ramp doubles after 10 repeats and again after 25
function V.arc_key_ticks(value, shift, repeats, ramp)
  if value ~= 1 and value ~= 2 then return 0 end
  local n = shift and V.ARC_KEY_SHIFT_TICKS or V.ARC_KEY_TICKS
  if value == 2 and ramp then
    if repeats >= 25 then n = n * 4 elseif repeats >= 10 then n = n * 2 end
  end
  return n
end

-- ---------------------------------------------------------------- two mappings that could answer to one message
function V.dev_overlap(a, b)
  if a == "ANY" or b == "ANY" then return true end
  return V.name_matches(a, b) or V.name_matches(b, a)
end

function V.ch_overlap(a, b) return a == 0 or b == 0 or a == b end

-- ---------------------------------------------------------------- WATCH: the last six values of the last CC, and what they look like
V.WATCH_N = 6
V.WATCH_MAX_SOURCES = 32

function V.watch_new() return {map = {}, order = {}, last = nil} end

function V.watch_size(w)
  local n = 0
  for _ in pairs(w.map) do n = n + 1 end
  return n
end

function V.watch_add(w, dev, ch, cc, v)
  local key = tostring(dev) .. "|" .. ch .. "|" .. cc
  local e = w.map[key]
  if e == nil then
    e = {dev = dev, ch = ch, cc = cc, values = {}}
    w.map[key] = e
  else
    for i, k in ipairs(w.order) do if k == key then table.remove(w.order, i) break end end
  end
  w.order[#w.order + 1] = key
  e.values[#e.values + 1] = v
  if #e.values > V.WATCH_N then table.remove(e.values, 1) end
  w.last = key
  while #w.order > V.WATCH_MAX_SOURCES do
    local old = table.remove(w.order, 1)
    w.map[old] = nil
  end
end

local WATCH_TEXT = {
  rel2c = {"LOOKS LIKE REL 2S", "1 UP  127 DOWN"},
  relsm = {"LOOKS LIKE REL SIGN", "1 UP  65 DOWN"},
  relob = {"LOOKS LIKE REL OFS", "65 UP  63 DOWN"},
  abs = {"LOOKS ABSOLUTE", "CHECK THE MODE"},
}

--- what the WATCH view shows: dev, ch, cc and values of the last message's source, the suggested mode (V.suggest on the last six values) and two lines of text
function V.watch_view(w)
  local e = w.last and w.map[w.last]
  if e == nil then return {values = {}, verdict = "TURN AN ENCODER", hint = "ONE CLICK EACH WAY"} end
  local view = {dev = e.dev, ch = e.ch, cc = e.cc, values = {table.unpack(e.values)}}
  if #e.values < 4 then
    view.verdict, view.hint = "TURN ONE CLICK EACH WAY", "A FEW TIMES"
    return view
  end
  local mode, why = V.suggest(e.values)
  view.mode = mode
  if mode then
    view.verdict, view.hint = WATCH_TEXT[mode][1], WATCH_TEXT[mode][2]
  else
    view.verdict, view.hint = "NOT SURE", why or ""
  end
  return view
end

-- ---------------------------------------------------------------- MIDI actions (docs/port/midi-actions-plan.md): press-only triggers and the guard time
V.GUARD = 0.25       -- seconds: the same action does not fire again sooner
V.BURST_QUIET = 0.3  -- seconds without a message before an encoder turn counts as a new burst

--- a note message presses only as a note on with a velocity above 0 (a note off, velocity 0 and anything else never act)
function V.action_note_press(kind, vel) return kind == "on" and vel > 0 end

--- a CC as a button: true only for the press edge above the threshold (st from V.key_new); the release at 0 never acts
function V.action_cc_press(st, v, threshold) return V.key_cc(st, v, threshold) == "press" end

function V.trig_new() return {t = nil} end
function V.trig_reset(st) st.t = nil end

--- an encoder as a trigger: true for the first message of a burst that turns the chosen way ("up" or "down"). every message with an amount keeps the burst alive; delta 0 is nothing
function V.trig_step(st, mode, v, dir, now)
  local r = V.rel_decode(mode, v)
  if r == 0 then return false end
  local fresh = st.t == nil or now - st.t >= V.BURST_QUIET
  st.t = now
  if not fresh then return false end
  return (dir == "up" and r > 0) or (dir == "down" and r < 0)
end

function V.guard_new() return {} end
function V.guard_reset(g) for k in pairs(g) do g[k] = nil end end

--- true and the time is noted when the action may fire; a blocked press does not restart the time
function V.guard_ok(g, id, now)
  local last = g[id]
  if last ~= nil and now - last < V.GUARD then return false end
  g[id] = now
  return true
end

return V
