-- lua/core/colour.lua: a hex code <-> hue, saturation, brightness, the picker's steps (docs/port/colour-picker-plan.md, tests 1 and 2). run from the repo root:  lua5.3 linux/tests/colour_test.lua
package.path = "lua/?.lua;lua/core/?.lua;lua/lib/?.lua;" .. package.path
local C = require 'core/colour'
local fails = 0
local function check(ok, what) if not ok then fails = fails + 1; print("FAIL " .. what) end end

-- parsing: 3 or 6 digits, with or without #, any case, blanks
for _, t in ipairs({"3B6EA8", "#3b6ea8", "  #3B6EA8 ", "#36A", "36a"}) do check(C.parse(t) ~= nil, "parses " .. t) end
check(C.hex("#36A") == "3366AA", "3 digits are doubled")
for _, t in ipairs({"", "#", "12", "1234", "12345", "1234567", "#GGGGGG", "3B6EA", "x", "#12 34 56", "#3B6EA8Z"}) do check(C.parse(t) == nil, "refuses '" .. t .. "'") end
check(C.parse(nil) == nil, "refuses nil")

-- the round trip hex -> hue, saturation, brightness -> hex is the identity: every grey, every primary and secondary, black, white, a million spread codes and 100k random ones
local function round_trip(r, g, b)
  local h, s, v = C.rgb_to_hsb(r, g, b)
  local r2, g2, b2 = C.hsb_to_rgb(h, s, v)
  return r2 == r and g2 == g and b2 == b
end
local bad = 0
for i = 0, 255 do if not round_trip(i, i, i) then bad = bad + 1 end end
check(bad == 0, "every grey round-trips (" .. bad .. " wrong)")
for _, c in ipairs({{0, 0, 0}, {255, 255, 255}, {255, 0, 0}, {0, 255, 0}, {0, 0, 255}, {255, 255, 0}, {0, 255, 255}, {255, 0, 255}, {1, 0, 0}, {0, 0, 1}, {254, 255, 255}}) do
  check(round_trip(c[1], c[2], c[3]), string.format("round trip %d %d %d", c[1], c[2], c[3]))
end
bad = 0
for n = 0, 16777215, 17 do if not round_trip(n >> 16, (n >> 8) & 255, n & 255) then bad = bad + 1 end end
check(bad == 0, "a million spread codes round-trip (" .. bad .. " wrong)")
math.randomseed(7)
bad = 0
for _ = 1, 100000 do local r, g, b = math.random(0, 255), math.random(0, 255), math.random(0, 255) if not round_trip(r, g, b) then bad = bad + 1 end end
check(bad == 0, "100k random codes round-trip (" .. bad .. " wrong)")

-- known values
local h, s, v = C.rgb_to_hsb(255, 0, 0); check(h == 0 and s == 100 and v == 100, "red is 0 100 100")
h, s, v = C.rgb_to_hsb(0, 255, 0); check(h == 120, "green is hue 120")
h, s, v = C.rgb_to_hsb(0, 0, 255); check(h == 240, "blue is hue 240")
check(C.hsb_hex(180, 50, 50) == "408080", "the middle (180 50 50) is #408080: " .. C.hsb_hex(180, 50, 50))
check(C.hsb_hex(360, 100, 100) == "FF0000" and C.hsb_hex(0, 100, 100) == "FF0000", "hue 360 is red, the same as 0")
check(C.hsb_hex(123, 0, 100) == "FFFFFF" and C.hsb_hex(123, 50, 0) == "000000", "any hue with no saturation is grey, with no brightness black")

-- greys, black and white keep the hue: opening on them takes the hue the picker last held; raising the saturation then continues at that hue
C.last_hue = 213
local val, valid = C.from_hex("808080")
check(valid and val.h == 213 and val.s == 0, "a grey opens with the kept hue")
C.move(val, "s", 50)
local r, g, b = C.hsb_to_rgb(val.h, val.s, val.v)
local h2 = C.rgb_to_hsb(r, g, b)
check(math.abs(h2 - 213) < 1.5, "raising the saturation on a grey continues at the kept hue (" .. tostring(h2) .. ")")
val = C.from_hex("000000"); check(val.h == 213 and val.v == 0, "black opens with the kept hue")
val = C.from_hex("FFFFFF"); check(val.h == 213 and val.s == 0 and val.v == 100, "white opens with the kept hue")
local before = C.last_hue
val = C.from_hex("3B6EA8")
check(math.abs(val.h - 211.9) < 0.5, "a colour opens at its own hue")
check(C.value_hex(val) == "3B6EA8", "opening a colour and not moving anything gives the same code")
-- moving one strip leaves the other two exactly as they were
local a = C.from_hex("3B6EA8"); local s0, v0 = a.s, a.v
C.move(a, "h", 25)
check(a.s == s0 and a.v == v0, "moving the hue leaves the saturation and brightness bit for bit")

-- an invalid or empty code opens at the middle
for _, t in ipairs({"", "nope", "#12", false}) do
  local m, ok = C.from_hex(t or nil)
  check(not ok and m.h == 180 and m.s == 50 and m.v == 50, "'" .. tostring(t) .. "' opens at the middle")
end
local m = C.from_hex("3B6EA8"); C.centre(m); check(m.h == 180 and m.s == 50 and m.v == 50 and C.value_hex(m) == "408080", "centre moves all three to the middle")

-- steps: base 5, Shift 5 steps, Ctrl one unit, clamped at both ends like a param
check(C.amount(1) == 5 and C.amount(-1) == -5 and C.amount(2) == 10, "a step is 5, a repeat (2 steps) is 10")
check(C.amount(1, true) == 25 and C.amount(-1, true) == -25, "Shift is 5 steps (25)")
check(C.amount(1, false, true) == 1 and C.amount(-2, false, true) == -2, "Ctrl is a fine unit")
check(C.amount(0) == 0 and C.amount(0, true) == 0, "0 steps is 0 (the release of a key)")
local t = {h = 355, s = 98, v = 2}
C.move(t, "h", 10); check(t.h == 360, "hue clamps at 360")
C.move(t, "s", 10); check(t.s == 100, "saturation clamps at 100")
C.move(t, "v", -10); check(t.v == 0, "brightness clamps at 0")
C.move(t, "h", -1000); check(t.h == 0, "hue clamps at 0")
if fails == 0 then print("colour_test: all passed") end
os.exit(fails == 0 and 0 or 1)
