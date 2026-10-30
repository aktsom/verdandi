-- colours for the colour picker (core/menu/picker.lua, docs/port/colour-picker-plan.md): a hex code <-> hue, saturation and brightness, and the picker's steps. pure Lua, no hardware, no state
-- except the hue the picker keeps for greys. hue 0-360 degrees, saturation and brightness 0-100 (HSB = HSV). the picker holds the exact floats: a code that was opened is the code that
-- comes back, for every 24 bit colour, so opening a colour and not moving anything changes nothing
local M = {}

M.HUE_MAX, M.PCT_MAX = 360, 100
M.MID = {h = 180, s = 50, v = 50}  -- the middle of every strip: cyan at half saturation and half brightness, #408080
M.STEP = 5                          -- degrees of hue, percent of saturation and brightness: one step
M.BIG = 5                           -- Shift: so many steps
M.FINE = 1                          -- Ctrl: this much (a fine step, not a multiple of the base step)

-- the hue a grey, white or black code has no hue of its own: the picker keeps the last one it held, so raising the saturation again does not jump
M.last_hue = M.MID.h

--- 3 or 6 hex digits, with or without a leading #, either case, blanks round it. returns r, g, b (0-255) or nil and why
function M.parse(text)
  local t = tostring(text or ""):match("^%s*(.-)%s*$")
  if t:sub(1, 1) == "#" then t = t:sub(2) end
  if not (t:match("^%x%x%x$") or t:match("^%x%x%x%x%x%x$")) then return nil, "3 or 6 digits (0-9, a-f)" end
  if #t == 3 then t = t:gsub(".", "%0%0") end
  return tonumber(t:sub(1, 2), 16), tonumber(t:sub(3, 4), 16), tonumber(t:sub(5, 6), 16)
end

--- the six upper case digits of a valid code, or nil
function M.hex(text)
  local r, g, b = M.parse(text)
  if r == nil then return nil end
  return string.format("%02X%02X%02X", r, g, b)
end

function M.rgb_hex(r, g, b)
  return string.format("%02X%02X%02X", r, g, b)
end

--- r, g, b (0-255) -> h (0-360), s (0-100), v (0-100) as exact floats; grey is true when the hue is not defined (s = 0 or v = 0): h is then the kept hue
function M.rgb_to_hsb(r, g, b)
  local rf, gf, bf = r / 255, g / 255, b / 255
  local mx, mn = math.max(rf, gf, bf), math.min(rf, gf, bf)
  local d = mx - mn
  local v = mx * 100
  local s = mx == 0 and 0 or d / mx * 100
  if d == 0 or mx == 0 then return M.last_hue, s, v, true end
  local h
  if mx == rf then h = ((gf - bf) / d) % 6
  elseif mx == gf then h = (bf - rf) / d + 2
  else h = (rf - gf) / d + 4 end
  h = h * 60
  if h < 0 then h = h + 360 end
  return h, s, v, false
end

--- h, s, v -> r, g, b (integers 0-255)
function M.hsb_to_rgb(h, s, v)
  local sf, vf = s / 100, v / 100
  local hh = (h % 360) / 60
  if h >= 360 then hh = 0 end -- 360 is red, the same as 0
  local c = vf * sf
  local x = c * (1 - math.abs(hh % 2 - 1))
  local m = vf - c
  local r, g, b
  if hh < 1 then r, g, b = c, x, 0
  elseif hh < 2 then r, g, b = x, c, 0
  elseif hh < 3 then r, g, b = 0, c, x
  elseif hh < 4 then r, g, b = 0, x, c
  elseif hh < 5 then r, g, b = x, 0, c
  else r, g, b = c, 0, x end
  local function byte(f) return math.max(0, math.min(255, math.floor((f + m) * 255 + 0.5))) end
  return byte(r), byte(g), byte(b)
end

function M.hsb_hex(h, s, v)
  return M.rgb_hex(M.hsb_to_rgb(h, s, v))
end

-- ---------------------------------------------------------------- the picker's value: three numbers
--- a new picker value from a code (valid: the markers are where that colour is; else the middle). returns the value and whether the code was valid
function M.from_hex(text)
  local r, g, b = M.parse(text)
  if r == nil then return {h = M.MID.h, s = M.MID.s, v = M.MID.v}, false end
  local h, s, v = M.rgb_to_hsb(r, g, b)
  M.last_hue = h
  return {h = h, s = s, v = v}, true
end

function M.value_hex(val)
  return M.hsb_hex(val.h, val.s, val.v)
end

local KEYS = {"h", "s", "v"}
local LIMIT = {h = M.HUE_MAX, s = M.PCT_MAX, v = M.PCT_MAX}
M.STRIPS = KEYS

--- one strip by an amount (clamped at both ends, like a param). the other two do not change; the hue is remembered for greys
function M.move(val, strip, amount)
  val[strip] = math.max(0, math.min(LIMIT[strip], val[strip] + amount))
  if strip == "h" then M.last_hue = val.h end
  return val
end

--- the size of a step: steps (a whole number, the encoder's delta) of the base step; Shift makes it BIG steps; Ctrl makes it one fine unit
function M.amount(steps, shift, ctrl)
  if ctrl then return steps * M.FINE end
  return steps * M.STEP * (shift and M.BIG or 1)
end

function M.centre(val)
  val.h, val.s, val.v = M.MID.h, M.MID.s, M.MID.v
  M.last_hue = val.h
  return val
end

return M
