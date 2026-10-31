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


-- ---- the virtual arc (docs/port/arc-plan.md 3.2, 3.3): ticks, gain, acceleration, calibration, the keyboard step, WATCH, overlaps
eq(V.ARC_TICKS_PER_TURN, 1024, "an arc turn is 1024 ticks")
local function arc_run(units, gain, accel, t0, dt)
  local st, total, out = V.arc_new(), 0, {}
  local t = t0 or 0
  for _, u in ipairs(units) do
    local n = V.arc_step(st, u, gain, accel or "off", t)
    total = total + n
    out[#out + 1] = n
    t = t + (dt or 1)
  end
  return total, out, st
end
eq(select(1, arc_run({1}, 8)), 8, "arc: one unit at gain 8 = 8 ticks")
eq(select(1, arc_run({-1}, 8)), -8, "arc: minus one unit = -8 ticks")
eq(select(1, arc_run({1}, 1)), 1, "arc: gain 1, one unit = 1 tick (a nudge is +-1)")
eq(select(1, arc_run({3}, 64)), 192, "arc: gain 64, 3 units")
eq(select(1, arc_run({0}, 8)), 0, "arc: a delta of 0 gives no ticks (the release lesson)")
eq(select(1, arc_run({0, 0, 0}, 64, "high", 0, 0.001)), 0, "arc: zeros stay zero with acceleration too")
local many = {}
for i = 1, 20 do many[i] = 1 end
eq(select(1, arc_run(many, 8)), select(1, arc_run({20}, 8)), "arc: twenty single units give the same ticks as one step of twenty (linear)")
eq(select(1, arc_run({127}, 8)), 1016, "arc: an absolute sweep of 127 values at gain 8 is 1016 ticks, about one turn")
-- the carry: fractions of a tick are kept (a gain below one does not exist, but acceleration and the key ramp make fractions)
local _, parts = arc_run({1, 1, 1}, 8, "low", 0, 1)
check(parts[1] == 8 and parts[2] == 8 and parts[3] == 8, "arc: low acceleration is exactly linear for single units at a slow pace")
-- acceleration: the factor 1 + a (|u| - 1), a = 0.25 (low), 0.5 (high), and 2 / 3 / 4 when the last message was under 20 / 10 / 5 ms ago
eq(select(1, arc_run({5}, 8, "low")), 8 * 5 * (1 + 0.25 * 4), "arc low: five units = 5 x 8 x 2 = 80")
eq(select(1, arc_run({5}, 8, "high")), 8 * 5 * (1 + 0.5 * 4), "arc high: five units = 5 x 8 x 3 = 120")
eq(select(1, arc_run({-5}, 8, "high")), -120, "arc high: symmetric")
eq(select(1, arc_run({5}, 8, "off")), 40, "arc off: exactly linear")
do
  local st = V.arc_new()
  V.arc_step(st, 1, 8, "low", 0)
  eq(V.arc_step(st, 1, 8, "low", 0.015), 16, "arc low: a message 15 ms after the last is doubled")
  eq(V.arc_step(st, 1, 8, "low", 0.015 + 0.008), 24, "arc low: 8 ms after = tripled")
  eq(V.arc_step(st, 1, 8, "low", 0.015 + 0.008 + 0.003), 32, "arc low: 3 ms after = four times")
  eq(V.arc_step(st, 1, 8, "low", 5), 8, "arc low: after a long pause no multiplier")
  eq(V.arc_step(st, 1, 8, "off", 5.001), 8, "arc off: fast messages are not multiplied")
end
-- the absolute baseline and jumps (units from the change of value)
do
  local st = V.abs_new()
  eq(V.abs_delta(st, 50, 0), 0, "abs delta: the first message is a baseline")
  eq(V.abs_delta(st, 53, 0.1), 3, "abs delta: +3")
  eq(V.abs_delta(st, 52, 0.2), -1, "abs delta: -1")
  eq(V.abs_delta(st, 120, 0.3), 0, "abs delta: a jump of more than 40 is a baseline")
  eq(V.abs_delta(st, 121, 5), 0, "abs delta: after a pause of more than 1.5 s the next is a baseline")
  eq(V.abs_delta(st, 124, 5.1), 3, "abs delta: and then counts again")
end
-- the calibration: units counted in one turn -> gain (1024 / units, a whole number, 1 to 64)
eq(V.gain_from_turn(128), 8, "calibration: 128 units a turn = gain 8")
eq(V.gain_from_turn(4), 64, "calibration: 4 units a turn = 256, clamped to 64")
eq(V.gain_from_turn(2000), 1, "calibration: 2000 units a turn = 0.5, clamped to 1")
eq(V.gain_from_turn(100), 10, "calibration: 100 units = 10.24, rounded to 10")
eq(V.gain_from_turn(0), nil, "calibration: no units, no gain")
eq(V.gain_from_turn(-5), nil, "calibration: negative, no gain")
-- the keyboard step: 16 ticks (one LED), Shift 4, a repeat repeats, a release is nothing, no ramp by default
eq(V.ARC_KEY_TICKS, 16, "a key press is 16 ticks"); eq(V.ARC_KEY_SHIFT_TICKS, 4, "shift is 4 ticks")
eq(V.arc_key_ticks(1, false, 0, false), 16, "key: press = 16")
eq(V.arc_key_ticks(1, true, 0, false), 4, "key: shift press = 4")
eq(V.arc_key_ticks(2, false, 3, false), 16, "key: a repeat = 16")
eq(V.arc_key_ticks(2, true, 3, false), 4, "key: a shifted repeat = 4")
eq(V.arc_key_ticks(0, false, 0, false), 0, "key: a release is nothing")
eq(V.arc_key_ticks(0, true, 30, true), 0, "key: a release is nothing, whatever the ramp")
eq(V.arc_key_ticks(2, false, 9, true), 16, "key ramp: 9 repeats = x1")
eq(V.arc_key_ticks(2, false, 10, true), 32, "key ramp: 10 repeats = x2")
eq(V.arc_key_ticks(2, false, 25, true), 64, "key ramp: 25 repeats = x4")
eq(V.arc_key_ticks(2, false, 25, false), 16, "key: no ramp unless asked")
eq(V.arc_key_ticks(5, false, 0, false), 0, "key: an unknown value is nothing")
-- two mappings that could answer to the same message
check(V.dev_overlap("ANY", "mio"), "overlap: ANY meets a name"); check(V.dev_overlap("mio", "ANY"), "overlap: a name meets ANY")
check(V.dev_overlap("mio", "mio 2"), "overlap: mio and mio 2"); check(V.dev_overlap("mio 2", "mio"), "overlap: mio 2 and mio")
check(not V.dev_overlap("mio 1", "mio 2"), "overlap: two different ports"); check(not V.dev_overlap("mio", "Push 2"), "overlap: two devices")
check(V.dev_overlap("ANY", "ANY"), "overlap: ANY and ANY")
check(V.ch_overlap(0, 5) and V.ch_overlap(5, 0) and V.ch_overlap(3, 3) and not V.ch_overlap(3, 4), "overlap: channels")
-- WATCH: the last six values of the last CC, and a verdict
do
  local w = V.watch_new()
  local view = V.watch_view(w)
  eq(view.cc, nil, "watch: nothing yet"); eq(#view.values, 0, "watch: no values"); check(view.verdict ~= nil and view.verdict ~= "", "watch: says to turn the knob")
  for _, v in ipairs({65, 63, 65, 63, 65, 65}) do V.watch_add(w, "mio", 1, 76, v) end
  view = V.watch_view(w)
  eq(view.dev, "mio", "watch: the device"); eq(view.ch, 1, "watch: the channel"); eq(view.cc, 76, "watch: the CC")
  eq(table.concat(view.values, " "), "65 63 65 63 65 65", "watch: the last six values")
  eq(view.mode, "relob", "watch: offset binary"); check(view.verdict:find("REL OFS", 1, true), "watch: says REL OFS"); check(view.hint:find("65 UP", 1, true), "watch: says which is up")
  w = V.watch_new()
  for _, v in ipairs({1, 127, 1, 127, 1, 127}) do V.watch_add(w, "mio", 1, 77, v) end
  view = V.watch_view(w); eq(view.mode, "rel2c", "watch: two's complement"); check(view.verdict:find("REL 2S", 1, true), "watch: says REL 2S")
  w = V.watch_new()
  for _, v in ipairs({1, 65, 1, 65, 1, 65}) do V.watch_add(w, "mio", 1, 78, v) end
  view = V.watch_view(w); eq(view.mode, "relsm", "watch: sign-magnitude"); check(view.verdict:find("REL SIGN", 1, true), "watch: says REL SIGN")
  w = V.watch_new()
  for _, v in ipairs({40, 41, 43, 44, 46, 47}) do V.watch_add(w, "mio", 1, 79, v) end
  view = V.watch_view(w); eq(view.mode, "abs", "watch: a ramp is absolute"); check(view.verdict:find("ABSOLUTE", 1, true), "watch: says absolute")
  w = V.watch_new(); V.watch_add(w, "mio", 1, 80, 65)
  view = V.watch_view(w); eq(view.mode, nil, "watch: one value is no verdict"); check(view.verdict:find("CLICK", 1, true), "watch: asks for one click each way")
  -- the display follows the last message; interleaved CCs keep their own lists
  w = V.watch_new()
  for i = 1, 6 do V.watch_add(w, "mio", 1, 10, 65); V.watch_add(w, "mio", 1, 11, 63) end
  view = V.watch_view(w); eq(view.cc, 11, "watch: the last message's CC"); eq(table.concat(view.values, " "), "63 63 63 63 63 63", "watch: its own list")
  V.watch_add(w, "mio", 1, 10, 1)
  view = V.watch_view(w); eq(view.cc, 10, "watch: back to the other CC"); eq(view.values[#view.values], 1, "watch: with its newest value")
  -- another device or channel is another list
  V.watch_add(w, "Push 2", 3, 10, 7)
  view = V.watch_view(w); eq(view.dev, "Push 2", "watch: another device"); eq(#view.values, 1, "watch: its own list is short")
  -- more than six values: the last six
  w = V.watch_new()
  for i = 1, 10 do V.watch_add(w, "mio", 1, 5, i) end
  eq(#V.watch_view(w).values, 6, "watch: six values at most"); eq(V.watch_view(w).values[1], 5, "watch: the oldest of the six")
  -- the watch never grows without limit (many CCs)
  for cc = 0, 127 do for ch = 1, 16 do V.watch_add(w, "mio", ch, cc, 1) end end
  check(V.watch_size(w) <= V.WATCH_MAX_SOURCES, "watch: a limit on the sources it remembers")
end

if fails == 0 then print("midimap value: all passed") end
os.exit(fails == 0 and 0 or 1)
