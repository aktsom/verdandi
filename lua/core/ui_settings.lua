-- the look of the screen on a computer (Linux desktop): brightness, colour and grey correction, from SYSTEM > UI (core/menu/ui.lua).
-- docs/port/ui-settings-plan.md. the settings live in <norns home>/ui.conf, key=value lines like audio.conf:
--   brightness=0.7    0.1 to 1 in steps of 0.1 (a gentler curve than linear is applied by the screen code), default 1
--   preset=YELLOW     the name of the colour preset in use (WHITE, YELLOW, PINK, one of his own in screen-presets/, or CUSTOM), default WHITE
--   tint=FFD000       the colour of the screen, 6 hex digits, default FFFFFF (a preset holds the colour only: brightness and contrast are not part of one)
--   contrast=0.5      how much the dim greys are lifted, 0 to 1 in steps of 0.1 (eleven values), 0 = the old linear mapping, default 0.5 (gamma_of below)
--   file_dialog=0     1: a script that opens the file chooser also gets the system's file dialog; 0 (default): norns's own on-screen browser only.
--                     ticked in the window's right-click menu ("Open the file dialog when a script loads a file"), applied at once
--   greys=0.7         the old key of that setting (a gamma, 0.4 to 1.0): still read, converted to the nearest contrast, never written
--   colour=custom, custom=FF8800   the old keys of the colour (white, yellow, pink or custom plus its hex): still read when preset and tint are not there
--                     (custom becomes the current colour, an unsaved look), never written
-- unknown keys are ignored with a log line (and kept when the file is written again), missing keys take their defaults, a damaged value
-- falls back to its own default with a log line. one call, _norns.ui_look(brightness, r, g, b, gamma), tells the window; it exists on the
-- Linux desktop only, elsewhere nothing here applies or writes anything.
--
-- adding a setting: one entry in SETTINGS below (key, default, parse, format) and one row in core/menu/ui.lua; apply() sends what C needs.

local M = {}

M.PATH = "/home/we/ui.conf"
M.log = function(s) print("ui.conf: " .. s) end

M.DIR = "/home/we/screen-presets/"
M.MAX_NAME = 18
M.MAX_PRESETS = 64 -- of his own
M.MAX_FILE = 2048  -- bytes
M.BUILTIN = {
  {name = "WHITE", colour = "FFFFFF", builtin = true},
  {name = "YELLOW", colour = "FFD000", builtin = true},
  {name = "PINK", colour = "FF80B8", builtin = true},
}
M.own = {}
local RESERVED = {CUSTOM = true}
for _, p in ipairs(M.BUILTIN) do RESERVED[p.name] = true end

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
    key = "preset", default = "WHITE",
    parse = function(text)
      local t = tostring(text):match("^%s*(.-)%s*$")
      if t == "" or #t > M.MAX_NAME then return nil end
      return t
    end,
    format = function(v) return v end,
    range = "a preset name",
  },
  {
    key = "tint", default = "FFFFFF",
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
-- the old keys are not settings any more: they are converted at load (greys unless contrast is there too, colour and custom unless preset or tint is there)
local LEGACY_GREYS = "greys"
local LEGACY_COLOURS = {white = "WHITE", yellow = "YELLOW", pink = "PINK"}

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
  local old_colour, old_colour_text, old_custom, seen_preset, seen_tint
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
      elseif k == "colour" or k == "color" then
        old_colour_text = v
        old_colour = tostring(v):match("^%s*(.-)%s*$"):lower()
      elseif k == "custom" then
        local r, g, b = M.parse_hex(v)
        if r == nil then M.log(string.format("custom='%s' is not a hex colour, ignored", v))
        else old_custom = string.format("%02X%02X%02X", r, g, b) end
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
          if s.key == "preset" then seen_preset = true end
          if s.key == "tint" then seen_tint = true end
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
  if seen_preset or seen_tint then
    -- a preset name without a tint takes the colour of a built-in preset; a tint without a preset is an unsaved look
    if seen_tint and not seen_preset then st.preset = "CUSTOM"
    elseif seen_preset and not seen_tint then
      for _, p in ipairs(M.BUILTIN) do if p.name == st.preset then st.tint = p.colour end end
    end
  elseif old_colour ~= nil then
    if LEGACY_COLOURS[old_colour] then
      st.preset = LEGACY_COLOURS[old_colour]
      for _, p in ipairs(M.BUILTIN) do if p.name == st.preset then st.tint = p.colour end end
    elseif old_colour == "custom" then
      if old_custom then
        st.preset, st.tint = "CUSTOM", old_custom
      else
        M.log("colour=custom without a valid custom, using white")
      end
    else
      M.log(string.format("colour='%s' is not white, yellow, pink or custom, using white", old_colour_text))
    end
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
  local r, g, b = M.parse_hex(M.state.tint)
  if r then return r, g, b end
  return 255, 255, 255
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
  M.reload_presets()
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

--- a colour from the picker or the clipboard: true, or false and why (the previous colour stays). the preset in use stays named: the PRESET row then reads NAME~
function M.set_custom(text)
  local r, g, b = M.parse_hex(text)
  if r == nil then return false, select(2, M.parse_hex(text)) end
  M.state.tint = string.format("%02X%02X%02X", r, g, b)
  changed()
  return true
end

-- ---------------------------------------------------------------- the presets (the colour only)
--- the name of a preset as the owner typed it, trimmed, or nil and why: 1 to 18 characters, letters, digits, space, - _ . (no path characters, not a built-in name)
function M.validate_name(name)
  if type(name) ~= "string" then return nil, "give a name" end
  local n = name:match("^%s*(.-)%s*$")
  if n == "" then return nil, "give a name" end
  if #n > M.MAX_NAME then return nil, M.MAX_NAME .. " characters at most" end
  if n:find("[%z\1-\31\127]") then return nil, "no control characters" end
  if n:find('[/\\:*?"<>|]') then return nil, 'no path characters (/ \\ : * ? " < > |)' end
  if n:find("[\128-\255]") or n:find("[^%w _%.%-]") then return nil, "letters, digits, space, - _ . only" end
  if n:sub(1, 1) == "." then return nil, "cannot start with a dot" end
  if n:find("..", 1, true) then return nil, "no .. in a name" end
  if not n:find("%w") then return nil, "needs a letter or a digit" end
  if RESERVED[n:upper()] then return nil, n:upper() .. " is a built-in name" end
  return n
end

--- the file name part of a name: lower case, spaces as dashes
function M.slug(name) return (name:lower():gsub(" ", "-")) end

local function read_preset_file(path, file)
  local f = io.open(path, "rb")
  if f == nil then return nil, "cannot be read" end
  local text = f:read(M.MAX_FILE + 1) or ""
  f:close()
  if #text > M.MAX_FILE then return nil, "too big (over " .. M.MAX_FILE .. " bytes)" end
  if text == "" then return nil, "empty" end
  if text:find("[%z\1-\8\11\12\14-\31\127]") then return nil, "not a text file" end
  local first = text:match("^([^\r\n]*)")
  if first ~= "verdandi-screen=1" then
    local v = first:match("^verdandi%-screen=(.*)$")
    if v then return nil, "version " .. v .. " is not known (newer?)" end
    return nil, "does not start with verdandi-screen=1"
  end
  local p = {builtin = false}
  local colour
  for line in text:gmatch("[^\r\n]+") do
    local k, v = line:match("^([%w_]+)=(.*)$")
    if k == "name" then p.name = v elseif k == "colour" then colour = v end
  end
  local why
  p.name, why = M.validate_name(p.name)
  if p.name == nil then return nil, "name: " .. tostring(why) end
  if M.slug(p.name) .. ".screen" ~= file then return nil, "the name '" .. p.name .. "' does not match the file name" end
  local r, g, b = M.parse_hex(colour)
  if r == nil then return nil, "colour is not a colour (" .. tostring(colour) .. ")" end
  p.colour = string.format("%02X%02X%02X", r, g, b)
  p.file = M.DIR .. file
  return p
end

--- read screen-presets/ again: his own presets, sorted by name. every file that is not valid is ignored with a log line
function M.reload_presets()
  M.own = {}
  local files = {}
  local list = (util and util.scandir and util.scandir(M.DIR)) or {}
  for _, name in ipairs(list) do
    if name:match("%.screen$") and name:sub(-1) ~= "/" then files[#files + 1] = name end
  end
  table.sort(files)
  for _, file in ipairs(files) do
    if #M.own >= M.MAX_PRESETS then
      M.log("screen-presets: more than " .. M.MAX_PRESETS .. " presets: " .. file .. " ignored")
    else
      local p, why = read_preset_file(M.DIR .. file, file)
      if p then
        local seen = false
        for _, o in ipairs(M.own) do if M.slug(o.name) == M.slug(p.name) then seen = true end end
        if seen then M.log("screen-presets: " .. file .. ": the same preset as another file, ignored")
        else M.own[#M.own + 1] = p end
      else
        M.log("screen-presets: " .. file .. ": " .. why .. ", ignored")
      end
    end
  end
  table.sort(M.own, function(a, b) return a.name:lower() < b.name:lower() end)
end

--- the presets in the order of the list: the built-in ones, then his own
function M.preset_list()
  local out = {}
  for _, p in ipairs(M.BUILTIN) do out[#out + 1] = p end
  for _, p in ipairs(M.own) do out[#out + 1] = p end
  return out
end

function M.preset_by_name(name)
  if type(name) ~= "string" then return nil end
  for _, p in ipairs(M.preset_list()) do if p.name == name then return p end end
  for _, p in ipairs(M.preset_list()) do if M.slug(p.name) == M.slug(name) then return p end end
  return nil
end

--- true when the colour is not the one of the preset named in `preset`
function M.is_modified()
  local p = M.preset_by_name(M.state.preset)
  return p ~= nil and p.colour ~= M.state.tint
end

--- what the PRESET row says: the name, NAME~ when changed since, CUSTOM when there is no preset
function M.label()
  local n = M.state.preset
  if n == "CUSTOM" or M.preset_by_name(n) == nil then return "CUSTOM" end
  return n .. (M.is_modified() and "~" or "")
end

--- a preset by name: its colour only (brightness and contrast stay), applied and saved at once
function M.select_preset(name)
  local p = M.preset_by_name(name)
  if p == nil then return false, "no such preset" end
  M.state.tint = p.colour
  M.state.preset = p.name
  changed()
  return true
end

--- E3 on PRESET: the next or the previous preset in the list (0 = nothing)
function M.step_preset(d)
  d = math.floor((d or 0) + 0.5)
  if d == 0 then return end
  local list = M.preset_list()
  local idx = 0
  for i, p in ipairs(list) do if p.name == M.state.preset then idx = i end end
  idx = clamp(idx + d, 1, #list)
  M.select_preset(list[idx].name)
end

--- save the colour as a preset: true, or false and why. a name that exists asks first: false, "exists", the name; overwrite = true writes it
function M.save_preset(name, overwrite)
  local n, why = M.validate_name(name)
  if n == nil then return false, why end
  local existing
  for _, o in ipairs(M.own) do if M.slug(o.name) == M.slug(n) then existing = o end end
  if existing and not overwrite then return false, "exists", existing.name end
  if existing then n = existing.name end -- an overwrite keeps the name as it was first written
  if existing == nil and #M.own >= M.MAX_PRESETS then return false, "there are " .. M.MAX_PRESETS .. " presets already (delete one first)" end
  os.execute('mkdir -p "' .. M.DIR:gsub("/$", "") .. '"')
  local file = M.DIR .. M.slug(n) .. ".screen"
  local tmp = file .. ".tmp"
  local f = io.open(tmp, "w")
  if f == nil then return false, "cannot write " .. file end
  f:write("verdandi-screen=1\n", "name=" .. n .. "\n", "colour=" .. M.state.tint .. "\n")
  f:close()
  if not os.rename(tmp, file) then return false, "cannot write " .. file end
  M.reload_presets()
  M.state.preset = n
  M.save()
  return true
end

--- delete one of his presets (a built-in one never): true, or false and why. the colour stays on the screen and the label reads CUSTOM
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

return M
