-- the look of the screen on a computer (Linux desktop): brightness, colour and grey correction, from SYSTEM > UI (core/menu/ui.lua).
-- docs/port/ui-settings-plan.md. the settings live in <norns home>/ui.conf, key=value lines like audio.conf:
--   brightness=0.7    0.1 to 1 in steps of 0.1 (a gentler curve than linear is applied by the screen code), default 1
--   colour=yellow     white, yellow, pink or custom, default white
--   custom=FF8800     the last custom colour (3 or 6 hex digits), none until one was entered
--   contrast=0.5      how much the dim greys are lifted, 0 to 1 in steps of 0.1 (eleven values), 0 = the old linear mapping, default 0.5 (gamma_of below)
--   file_dialog=0     1: a script that opens the file chooser also gets the system's file dialog; 0 (default): norns's own on-screen browser only.
--                     ticked in the window's right-click menu ("Open the file dialog when a script loads a file"), applied at once
--   greys=0.7         the old key of that setting (a gamma, 0.4 to 1.0): still read, converted to the nearest contrast, never written
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
  local r = M.parse_hex(t)
  return r and "" or "need 3 or 6 digits"
end

--- the text entry's limit for a hex code: an optional #, then at most 6 hex digits, nothing else. true, or false and a short hint
function M.hex_accept(text)
  local digits = tostring(text or ""):match("^#?(%x*)$")
  if digits == nil then return false, "0-9 and a-f only" end
  if #digits > 6 then return false, "6 digits max" end
  return true
end

function M.format_brightness(b) return string.format("%.1f", tenths(b)) end
M.format_contrast = M.format_brightness

--- the displayed contrast (0 to 1) as the gamma exponent of the grey correction g' = 255 (g / 255) ^ gamma, in one place:
--   0 .. 0.5:  gamma = 1 - contrast         (1.0 linear ... 0.5, one tenth of gamma per step)
--   0.5 .. 1:  gamma = 0.5 - 0.2 (contrast - 0.5)   (0.5 ... 0.4, two hundredths per step)
-- 0 is exactly the old linear mapping, 0.5 the first default (gamma 0.5), 1 the strongest lift (gamma 0.4)
function M.gamma_of(contrast)
  local c = clamp(contrast, 0, 1)
  if c <= 0.5 then return 1.0 - c end
  return 0.5 - 0.2 * (c - 0.5)
end

--- the inverse for the old greys key: a gamma (0.4 to 1.0) as the nearest contrast value (a step of 0.1)
function M.contrast_from_gamma(gamma)
  local g = clamp(gamma, 0.4, 1.0)
  local c
  if g >= 0.5 then c = 1.0 - g else c = 0.5 + (0.5 - g) / 0.2 end
  return tenths(c)
end

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
  {
    key = "contrast", default = 0.5,
    -- out of range is not clamped: it falls back to the default with a log line, like a damaged value
    parse = function(text)
      local n = tonumber(text)
      if n == nil or n ~= n or n < -1e-9 or n > 1 + 1e-9 then return nil end
      return clamp(tenths(n), 0, 1)
    end,
    format = function(v) return M.format_contrast(v) end,
    range = "0..1",
  },
  {
    key = "file_dialog", default = false,
    parse = function(text)
      text = tostring(text):lower()
      if text == "1" or text == "on" or text == "true" then return true end
      if text == "0" or text == "off" or text == "false" then return false end
      return nil
    end,
    format = function(v) return v and "1" or "0" end,
    range = "0 or 1",
  },
}
local BY_KEY = {}
for _, s in ipairs(SETTINGS) do BY_KEY[s.key] = s end
BY_KEY.color = BY_KEY.colour -- a spelling that is accepted
-- the old greys key (a gamma) is not a setting any more: it is converted at load unless contrast is there too
local LEGACY_GREYS = "greys"

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
  local legacy, legacy_text, has_contrast
  local f = io.open(M.PATH)
  if f == nil then
    M.log("not found, using defaults")
    return st
  end
  for line in f:lines() do
    local k, v = line:match("^([%w_]+)=(.*)$")
    if k then
      local s = BY_KEY[k]
      if k == LEGACY_GREYS then
        local n = tonumber(v)
        if n == nil or n ~= n then
          M.log(string.format("greys='%s' is not a gamma (0.4..1.0), ignored", v))
        else
          legacy = M.contrast_from_gamma(n)
          legacy_text = v
        end
      elseif s == nil then
        M.log("unknown key '" .. k .. "' ignored")
        table.insert(st.extra, line)
      else
        local val = s.parse(v)
        if val == nil then
          M.log(string.format("%s='%s' is not %s, using %s", s.key, v, s.range, tostring(s.default)))
        else
          st[s.key] = val
          if s.key == "contrast" then has_contrast = true end
        end
      end
    elseif line:match("%S") then
      M.log("ignored a line without '='")
    end
  end
  f:close()
  if legacy ~= nil and not has_contrast then
    st.contrast = legacy
    M.log(string.format("greys=%s (the old gamma key) is contrast=%s now", legacy_text, M.format_contrast(legacy)))
  end
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
  _norns.ui_look(M.state.brightness, r, g, b, M.gamma_of(M.state.contrast))
  if _norns.ui_file_dialog ~= nil then _norns.ui_file_dialog(M.state.file_dialog == true) end -- the tick in the window's menu
end

--- the colour picker: show one custom colour on the screen without storing or saving anything; restore with M.apply()
function M.preview_custom(text)
  if _norns == nil or _norns.ui_look == nil then return false end
  local r, g, b = M.parse_hex(text)
  if r == nil then return false end
  _norns.ui_look(M.state.brightness, r, g, b, M.gamma_of(M.state.contrast))
  return true
end

--- at start: read the file and apply it
function M.load_and_apply()
  if _norns == nil or _norns.ui_look == nil then return end
  M.load()
  M.apply()
  if _norns.ui_file_dialog ~= nil then
    -- the window's menu ticked or unticked the item: C calls this with "1" or "0"
    _norns.ui_file_dialog_changed = function(v) M.set_file_dialog(tostring(v) == "1") end
  end
end

-- every change: apply at once, save at once
local function changed()
  M.apply()
  M.save()
end

-- the step functions take the encoder's delta in steps (0 = nothing: no change, no apply, no write)
function M.step_brightness(d)
  d = math.floor((d or 0) + 0.5)
  if d == 0 then return end
  M.state.brightness = clamp(tenths(M.state.brightness + d * 0.1), 0.1, 1.0)
  changed()
end

function M.step_contrast(d)
  d = math.floor((d or 0) + 0.5)
  if d == 0 then return end
  M.state.contrast = clamp(tenths(M.state.contrast + d * 0.1), 0, 1)
  changed()
end

--- "Open the file dialog when a script loads a file": on or off, applied and saved at once
function M.set_file_dialog(on)
  M.state.file_dialog = on and true or false
  changed()
end

--- E3 on COLOUR: white, yellow, pink, custom (custom only once a valid hex was entered)
function M.step_colour(d)
  d = math.floor((d or 0) + 0.5)
  if d == 0 then return end
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
