-- the look of the screen on a computer (Linux desktop): brightness, colour and grey correction, from SYSTEM > UI (core/menu/ui.lua).
-- docs/port/ui-settings-plan.md. the settings live in <norns home>/ui.conf, key=value lines like audio.conf:
--   brightness=0.7    0.1 to 1 in steps of 0.1 (a gentler curve than linear is applied by the screen code), default 1
--   colour=yellow     white, yellow, pink or custom, default white
--   custom=FF8800     the last custom colour (3 or 6 hex digits), none until one was entered
--   greys=0.5         the gamma of the grey correction, 0.4 to 1.0 in steps of 0.1, 1.0 = linear (as before), default 0.5
-- unknown keys are ignored with a log line (and kept when the file is written again), missing keys take their defaults, a damaged value
-- falls back to its own default with a log line. one call, _norns.ui_look(brightness, r, g, b, gamma), tells the window; it exists on the
-- Linux desktop only, elsewhere nothing here applies or writes anything.
--
-- adding a setting: one entry in SETTINGS below (key, default, parse, format) and one row in core/menu/ui.lua; apply() sends what C needs.

local M = {}

M.PATH = "/home/we/ui.conf"
M.log = function(s) print("ui.conf: " .. s) end

M.COLOURS = {"white", "yellow", "pink", "custom"}
M.PRESETS = {white = {255, 255, 255}, yellow = {255, 208, 0}, pink = {255, 128, 184}}

local function clamp(x, lo, hi) return math.max(lo, math.min(hi, x)) end
-- a number in whole tenths, so that steps never leave float noise (0.30000000000000004)
local function tenths(x) return math.floor(x * 10 + 0.5) / 10 end

--- parse a hex colour: 3 or 6 hex digits, with or without a leading #, either case, blanks around ignored.
-- @treturn number r, g, b (0-255) or nil and a message
function M.parse_hex(text)
  local t = tostring(text or ""):match("^%s*(.-)%s*$")
  if t:sub(1, 1) == "#" then t = t:sub(2) end
  if not (t:match("^%x%x%x$") or t:match("^%x%x%x%x%x%x$")) then
    return nil, "3 or 6 digits (0-9, a-f)"
  end
  if #t == 3 then t = t:gsub(".", "%0%0") end
  local r, g, b = tonumber(t:sub(1, 2), 16), tonumber(t:sub(3, 4), 16), tonumber(t:sub(5, 6), 16)
  if r == 0 and g == 0 and b == 0 then return nil, "black would hide the screen" end
  return r, g, b
end

--- the warning the text entry shows while typing: "" for an empty text and for a valid code, else why it is not one yet
function M.hex_hint(text)
  local t = tostring(text or ""):match("^%s*(.-)%s*$")
  if t == "" or t == "#" then return "" end
  local r, msg = M.parse_hex(t)
  return r and "" or msg
end

function M.format_brightness(b) return string.format("%.1f", tenths(b)) end
M.format_greys = M.format_brightness

-- ---- the settings: key, default, parse(text) -> value or nil, format(value) -> text ----
local function number_setting(key, default, lo, hi)
  return {
    key = key, default = default,
    parse = function(text)
      local n = tonumber(text)
      if n == nil or n ~= n then return nil end
      return clamp(tenths(n), lo, hi)
    end,
    format = function(v) return M.format_brightness(v) end,
    range = string.format("%.1f..%.1f", lo, hi),
  }
end

local SETTINGS = {
  number_setting("brightness", 1.0, 0.1, 1.0),
  {
    key = "colour", default = "white",
    parse = function(text)
      text = tostring(text):lower()
      for _, c in ipairs(M.COLOURS) do if c == text then return c end end
      return nil
    end,
    format = function(v) return v end,
    range = "white, yellow, pink or custom",
  },
  {
    key = "custom", default = nil,
    parse = function(text)
      local r, g, b = M.parse_hex(text)
      if r == nil then return nil end
      return string.format("%02X%02X%02X", r, g, b)
    end,
    format = function(v) return v end,
    range = "a hex colour",
  },
  number_setting("greys", 0.5, 0.4, 1.0),
}
local BY_KEY = {}
for _, s in ipairs(SETTINGS) do BY_KEY[s.key] = s end
BY_KEY.color = BY_KEY.colour -- a spelling that is accepted

local function defaults()
  local st = {extra = {}}
  for _, s in ipairs(SETTINGS) do st[s.key] = s.default end
  return st
end
M.state = defaults()

--- read ui.conf into M.state (and return it). a missing file is the defaults, a damaged value is its default, each with a log line
function M.load()
  local st = defaults()
  M.state = st
  local f = io.open(M.PATH)
  if f == nil then
    M.log("not found, using defaults")
    return st
  end
  for line in f:lines() do
    local k, v = line:match("^([%w_]+)=(.*)$")
    if k then
      local s = BY_KEY[k]
      if s == nil then
        M.log("unknown key '" .. k .. "' ignored")
        table.insert(st.extra, line)
      else
        local val = s.parse(v)
        if val == nil then
          M.log(string.format("%s='%s' is not %s, using %s", s.key, v, s.range, tostring(s.default)))
        else
          st[s.key] = val
        end
      end
    elseif line:match("%S") then
      M.log("ignored a line without '='")
    end
  end
  f:close()
  if st.colour == "custom" and st.custom == nil then
    M.log("colour=custom without a valid custom, using white")
    st.colour = "white"
  end
  return st
end

--- write ui.conf (through a temporary file, so that a crash never leaves half of it)
function M.save()
  local tmp = M.PATH .. ".tmp"
  local f = io.open(tmp, "w")
  if f == nil then
    M.log("cannot write " .. M.PATH)
    return false
  end
  for _, s in ipairs(SETTINGS) do
    local v = M.state[s.key]
    if v ~= nil then f:write(s.key .. "=" .. s.format(v) .. "\n") end
  end
  for _, line in ipairs(M.state.extra or {}) do f:write(line .. "\n") end
  f:close()
  return os.rename(tmp, M.PATH) and true or false
end

--- the tint colour of the current setting: r, g, b
function M.tint()
  local st = M.state
  if st.colour == "custom" and st.custom then
    local r, g, b = M.parse_hex(st.custom)
    if r then return r, g, b end
  end
  local p = M.PRESETS[st.colour] or M.PRESETS.white
  return p[1], p[2], p[3]
end

--- tell the window (Linux desktop only)
function M.apply()
  if _norns == nil or _norns.ui_look == nil then return end
  local r, g, b = M.tint()
  _norns.ui_look(M.state.brightness, r, g, b, M.state.greys)
end

--- at start: read the file and apply it
function M.load_and_apply()
  if _norns == nil or _norns.ui_look == nil then return end
  M.load()
  M.apply()
end

-- every change: apply at once, save at once
local function changed()
  M.apply()
  M.save()
end

function M.step_brightness(d)
  M.state.brightness = clamp(tenths(M.state.brightness + d * 0.1), 0.1, 1.0)
  changed()
end

function M.step_greys(d)
  M.state.greys = clamp(tenths(M.state.greys + d * 0.1), 0.4, 1.0)
  changed()
end

--- E3 on COLOUR: white, yellow, pink, custom (custom only once a valid hex was entered)
function M.step_colour(d)
  local n = #M.COLOURS
  if M.state.custom == nil then n = n - 1 end
  local i = 1
  for k, c in ipairs(M.COLOURS) do if c == M.state.colour then i = k end end
  M.state.colour = M.COLOURS[clamp(i + d, 1, n)]
  changed()
end

--- a hex code from the text entry: true, or false and why (the previous colour stays)
function M.set_custom(text)
  local r, g, b = M.parse_hex(text)
  if r == nil then return false, select(2, M.parse_hex(text)) end
  M.state.custom = string.format("%02X%02X%02X", r, g, b)
  M.state.colour = "custom"
  changed()
  return true
end

return M
