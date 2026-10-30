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

return V
