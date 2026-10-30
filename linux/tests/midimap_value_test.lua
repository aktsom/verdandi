-- MIDI MAP, the pure value functions (lua/core/midimap_value.lua), docs/port/midi-map-plan.md sections 2.1a, 2.3, 3.1. no norns, no files. run from the repo root:
--   lua5.3 linux/tests/midimap_value_test.lua
-- every expectation below is written out here, not computed with the code's own formulas
package.path = "lua/?.lua;lua/core/?.lua;lua/lib/?.lua;" .. package.path
local V = require 'core/midimap_value'

local fails = 0
local function check(ok, what) if not ok then fails = fails + 1; print("FAIL " .. what) end end
local function eq(a, b, what) check(a == b, what .. ": got " .. tostring(a) .. ", wanted " .. tostring(b)) end
local function near(a, b, what) check(math.abs(a - b) < 1e-9, what .. ": got " .. tostring(a) .. ", wanted " .. tostring(b)) end

-- ---- the factors: one step per two CC values at sens 5 (absolute), one per unit (relative)
near(V.factor_abs(5), 0.5, "abs factor sens 5")
near(V.factor_abs(1), 0.125, "abs factor sens 1 (one step per eight values)")
near(V.factor_abs(9), 2, "abs factor sens 9 (two steps per value)")
near(V.factor_rel(5), 1, "rel factor sens 5")
near(V.factor_rel(1), 0.25, "rel factor sens 1")
near(V.factor_rel(9), 4, "rel factor sens 9")
eq(V.JUMP, 40, "jump limit")
near(V.PAUSE, 1.5, "pause")

-- ---- absolute
local function run_abs(values, sens, t0, dt)
  local st, total, steps = V.abs_new(), 0, {}
  local t = t0 or 0
  for _, v in ipairs(values) do
    local n = V.abs_step(st, v, sens or 5, t)
    total = total + n
    steps[#steps + 1] = n
    t = t + (dt or 0.01)
  end
  return total, steps, st
end
do
  local total = run_abs({64}, 5)
  eq(total, 0, "abs: the first message gives no steps")
  total = run_abs({0, 10}, 5)
  eq(total, 5, "abs: +10 values at sens 5 = 5 steps")
  total = run_abs({100, 90}, 5)
  eq(total, -5, "abs: -10 values = -5 steps")
  -- a full sweep in single values: the first value is the baseline, 127 changes of one = 63 steps
  local sweep = {}
  for v = 0, 127 do sweep[#sweep + 1] = v end
  total = run_abs(sweep, 5)
  eq(total, 63, "abs: 0 to 127 in single values = 63 steps")
  local back = {}
  for v = 127, 0, -1 do back[#back + 1] = v end
  total = run_abs(back, 5)
  eq(total, -63, "abs: 127 to 0 in single values = -63 steps")
  -- the carry: single values at sens 5 give 0, 1, 0, 1 steps, none is lost
  local _, steps2 = run_abs({10, 11, 12, 13, 14}, 5)
  eq(table.concat(steps2, ","), "0,0,1,0,1", "abs: the remainder is carried (sens 5, +1 each)")
  -- sens 1: a step only after the eighth value
  local one = {}
  for v = 20, 28 do one[#one + 1] = v end
  local t1, s1 = run_abs(one, 1)
  eq(t1, 1, "abs sens 1: 8 values = 1 step")
  eq(s1[#s1], 1, "abs sens 1: the step comes with the eighth change")
  eq(select(1, run_abs({20, 27}, 1)), 0, "abs sens 1: 7 values = no step yet")
  -- sens 9: two steps per value
  eq(select(1, run_abs({30, 31, 32}, 9)), 4, "abs sens 9: 2 values = 4 steps")
  -- direction reversal: up one, down one is nothing in total
  local _, sr = run_abs({10, 11, 10}, 5)
  eq(sr[2] + sr[3], 0, "abs: up one, down one = nothing in total")
  -- the ends: the same value again changes nothing
  eq(select(1, run_abs({127, 127, 127}, 5)), 0, "abs: 127, 127, 127 = nothing")
  eq(select(1, run_abs({0, 0, 0}, 5)), 0, "abs: 0, 0, 0 = nothing")
  -- jump: exactly 40 still counts, 41 is a new baseline
  eq(select(1, run_abs({20, 60}, 5)), 20, "abs: a change of exactly 40 is a turn (20 steps)")
  eq(select(1, run_abs({20, 61}, 5)), 0, "abs: a change of 41 is a jump: no steps")
  eq(select(1, run_abs({100, 59}, 5)), 0, "abs: a jump downwards is no steps either")
  -- after a jump the new value is the baseline
  eq(select(1, run_abs({20, 80, 82}, 5)), 1, "abs: after a jump the next change counts from the new value")
  -- a pause of more than 1.5 s starts again (no steps for the first message after it); exactly 1.5 s does not
  local st = V.abs_new()
  V.abs_step(st, 10, 5, 0)
  eq(V.abs_step(st, 20, 5, 1.5), 5, "abs: a pause of exactly 1.5 s is not a pause")
  eq(V.abs_step(st, 30, 5, 3.1), 0, "abs: after more than 1.5 s the next message is a baseline")
  eq(V.abs_step(st, 34, 5, 3.2), 2, "abs: and then counts again")
  -- reset
  V.abs_reset(st)
  eq(V.abs_step(st, 90, 5, 3.3), 0, "abs: after a reset the next message is a baseline")
end

-- ---- relative: every format against a table written out by hand
local function rel(mode, v) return V.rel_decode(mode, v) end
-- two's complement: 1..63 up, 65..127 down (127 = -1, 65 = -63), 0 and 64 nothing
eq(rel("rel2c", 1), 1, "2c 1"); eq(rel("rel2c", 2), 2, "2c 2"); eq(rel("rel2c", 63), 63, "2c 63")
eq(rel("rel2c", 127), -1, "2c 127"); eq(rel("rel2c", 126), -2, "2c 126"); eq(rel("rel2c", 65), -63, "2c 65")
eq(rel("rel2c", 0), 0, "2c 0"); eq(rel("rel2c", 64), 0, "2c 64")
-- sign-magnitude, bit 6 = sign: 1..63 up, 65..127 down (65 = -1, 127 = -63), 0 and 64 nothing
eq(rel("relsm", 1), 1, "sm 1"); eq(rel("relsm", 63), 63, "sm 63")
eq(rel("relsm", 65), -1, "sm 65"); eq(rel("relsm", 66), -2, "sm 66"); eq(rel("relsm", 127), -63, "sm 127")
eq(rel("relsm", 0), 0, "sm 0"); eq(rel("relsm", 64), 0, "sm 64")
-- offset binary, 64 = nothing: v - 64
eq(rel("relob", 65), 1, "ob 65"); eq(rel("relob", 63), -1, "ob 63"); eq(rel("relob", 127), 63, "ob 127")
eq(rel("relob", 0), -64, "ob 0"); eq(rel("relob", 64), 0, "ob 64"); eq(rel("relob", 1), -63, "ob 1")
-- the formats disagree on the same value (the table of the plan)
check(rel("rel2c", 127) ~= rel("relsm", 127) and rel("relsm", 127) ~= rel("relob", 127), "the formats differ on 127")
check(rel("rel2c", 65) ~= rel("relsm", 65), "the formats differ on 65")
for _, mode in ipairs({"rel2c", "relsm", "relob"}) do
  for v = 0, 127 do
    local r = rel(mode, v)
    check(r >= -64 and r <= 63 and r == math.floor(r), mode .. " " .. v .. " is a whole number in range")
  end
end
eq(rel("nonsense", 5), 0, "unknown mode decodes to nothing")
eq(rel("abs", 5), 0, "abs is not a relative format")

local function run_rel(mode, values, sens)
  local st, total = V.rel_new(), 0
  for _, v in ipairs(values) do total = total + V.rel_step(st, mode, v, sens or 5) end
  return total, st
end
eq(run_rel("rel2c", {1, 1, 1}), 3, "rel2c: three clicks up")
eq(run_rel("rel2c", {127, 127}), -2, "rel2c: two clicks down")
eq(run_rel("rel2c", {5, 125}), 2, "rel2c: fast up 5, slow down 3")
eq(run_rel("relsm", {65, 65, 3}), 1, "relsm: down 1, down 1, up 3")
eq(run_rel("relob", {65, 63, 66}), 2, "relob: up 1, down 1, up 2")
-- sensitivity with carry
eq(run_rel("rel2c", {1, 1, 1, 1}, 1), 1, "rel2c sens 1: four units = one step")
eq(run_rel("rel2c", {1, 1, 1}, 1), 0, "rel2c sens 1: three units = none yet")
eq(run_rel("rel2c", {1, 1}, 9), 8, "rel2c sens 9: two units = eight steps")
local _, rst = run_rel("rel2c", {1, 1, 1}, 1)
near(rst.acc, 0.75, "the carry is kept")
eq(run_rel("rel2c", {1, 127, 1, 127}, 1), 0, "rel2c: up and down cancel, also with carry")
V.rel_reset(rst)
near(rst.acc, 0, "rel reset")

-- ---- the format suggestion
local function sg(list) return (V.suggest(list)) end
eq(sg({1, 1, 127, 2, 126, 1}), "rel2c", "suggest: two's complement turned both ways")
eq(sg({1, 127, 1, 127, 1, 127}), "rel2c", "suggest: one click each way")
eq(sg({1, 1, 65, 3, 66, 1}), "relsm", "suggest: sign-magnitude turned both ways")
eq(sg({65, 63, 65, 63, 65, 65}), "relob", "suggest: offset binary turned both ways")
eq(sg({66, 62, 67, 61, 65, 63}), "relob", "suggest: offset binary, faster")
eq(sg({1, 1, 1, 1, 1, 1}), nil, "suggest: one direction only gives no suggestion")
eq(sg({127, 127, 127, 127, 127}), nil, "suggest: one direction only, down")
eq(sg({10, 11, 13, 14, 16, 17}), "abs", "suggest: a smooth ramp is absolute")
eq(sg({100, 98, 97, 95, 94, 90}), "abs", "suggest: a smooth ramp down is absolute")
eq(sg({62, 63, 64, 65, 66}), nil, "suggest: an absolute knob through the middle (64 present) is not called relative")
eq(sg({63, 64, 65}), nil, "suggest: three messages are too few")
eq(sg({}), nil, "suggest: nothing")
eq(sg({10, 70, 20, 90, 5, 120}), nil, "suggest: scattered values give nothing")
local _, why = V.suggest({1, 1, 1})
check(type(why) == "string" and why ~= "", "suggest: says why when it has nothing")

-- ---- keys
local function key_run(events, threshold)
  local st, out = V.key_new(), {}
  for _, v in ipairs(events) do out[#out + 1] = V.key_cc(st, v, threshold) or "-" end
  return table.concat(out, ",")
end
eq(key_run({127, 0}, 63), "press,release", "key cc: 127 presses, 0 releases")
eq(key_run({64, 0}, 63), "press,release", "key cc: 64 is above 63")
eq(key_run({63, 0}, 63), "-,-", "key cc: 63 is not above 63 and there is nothing to release")
eq(key_run({127, 40, 20, 0}, 63), "press,-,-,release", "key cc: values in between change nothing while pressed")
eq(key_run({127, 127, 0}, 63), "press,-,release", "key cc: a second press without release is ignored")
eq(key_run({0, 0}, 63), "-,-", "key cc: a release without a press is ignored")
eq(key_run({1, 0}, 0), "press,release", "key cc: threshold 0 = any value above 0")
eq(key_run({126, 127, 0}, 126), "-,press,release", "key cc: threshold 126, only 127 presses")
eq(key_run({127, 0, 127, 0}, 63), "press,release,press,release", "key cc: again")
do
  local st = V.key_new()
  eq(V.key_note(st, "on", 100), "press", "note on")
  eq(V.key_note(st, "on", 100), nil, "note on again without off is ignored")
  eq(V.key_note(st, "off", 0), "release", "note off")
  eq(V.key_note(st, "off", 0), nil, "note off without on is ignored")
  eq(V.key_note(st, "on", 90), "press", "note on")
  eq(V.key_note(st, "on", 0), "release", "note on with velocity 0 is a release")
  V.key_note(st, "on", 5)
  eq(V.key_held(st), true, "held after a press")
  V.key_reset(st)
  eq(V.key_held(st), false, "reset releases")
end

-- ---- device names (docs/port/midi-map-plan.md 2.1a)
local M = V.name_matches
eq(V.norm_name("  MIO   "), "mio", "norm: trim, case")
eq(V.norm_name("mio   MIDI  1"), "mio midi 1", "norm: blanks collapsed")
eq(V.norm_name("mio (ABSENT)"), "mio", "norm: a trailing (ABSENT) marker is dropped")
eq(V.norm_name("a\1b"), "ab", "norm: control characters removed")
check(M("mio", "mio"), "mio matches mio")
check(M("mio", "mio 1"), "mio matches mio 1")
check(M("mio", "mio 2"), "mio matches mio 2")
check(M("mio", "MIO"), "mio matches MIO")
check(M("mio", "mio  "), "mio matches mio with blanks")
check(M("  Mio ", "mio"), "a stored name with blanks and case")
check(not M("mio", "mio 1x"), "mio does not match mio 1x")
check(not M("mio", "mio x"), "mio does not match mio x")
check(not M("mio", "mioxyz"), "mio does not match mioxyz")
check(not M("mio", "mio 1 2"), "mio does not match mio 1 2")
check(not M("mio", "mio MIDI 1"), "mio does not match mio MIDI 1 (another name)")
check(M("mio 2", "mio 2"), "mio 2 matches mio 2")
check(not M("mio 2", "mio"), "mio 2 does not match mio")
check(not M("mio 2", "mio 1"), "mio 2 does not match mio 1")
check(not M("mio 2", "mio 22"), "mio 2 does not match mio 22")
check(M("Push 2", "Push 2"), "Push 2 matches Push 2")
check(M("Push 2", "Push 2 1"), "Push 2 matches its port 1")
check(not M("Push 2", "Push 3"), "Push 2 does not match Push 3")
check(not M("Push 2", "Push"), "Push 2 does not match Push")
check(M("iii grid", "iii grid"), "iii grid matches itself")
check(not M("mio", "iii grid"), "mio does not match iii grid")
check(not M("", "mio"), "an empty stored name matches nothing")
check(not M("mio", ""), "an empty device name matches nothing")
check(not M(nil, "mio"), "nil stored")
check(not M("mio", nil), "nil device")
check(M("\195\164b", "\195\164b"), "non-ASCII names match bytewise")
check(not M("\195\164b", "ab"), "non-ASCII does not match ASCII")
check(M(string.rep("x", 200), string.rep("x", 200)), "a long name")

-- ---- devices that ANY must not take
check(V.is_non_controller("Verdandi keys"), "the keys window is not a controller for ANY")
check(V.is_non_controller("iii grid"), "the iii grid is not a controller for ANY")
check(V.is_non_controller("III Grid"), "also in capitals")
check(V.is_non_controller("iii"), "iii alone")
check(V.is_non_controller("iii arc 2"), "an iii arc")
check(not V.is_non_controller("mio"), "the mio is a controller")
check(not V.is_non_controller("Verdandi JACK in"), "the JACK input is a controller (the network case)")
check(not V.is_non_controller("iiiX controller"), "a name that only starts with the letters iii")
check(not V.is_non_controller("Push 2"), "Push 2")
check(not V.is_non_controller(nil), "nil")

if fails == 0 then print("midimap value: all passed") end
os.exit(fails == 0 and 0 or 1)
