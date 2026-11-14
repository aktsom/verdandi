-- MIDI MAP encoder sensitivity, the new scale (Windows 0.10.2; docs/port/phase-m11.md): the table (old and new, written out here, not computed with the code's formulas), the conversion of saved settings and presets
-- once (a marker line, sens_scale=2), what a file with no sens line does, a fresh install, and the speed of a real knob at the ends. run from the repo root: NORNS_PLATFORM=linux lua5.3 linux/tests/midimap_sens_test.lua
package.path = "lua/?.lua;lua/core/?.lua;lua/lib/?.lua;" .. package.path
local tmp = os.tmpname()
os.remove(tmp)
os.execute("mkdir -p " .. tmp)
local real_open, real_remove, real_rename, real_execute = io.open, os.remove, os.rename, os.execute
local function map(p) return (p:gsub("^/home/we", tmp)) end
io.open = function(p, m) return real_open(map(p), m) end
os.remove = function(p) return real_remove(map(p)) end
os.rename = function(a, b) return real_rename(map(a), map(b)) end
os.execute = function(cmd) return real_execute((cmd:gsub("/home/we", tmp))) end
local fails = 0
local function check(ok, what) if not ok then fails = fails + 1; print("FAIL " .. what) end end
local function eq(a, b, what) check(a == b, what .. ": got " .. tostring(a) .. ", wanted " .. tostring(b)) end
local function near(a, b, what) check(math.abs(a - b) < 1e-4, what .. ": got " .. tostring(a) .. ", wanted " .. tostring(b)) end
local function slurp(p) local h = real_open(map(p)); if not h then return nil end local c = h:read("a"); h:close(); return c end
local function put(p, text) local h = real_open(map(p), "w"); h:write(text); h:close() end
util = {scandir = function(dir) local out = {} local p = io.popen("ls -p '" .. map(dir) .. "' 2>/dev/null") for l in p:lines() do out[#out + 1] = l end p:close() return out end,
  clamp = function(x, lo, hi) return math.max(lo, math.min(hi, x)) end}
package.loaded.util = util
local V = require 'core/midimap_value'
local S = require 'core/midimap_settings'
local logs = {}
S.log = function(s) logs[#logs + 1] = s end
local function logged(part) for _, l in ipairs(logs) do if l:find(part, 1, true) then return true end end return false end
local function fresh() logs = {}; os.execute("rm -rf '" .. tmp .. "'/midimap.conf '" .. tmp .. "'/midimap.conf.tmp '" .. tmp .. "'/midimap-presets") end

-- ---- the table. speed = the factor of one unit (relative: steps per unit; absolute: steps per CC value are half of it)
local OLD = {0.25, 0.35355339, 0.5, 0.70710678, 1, 1.41421356, 2, 2.82842712, 4}
local NEW = {0.16666667, 0.20113168, 0.24273141, 0.29291686, 0.35355339, 0.64840970, 1.18920712, 2.18105390, 4}
for k = 1, 9 do
  near(V.OLD_SPEED(k), OLD[k], "old " .. k .. " speed")
  near(V.speed(k), NEW[k], "new " .. k .. " speed")
  near(V.factor_rel(k), NEW[k], "rel factor " .. k)
  near(V.factor_abs(k), NEW[k] / 2, "abs factor " .. k)
end
near(V.speed(5), V.OLD_SPEED(2), "the new 5 is exactly the old 2")
near(V.speed(9), V.OLD_SPEED(9), "the new 9 is exactly the old 9")
near(V.speed(1) / V.OLD_SPEED(1), 2 / 3, "the new 1 is two thirds of the old 1")
for k = 1, 8 do check(V.speed(k + 1) > V.speed(k), "faster with every number: " .. k) end
-- even steps within each part (the same ratio from one number to the next)
local r1 = V.speed(2) / V.speed(1)
for k = 1, 4 do near(V.speed(k + 1) / V.speed(k), r1, "even steps 1 to 5 at " .. k) end
local r2 = V.speed(6) / V.speed(5)
for k = 5, 8 do near(V.speed(k + 1) / V.speed(k), r2, "even steps 5 to 9 at " .. k) end
near(r1, 1.206845, "the step 1 to 5"); near(r2, 1.8340, "the step 5 to 9")
-- numbers outside the scale are held at its ends, a missing one is the default
near(V.speed(0), NEW[1], "0 is held at 1"); near(V.speed(12), NEW[9], "12 is held at 9"); near(V.speed(nil), NEW[5], "none is the default")
eq(V.SENS_DEFAULT, 5, "the default of a fresh install is 5"); eq(V.SENS_SCALE, 2, "the scale is number 2")

-- ---- the conversion of a number on the old scale: the nearest speed (by ratio)
local CONV = {3, 5, 6, 6, 7, 7, 8, 8, 9}
for old = 1, 9 do eq(V.sens_from_old(old), CONV[old], "old " .. old .. " becomes") end
eq(V.sens_from_old(2), 5, "the old 2 (the owner's) becomes 5"); eq(V.sens_from_old(9), 9, "9 stays 9")
for old = 1, 9 do
  local n = V.sens_from_old(old)
  local best = math.huge
  for k = 1, 9 do best = math.min(best, math.abs(math.log(V.speed(k) / V.OLD_SPEED(old)))) end
  near(math.abs(math.log(V.speed(n) / V.OLD_SPEED(old))), best, "old " .. old .. ": no new number is nearer than " .. n)
end

-- ---- a fresh install
fresh()
local st = S.load()
for _, id in ipairs({"e1", "e2", "e3"}) do eq(st.ctl[id].sens, 5, id .. " starts at 5 (the speed of the old 2)") end
check(not logged("converted"), "nothing to convert on a fresh install")
S.set("e1", "num", 20); S.set("e1", "sens", 7); S.save()
local text = slurp("/home/we/midimap.conf")
check(text:find("sens_scale=2\n", 1, true) ~= nil, "a saved file carries the marker")
check(text:find("e1.sens=7\n", 1, true) ~= nil, "and the number as it is")

-- ---- a file from before (no marker): converted once, then the marker stops a second conversion
fresh()
put("/home/we/midimap.conf", "verdandi-midimap=1\npreset=CUSTOM\ne1.type=cc\ne1.num=20\ne1.mode=abs\ne1.sens=2\ne2.type=cc\ne2.num=21\ne2.mode=rel2c\ne2.sens=9\ne3.type=cc\ne3.num=22\ne3.mode=relob\ne3.sens=1\n")
st = S.load()
eq(st.ctl.e1.sens, 5, "old 2 is new 5"); eq(st.ctl.e2.sens, 9, "old 9 is new 9"); eq(st.ctl.e3.sens, 3, "old 1 is new 3 (the nearest speed)")
check(logged("converted once"), "the conversion is logged")
text = slurp("/home/we/midimap.conf")
check(text:find("sens_scale=2\n", 1, true) ~= nil, "the file was written again with the marker")
check(text:find("e1.sens=5\n", 1, true) ~= nil and text:find("e2.sens=9\n", 1, true) ~= nil and text:find("e3.sens=3\n", 1, true) ~= nil, "with the new numbers")
logs = {}
st = S.load()
eq(st.ctl.e1.sens, 5, "read a second time: e1 stays 5 (not converted again)"); eq(st.ctl.e3.sens, 3, "e3 stays 3"); eq(st.ctl.e2.sens, 9, "e2 stays 9")
check(not logged("converted"), "no second conversion")
for i = 1, 3 do S.load() end
eq(S.state.ctl.e1.sens, 5, "and after more starts")
-- old 5 turns into 7 (the same speed to within 19 per cent), not 5
fresh()
put("/home/we/midimap.conf", "verdandi-midimap=1\ne1.type=cc\ne1.num=20\ne1.sens=5\n")
st = S.load()
eq(st.ctl.e1.sens, 7, "old 5 (the old default speed) becomes 7")
-- an encoder with no sens line in an old file had the old default, 5: its speed is kept (7), not reset to the new default
eq(st.ctl.e2.sens, 7, "no sens line in an old file: the old default's speed is kept")
eq(st.ctl.e3.sens, 7, "the same for e3")
-- the same speed after the update: what a CC does is what it did (within a nearest-number difference)
for old = 1, 9 do
  local n = V.sens_from_old(old)
  local ratio = V.speed(n) / V.OLD_SPEED(old)
  check(ratio > 0.7 and ratio < 1.42, "old " .. old .. " to " .. n .. ": the speed changed by at most a factor of 1.42 (" .. string.format("%.2f", ratio) .. ")")
end
-- a damaged number in an old file: the old default, converted
fresh()
put("/home/we/midimap.conf", "verdandi-midimap=1\ne1.type=cc\ne1.num=20\ne1.sens=99\n")
st = S.load()
eq(st.ctl.e1.sens, 7, "a damaged number in an old file is the old default, converted")
-- a marker of a newer scale than this knows is read as scale 2 (nothing converted)
fresh()
put("/home/we/midimap.conf", "verdandi-midimap=1\nsens_scale=9\ne1.type=cc\ne1.num=20\ne1.sens=2\n")
st = S.load()
eq(st.ctl.e1.sens, 2, "a newer scale number: the numbers are taken as they are")
-- an unreadable marker is the old scale
fresh()
put("/home/we/midimap.conf", "verdandi-midimap=1\nsens_scale=abc\ne1.type=cc\ne1.num=20\ne1.sens=2\n")
st = S.load()
eq(st.ctl.e1.sens, 5, "sens_scale=abc: read as the old scale and converted")

-- ---- presets
fresh()
os.execute("mkdir -p '/home/we/midimap-presets'")
put("/home/we/midimap-presets/my-push.midimap", "verdandi-midimap-preset=1\nname=My Push\ne1.type=cc\ne1.num=71\ne1.mode=rel2c\ne1.sens=2\ne2.type=cc\ne2.num=72\ne2.mode=rel2c\ne2.sens=9\ne3.type=cc\ne3.num=73\ne3.mode=rel2c\n")
S.load()
local p = S.preset_by_name("My Push")
check(p ~= nil, "the preset of the old scale is read")
eq(p.ctl.e1.sens, 5, "its old 2 is new 5"); eq(p.ctl.e2.sens, 9, "its old 9 is new 9"); eq(p.ctl.e3.sens, 7, "an encoder with no sens line: the old default, converted")
put("/home/we/midimap-presets/new-one.midimap", "verdandi-midimap-preset=1\nsens_scale=2\nname=New One\ne1.type=cc\ne1.num=71\ne1.mode=rel2c\ne1.sens=2\n")
S.reload_presets()
eq(S.preset_by_name("New One").ctl.e1.sens, 2, "a preset with the marker is not converted")
-- saving a preset writes the marker, and reading it back keeps the number
S.select_preset("My Push")
eq(S.state.ctl.e1.sens, 5, "selected: 5")
check(S.save_preset("Mine"), "a preset is saved")
text = slurp("/home/we/midimap-presets/mine.midimap")
check(text:find("sens_scale=2\n", 1, true) ~= nil, "the saved preset has the marker")
S.reload_presets()
eq(S.preset_by_name("Mine").ctl.e1.sens, 5, "read back: 5 (not converted again)")
-- the built-in presets use the default
eq(S.preset_by_name("GENERIC REL 2S").ctl.e1.sens, 5, "built-in preset: the default 5")

-- ---- the page: 1 to 9 at the ends
fresh(); S.load(); S.set("e1", "sens", 1)
local ok = S.set("e1", "sens", 0); check(ok == false or ok == nil, "0 is refused")
ok = S.set("e1", "sens", 10); check(ok == false or ok == nil, "10 is refused")

-- ---- a real knob: 127 CC values of a slow sweep, in steps
local function sweep(sens)
  local st2, total = V.abs_new(), 0
  for v = 0, 127 do total = total + V.abs_step(st2, v, sens, v * 0.01) end
  return total
end
eq(sweep(9), 254, "a full sweep at 9: about two steps per value")
check(sweep(5) >= 21 and sweep(5) <= 23, "a full sweep at 5: about 22 steps (one per 5.66 values): " .. sweep(5))
check(sweep(1) >= 10 and sweep(1) <= 11, "a full sweep at 1: about 10 steps: " .. sweep(1))
os.execute("rm -rf '" .. tmp .. "'")
if fails > 0 then print(fails .. " failed"); os.exit(1) end
print("midimap sens: all passed")
