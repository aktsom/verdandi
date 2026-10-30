-- the look of the box on a computer (Linux desktop): the style (aluminium or pixel), five colours (box, keys, encoders, buttons, font), the page buttons shown or hidden, and the looks the
-- owner saved. SYSTEM > BOX (core/menu/box.lua). docs/port/box-style-plan.md. the settings live in <norns home>/box.conf, key=value lines like ui.conf:
--   style=aluminium   aluminium (default) or pixel: the shape language. the five colours work for both
--   preset=MAC        the name of the look in use (a label: the colours below are what counts), CUSTOM when none
--   box=D1D4D8  keys=404246  encoders=DCDDE0  buttons=303135  font=C3C6CB     6 hex digits each (3 are accepted and doubled); the defaults are the Mac look
--   show_buttons=1    1 (default) or 0: the right-click item "Show the page buttons", applied at once
-- unknown keys are ignored with a log line (and kept when the file is written again), missing keys take their defaults, a damaged value falls back to its own default with a log line.
-- one call, _norns.box_look(style, box, keys, encoders, buttons, font, show_buttons), tells the window; it exists on the Linux desktop only, elsewhere nothing here applies or writes anything.
-- a look = the style and the five colours. four are built in (DARK LIGHT COLOUR MAC: the same table as matron/src/platform/linux/box_palette.c, a test compares them); the owner's own are one
-- small file each in <norns home>/box-presets/ (<slug>.box), so that a look can be copied to another computer:
--   verdandi-box=1
--   name=Barn door
--   style=pixel
--   box=2C2E33
--   keys=444853
--   encoders=5D6270
--   buttons=3A3D45
--   font=E4E6EA
-- a damaged, unknown or too-new file is ignored with one log line, never an error.

local M = {}

M.PATH = "/home/we/box.conf"
M.DIR = "/home/we/box-presets/"
M.log = function(s) print("box.conf: " .. s) end

M.PARTS = {"box", "keys", "encoders", "buttons", "font"}
M.STYLES = {"aluminium", "pixel"}
M.MAX_LOOKS = 64   -- of his own
M.MAX_NAME = 18
M.MAX_FILE = 2048  -- bytes
M.LOW_CONTRAST = 2.5

-- the built-in looks (box, keys, encoders, buttons, font): see matron/src/platform/linux/box_palette.c
local function look(name, box, keys, encoders, buttons, font)
  return {name = name, builtin = true, style = "pixel", colours = {box = box, keys = keys, encoders = encoders, buttons = buttons, font = font}}
end
M.BUILTIN = {
  look("DARK", "2C2E33", "444853", "5D6270", "3A3D45", "E4E6EA"),
  look("LIGHT", "D8D5CE", "F4F2ED", "B9B5AB", "EBE8E1", "34343A"),
  look("COLOUR", "2B6F73", "F2B63D", "E9DFC8", "1D4A4D", "F7F0DE"),
  look("MAC", "D1D4D8", "404246", "DCDDE0", "303135", "C3C6CB"),
}
local RESERVED = {CUSTOM = true}
for _, l in ipairs(M.BUILTIN) do RESERVED[l.name] = true end

local DEFAULT = M.BUILTIN[4] -- the Mac look: what the aluminium box always looked like

local function copy_colours(c)
  return {box = c.box, keys = c.keys, encoders = c.encoders, buttons = c.buttons, font = c.font}
end

local function defaults()
  return {style = "aluminium", preset = "MAC", colours = copy_colours(DEFAULT.colours), show_buttons = true, extra = {}}
end
M.state = defaults()
M.own = {}

-- ---------------------------------------------------------------- hex
--- 3 or 6 hex digits, with or without a leading #, either case, blanks round it. black is fine here (a black box is a box)
-- @treturn number r, g, b (0-255) or nil and a message
function M.parse_hex(text)
  local t = tostring(text or ""):match("^%s*(.-)%s*$")
  if t:sub(1, 1) == "#" then t = t:sub(2) end
  if not (t:match("^%x%x%x$") or t:match("^%x%x%x%x%x%x$")) then
    return nil, "3 or 6 digits (0-9, a-f)"
  end
  if #t == 3 then t = t:gsub(".", "%0%0") end
  return tonumber(t:sub(1, 2), 16), tonumber(t:sub(3, 4), 16), tonumber(t:sub(5, 6), 16)
end

--- the six upper case digits of a valid hex text, or nil
function M.hex(text)
  local r, g, b = M.parse_hex(text)
  if r == nil then return nil end
  return string.format("%02X%02X%02X", r, g, b)
end

--- the warning the text entry shows while typing: "" for an empty text and for a valid code, else why it is not one yet
function M.hex_hint(text)
  local t = tostring(text or ""):match("^%s*(.-)%s*$")
  if t == "" or t == "#" then return "" end
  local r, msg = M.parse_hex(t)
  return r and "" or msg
end

local function channel(v)
  v = v / 255
  if v <= 0.03928 then return v / 12.92 end
  return ((v + 0.055) / 1.055) ^ 2.4
end
local function luminance(hex)
  local r, g, b = M.parse_hex(hex)
  return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
end
--- contrast ratio (1 to 21) of two hex colours
function M.contrast(a, b)
  local la, lb = luminance(a), luminance(b)
  if la < lb then la, lb = lb, la end
  return (la + 0.05) / (lb + 0.05)
end

-- ---------------------------------------------------------------- names
--- the name of a look as the owner typed it, trimmed, or nil and why. 1 to 18 characters: letters, digits, space, - _ . (no path characters, nothing that is not plain ASCII, not a built-in name)
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

--- the file name part of a name: lower case, spaces as dashes. two names with the same slug are the same look
function M.slug(name)
  return (name:lower():gsub(" ", "-"))
end

-- ---------------------------------------------------------------- looks
local function read_look_file(path, file)
  local f = io.open(path, "rb")
  if f == nil then return nil, "cannot be read" end
  local text = f:read(M.MAX_FILE + 1) or ""
  f:close()
  if #text > M.MAX_FILE then return nil, "too big (over " .. M.MAX_FILE .. " bytes)" end
  if text == "" then return nil, "empty" end
  if text:find("[%z\1-\8\11\12\14-\31\127]") then return nil, "not a text file" end
  local first = text:match("^([^\r\n]*)")
  if first ~= "verdandi-box=1" then
    local v = first:match("^verdandi%-box=(.*)$")
    if v then return nil, "version " .. v .. " is not known (newer?)" end
    return nil, "does not start with verdandi-box=1"
  end
  local l = {builtin = false, colours = {}}
  for line in text:gmatch("[^\r\n]+") do
    local k, v = line:match("^([%w_]+)=(.*)$")
    if k == "name" then l.name = v
    elseif k == "style" then l.style = v
    elseif k then
      for _, part in ipairs(M.PARTS) do
        if k == part then l.colours[part] = v end
      end
    end
  end
  local why
  l.name, why = M.validate_name(l.name)
  if l.name == nil then return nil, "name: " .. tostring(why) end
  if M.slug(l.name) .. ".box" ~= file then return nil, "the name '" .. l.name .. "' does not match the file name" end
  if l.style ~= "aluminium" and l.style ~= "pixel" then return nil, "style '" .. tostring(l.style) .. "' is not aluminium or pixel" end
  for _, part in ipairs(M.PARTS) do
    local hex = l.colours[part] and M.hex(l.colours[part])
    if hex == nil then return nil, part .. " is not a colour (" .. tostring(l.colours[part]) .. ")" end
    l.colours[part] = hex
  end
  l.file = M.DIR .. file
  return l
end

--- read box-presets/ again: his own looks, sorted by name. every file that is not valid is ignored with a log line
function M.reload_looks()
  M.own = {}
  local files = {}
  for _, name in ipairs(util.scandir(M.DIR) or {}) do
    if name:match("%.box$") and name:sub(-1) ~= "/" then files[#files + 1] = name end
  end
  table.sort(files)
  for _, file in ipairs(files) do
    if #M.own >= M.MAX_LOOKS then
      M.log("box-presets: more than " .. M.MAX_LOOKS .. " looks: " .. file .. " ignored")
    else
      local l, why = read_look_file(M.DIR .. file, file)
      if l then
        local seen = false
        for _, o in ipairs(M.own) do if M.slug(o.name) == M.slug(l.name) then seen = true end end
        if seen then M.log("box-presets: " .. file .. ": the same look as another file, ignored")
        else M.own[#M.own + 1] = l end
      else
        M.log("box-presets: " .. file .. ": " .. why .. ", ignored")
      end
    end
  end
  table.sort(M.own, function(a, b) return a.name:lower() < b.name:lower() end)
end

--- the looks in the order of the PRESET list: the built-in ones, then his own
function M.look_list()
  local out = {}
  for _, l in ipairs(M.BUILTIN) do out[#out + 1] = l end
  for _, l in ipairs(M.own) do out[#out + 1] = l end
  return out
end

function M.look_by_name(name)
  if type(name) ~= "string" then return nil end
  for _, l in ipairs(M.look_list()) do
    if l.name == name then return l end
  end
  for _, l in ipairs(M.look_list()) do
    if M.slug(l.name) == M.slug(name) then return l end
  end
  return nil
end

local function same_as(l)
  if l == nil then return false end
  local st = M.state
  -- the colours only: the style is chosen with STYLE, and the default (aluminium with the Mac look's colours) is just MAC
  for _, part in ipairs(M.PARTS) do
    if st.colours[part] ~= l.colours[part] then return false end
  end
  return true
end

--- true when the colours are not those of the look named in `preset`
function M.is_modified()
  local l = M.look_by_name(M.state.preset)
  return l ~= nil and not same_as(l)
end

--- what the PRESET row says: the name, NAME~ when changed since, CUSTOM when there is no look
function M.label()
  local p = M.state.preset
  if p == "CUSTOM" or M.look_by_name(p) == nil then return "CUSTOM" end
  return p .. (M.is_modified() and "~" or "")
end

-- ---------------------------------------------------------------- the file and the window
local function parse_style(text)
  text = tostring(text):lower()
  if text == "aluminium" or text == "aluminum" or text == "pixel" then return text == "aluminum" and "aluminium" or text end
  return nil
end

--- read box.conf into M.state (and return it), and the looks. a missing file is the defaults, a damaged value is its default, each with a log line
function M.load()
  local st = defaults()
  M.state = st
  M.reload_looks()
  local f = io.open(M.PATH)
  if f == nil then
    M.log("not found, using defaults")
    return st
  end
  for line in f:lines() do
    local k, v = line:match("^([%w_]+)=(.*)$")
    if k == "style" then
      local s = parse_style(v)
      if s then st.style = s else M.log(string.format("style='%s' is not aluminium or pixel, using aluminium", v)) end
    elseif k == "preset" then
      if v ~= "" then st.preset = v else M.log("preset= is empty, using MAC") end
    elseif k == "show_buttons" then
      local t = v:lower()
      if t == "1" or t == "on" or t == "true" then st.show_buttons = true
      elseif t == "0" or t == "off" or t == "false" then st.show_buttons = false
      else M.log(string.format("show_buttons='%s' is not 0 or 1, using 1", v)) end
    elseif k then
      local is_part = false
      for _, part in ipairs(M.PARTS) do
        if k == part then
          is_part = true
          local hex = M.hex(v)
          if hex then st.colours[part] = hex
          else M.log(string.format("%s='%s' is not a colour (3 or 6 hex digits), using %s", part, v, DEFAULT.colours[part])) end
        end
      end
      if not is_part then
        M.log("unknown key '" .. k .. "' ignored")
        table.insert(st.extra, line)
      end
    elseif line:match("%S") then
      M.log("ignored a line without '='")
    end
  end
  f:close()
  if st.preset ~= "CUSTOM" and M.look_by_name(st.preset) == nil then
    M.log("preset=" .. st.preset .. ": there is no such look, using CUSTOM (the colours stay)")
    st.preset = "CUSTOM"
  end
  return st
end

--- write box.conf (through a temporary file, so that a crash never leaves half of it)
function M.save()
  local tmp = M.PATH .. ".tmp"
  local f = io.open(tmp, "w")
  if f == nil then
    M.log("cannot write " .. M.PATH)
    return false
  end
  local st = M.state
  f:write("style=" .. st.style .. "\n")
  f:write("preset=" .. st.preset .. "\n")
  for _, part in ipairs(M.PARTS) do f:write(part .. "=" .. st.colours[part] .. "\n") end
  f:write("show_buttons=" .. (st.show_buttons and "1" or "0") .. "\n")
  for _, line in ipairs(st.extra or {}) do f:write(line .. "\n") end
  f:close()
  return os.rename(tmp, M.PATH) and true or false
end

--- tell the window (Linux desktop only)
function M.apply()
  if _norns == nil or _norns.box_look == nil then return end
  local c = M.state.colours
  _norns.box_look(M.state.style == "pixel" and 1 or 0, c.box, c.keys, c.encoders, c.buttons, c.font, M.state.show_buttons and 1 or 0)
end

--- at start: read the file and apply it
function M.load_and_apply()
  if _norns == nil or _norns.box_look == nil then return end
  M.load()
  M.apply()
  -- the window's menu ticked or unticked "Show the page buttons": C calls this with "1" or "0"
  _norns.box_buttons_changed = function(v) M.set_show_buttons(tostring(v) == "1") end
end

local function changed()
  M.apply()
  M.save()
end

-- ---------------------------------------------------------------- changes
--- one colour, from the text entry: true (and a warning if the pair font / buttons is hard to read), or false and why (the previous colour stays)
function M.set_part(part, text)
  local known = false
  for _, p in ipairs(M.PARTS) do if p == part then known = true end end
  if not known then return false, "no such part: " .. tostring(part) end
  local hex = M.hex(text)
  if hex == nil then return false, select(2, M.parse_hex(text)) end
  M.state.colours[part] = hex
  changed()
  if (part == "font" or part == "buttons") and M.contrast(M.state.colours.font, M.state.colours.buttons) < M.LOW_CONTRAST then
    return true, "low contrast: labels hard to read"
  end
  return true
end

--- the look by name: its style and its five colours (a pixel look switches to pixel, a saved aluminium look to aluminium)
function M.select_look(name)
  local l = M.look_by_name(name)
  if l == nil then return false, "no such look" end
  M.state.style = l.style
  M.state.colours = copy_colours(l.colours)
  M.state.preset = l.name
  changed()
  return true
end

--- STYLE: the shape language only. the first time pixel is chosen while the colours are still the untouched defaults (the Mac look), the dark look is taken, because dark matt is the pixel default
function M.set_style(style)
  if style ~= "aluminium" and style ~= "pixel" then return false end
  if style == "pixel" and M.state.style ~= "pixel" and M.state.preset == "MAC" and not M.is_modified() then
    return M.select_look("DARK")
  end
  M.state.style = style
  changed()
  return true
end

--- E3 on PRESET: the next or the previous look in the list (0 = nothing)
function M.step_preset(d)
  d = math.floor((d or 0) + 0.5)
  if d == 0 then return end
  local list = M.look_list()
  local idx = 0
  for i, l in ipairs(list) do if l.name == M.state.preset then idx = i end end
  idx = math.max(1, math.min(#list, idx + d))
  M.select_look(list[idx].name)
end

function M.set_show_buttons(on)
  M.state.show_buttons = on and true or false
  changed()
end

-- ---------------------------------------------------------------- his own looks
--- save the colours and the style as a look: true, or false and why. a name that exists asks first: false, "exists", the name; overwrite = true writes it
function M.save_look(name, overwrite)
  local n, why = M.validate_name(name)
  if n == nil then return false, why end
  local existing
  for _, o in ipairs(M.own) do if M.slug(o.name) == M.slug(n) then existing = o end end
  if existing and not overwrite then return false, "exists", existing.name end
  if existing == nil and #M.own >= M.MAX_LOOKS then return false, "there are " .. M.MAX_LOOKS .. " looks already (delete one first)" end
  os.execute('mkdir -p "' .. M.DIR:gsub("/$", "") .. '"')
  local file = M.DIR .. M.slug(n) .. ".box"
  local tmp = file .. ".tmp"
  local f = io.open(tmp, "w")
  if f == nil then return false, "cannot write " .. file end
  local st = M.state
  f:write("verdandi-box=1\n", "name=" .. n .. "\n", "style=" .. st.style .. "\n")
  for _, part in ipairs(M.PARTS) do f:write(part .. "=" .. st.colours[part] .. "\n") end
  f:close()
  if not os.rename(tmp, file) then return false, "cannot write " .. file end
  M.reload_looks()
  st.preset = n
  M.save()
  return true
end

--- delete one of his looks (a built-in one never): true, or false and why. the colours stay on the box and the label reads CUSTOM
function M.delete_look(name)
  local l = M.look_by_name(name)
  if l == nil then return false, "no such look" end
  if l.builtin then return false, l.name .. " is built in" end
  if not os.remove(l.file) then return false, "cannot delete " .. l.file end
  M.reload_looks()
  if M.state.preset == l.name then M.state.preset = "CUSTOM" end
  M.save()
  return true
end

return M
