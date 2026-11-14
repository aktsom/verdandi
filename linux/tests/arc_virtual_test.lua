-- the virtual arc as a script sees it (lua/core/arc.lua): the ring LEDs a script draws (led, all, segment, relative levels, 1-based ring and led numbers), the deltas and key presses that arrive (one call per message, one device, no double
-- counting when the same ring is turned by the window and by a mapped MIDI encoder), and a second (real) arc next to it. run from the repo root:
--   NORNS_PLATFORM=linux lua5.3 linux/tests/arc_virtual_test.lua
-- the device side (the window's wheel and drag numbers, the 64 LEDs of the protocol) is tested in C: arc_input_test.c and macos/tests/vgrid_test.c
package.path = "lua/?.lua;lua/core/?.lua;lua/lib/?.lua;" .. package.path
local fails = 0
local function check(ok, what) if not ok then fails = fails + 1; print("FAIL " .. what) end end
local function eq(a, b, what) check(a == b, what .. ": got " .. tostring(a) .. ", wanted " .. tostring(b)) end

util = {round = function(x) return math.floor(x + 0.5) end}
package.loaded.util = util

-- the C side of matron (device_monome.cc): 4 rings of 64 LEDs, level 0-15, ring and led given 1-based by the script and 0-based below
local function new_device()
  local d = {data = {}, dirty = {}, refreshed = 0, intensity = 15}
  for n = 0, 3 do d.data[n] = {}; for i = 0, 63 do d.data[n][i] = 0 end; d.dirty[n] = false end
  return d
end
local function clamp(v) return math.max(0, math.min(15, v)) end
_norns = {}
_norns.arc_set_led = function(d, ring, x, val, rel)
  local n, i = (ring - 1) & 3, (x - 1) & 63
  if rel then d.data[n][i] = clamp(d.data[n][i] + val) else d.data[n][i] = val end
  d.dirty[n] = true
end
_norns.arc_all_led = function(d, val, rel)
  for n = 0, 3 do
    for i = 0, 63 do d.data[n][i] = rel and clamp(d.data[n][i] + val) or val end
    d.dirty[n] = true
  end
end
_norns.monome_refresh = function(d) for n = 0, 3 do d.dirty[n] = false end; d.refreshed = d.refreshed + 1 end
_norns.monome_intensity = function(d, i) d.intensity = i end

local Arc = require 'core/arc'

local dev = new_device()
_norns.arc.add(1, "m0000002", "monome arc", dev)
local a = Arc.devices[1]
eq(a.name, "monome arc m0000002", "the arc's name starts with 'monome arc' (startup.lua tells an arc from a grid by it)")
local port = Arc.connect(1)
eq(port.name, a.name, "the first arc takes the first port")
eq(a.port, 1, "the device knows its port")

-- LEDs: led(ring, x, level): 1-based, 0-15
a:all(0); a:refresh()
a:led(1, 1, 15); a:led(4, 64, 7)
eq(dev.data[0][0], 15, "ring 1 led 1 is the first LED (the top)")
eq(dev.data[3][63], 7, "ring 4 led 64 is the last LED of the last ring")
eq(dev.data[1][0], 0, "ring 2 is untouched")
a:led(1, 1, 3, true); eq(dev.data[0][0], 15, "relative: 15 + 3 stays 15 (clamped)")
a:led(1, 1, -20, true); eq(dev.data[0][0], 0, "relative: below 0 stays 0")
a:led(2, 10, 4, true); a:led(2, 10, 5, true); eq(dev.data[1][9], 9, "relative levels add")
a:all(5); eq(dev.data[2][33], 5, "all() sets every LED of every ring")
a:all(0)
for n = 0, 3 do for i = 0, 63 do if dev.data[n][i] ~= 0 then check(false, "all(0) clears ring " .. n .. " led " .. i) end end end
eq(dev.dirty[0], true, "a change marks the ring dirty")
a:refresh(); eq(dev.dirty[0], false, "refresh sends the dirty rings"); eq(dev.refreshed, 2 + 0, "refresh went to the device")
a:intensity(8); eq(dev.intensity, 8, "intensity")

-- segment: a point-to-point arc, 64 LEDs of tau/64 each, fractions fade
local tau = math.pi * 2
a:all(0)
a:segment(1, 0, tau - 1e-9, 15) -- (0 to tau is an empty segment in norns: tau % tau is 0)
local all15 = true
for i = 0, 63 do if dev.data[0][i] ~= 15 then all15 = false end end
check(all15, "segment over the whole ring lights all 64 LEDs")
a:all(0)
a:segment(2, 0, math.pi, 15)
local first, second = 0, 0
for i = 0, 31 do first = first + dev.data[1][i] end
for i = 32, 63 do second = second + dev.data[1][i] end
eq(first, 32 * 15, "a half turn from the top lights the first 32 LEDs (clockwise)")
eq(second, 0, "and not the others")
a:all(0)
a:segment(3, tau - 0.5, 0.5, 10) -- across the top, wrapping
check(dev.data[2][0] > 0 and dev.data[2][63] > 0, "a segment can wrap past the top")
eq(dev.data[2][32], 0, "and leaves the bottom dark")
a:all(0)
a:segment(1, 0, tau / 64 / 2, 10) -- half an LED: half the level
eq(dev.data[0][0], 5, "half an LED lights it at half level")

-- deltas and keys: one call per message, with the numbers the window sent
local got = {}
port.delta = function(n, d) got[#got + 1] = "d" .. n .. ":" .. d end
port.key = function(n, z) got[#got + 1] = "k" .. n .. ":" .. z end
local function feed(fn) got = {}; fn(); return table.concat(got, " ") end
eq(feed(function() _norns.arc.delta(1, 1, 2) end), "d1:2", "a wheel notch (2 ticks) on ring 1")
eq(feed(function() _norns.arc.delta(1, 4, -17) end), "d4:-17", "a drag on ring 4, backwards")
eq(feed(function() _norns.arc.key(1, 3, 1); _norns.arc.key(1, 3, 0) end), "k3:1 k3:0", "ring 3 pressed and let go")
local dd = {}
a.delta = function(n, d) dd[#dd + 1] = n .. ":" .. d end
feed(function() _norns.arc.delta(1, 2, 5) end)
eq(table.concat(dd, " "), "2:5", "the device callback gets it as well, once")

-- no double counting: the window turns a ring by the wheel (2 + 2 ticks) and a mapped MIDI encoder by 100 ticks: they are three messages and the script's sum is the sum of both, not more
a.delta = nil
local sum = {0, 0, 0, 0}
port.delta = function(n, d) sum[n] = sum[n] + d end
for _, d in ipairs({2, 2, 100}) do _norns.arc.delta(1, 1, d) end
eq(sum[1], 104, "wheel and mapped encoder on the same ring add up (no ring is counted twice)")
eq(sum[2] + sum[3] + sum[4], 0, "and no other ring moves")

-- a second (real) arc next to the virtual one: its own device and port, its deltas are its own
local dev2 = new_device()
_norns.arc.add(2, "m0000163", "monome arc", dev2)
local b = Arc.devices[2]
check(b.name ~= a.name, "a real arc has another name")
eq(b.port, 2, "and the second port")
local real = {}
Arc.connect(2).delta = function(n, d) real[#real + 1] = n .. ":" .. d end
for _, d in ipairs({1, 1}) do _norns.arc.delta(2, 2, d) end
eq(table.concat(real, " "), "2:1 2:1", "the real arc's deltas reach its own port")
eq(sum[2], 0, "and not the virtual arc's script")
Arc.connect(2):led(1, 5, 9); eq(dev2.data[0][4], 9, "LEDs go to the arc of that port")
eq(dev.data[0][4], 0, "and not to the other")

-- closing the virtual arc: the device leaves, the vport stays for the next one
_norns.arc.remove(1)
eq(Arc.devices[1], nil, "removed")
check(pcall(function() _norns.arc.delta(1, 1, 1) end) == false, "a delta for a removed arc is an error that the caller logs (matron does not send one)")
_norns.arc.add(3, "m0000002", "monome arc", new_device())
eq(Arc.devices[3].name, "monome arc m0000002", "the arc comes back under the same name (scripts keep their port)")
eq(Arc.devices[3].port, 1, "on the same port")

if fails == 0 then print("arc_virtual_test: ok") else print("arc_virtual_test: " .. fails .. " FAILED") os.exit(1) end
