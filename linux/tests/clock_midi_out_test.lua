-- the clock params of the Linux desktop: scripts written for norns up to 2.7.3 read the bare option param "clock_midi_out" (1 = off, n + 1 = MIDI vport n; Cheat Codes 2 does:
-- params:get("clock_midi_out") ~= 1, and params:set("clock_midi_out", 1) when it sends the clock itself), newer norns (2.7.4 and on, and this repository's lua/core/clock.lua) have the toggles
-- clock_midi_out_1 .. 16. on the desktop both exist and agree; on the device (no NORNS_PLATFORM) nothing is added. run from the repo root:
--   NORNS_PLATFORM=linux lua5.3 linux/tests/clock_midi_out_test.lua   (and without NORNS_PLATFORM: the device case is checked by the same file through a flag)
package.path = "lua/?.lua;lua/core/?.lua;lua/lib/?.lua;" .. package.path
local fails = 0
local function check(ok, what) if not ok then fails = fails + 1; print("FAIL " .. what) end end
local desktop = os.getenv("NORNS_PLATFORM") ~= nil

local function fresh(initial)
  for _, k in ipairs({"core/clock", "core/paramset", "paramset", "clock"}) do package.loaded[k] = nil end
  util = dofile("lua/lib/util.lua")
  package.loaded.util = util
  tab = dofile("lua/lib/tabutil.lua")
  package.loaded.tabutil = tab
  midi = {vports = {}, update_clock_receive = function() end}
  for i = 1, 16 do midi.vports[i] = {name = i == 1 and "virtual" or (i == 3 and "mio" or "none"), connected = (i == 1 or i == 3), clock = function() end} end
  norns = {pmap = {data = {}, rev = {}}, state = {clock = {source = 1, tempo = 90, link_quantum = 4, link_start_stop_sync = 1, midi_out = initial or {}, midi_in = 1, crow_out = 1, crow_out_div = 4, crow_in_div = 4}}}
  _norns = setmetatable({clock = {}}, {__index = function() return function() end end})
  _menu = {rebuild_params = function() end, binarystates = {triggered = {}, on = {}}}
  crow = {output = {}}
  local paramset = dofile("lua/core/paramset.lua")
  params = paramset.new()
  clock = dofile("lua/core/clock.lua")
  clock.run = function() return 1 end
  clock.link = clock.link or {}
  clock.internal = clock.internal or {}
  clock.add_params()
  return clock
end

fresh()
if not desktop then
  check(params.lookup["clock_midi_out"] == nil, "device: no bare clock_midi_out (as upstream's current norns)")
  check(params.lookup["clock_midi_out_1"] ~= nil, "device: the toggles")
else
  check(params.lookup["clock_midi_out"] ~= nil, "desktop: the bare clock_midi_out option exists")
  check(params.lookup["clock_midi_out_1"] ~= nil and params.lookup["clock_midi_out_16"] ~= nil, "desktop: the toggles are still there")
  check(params:get("clock_midi_out") == 1, "off at the start (1 = off)")
  check(params:string("clock_midi_out") == "off", "its first option is off")
  check(params.hidden[params.lookup["clock_midi_out"]] == true, "it is hidden in PARAMS > CLOCK (the per-slot rows are the page)")
  -- the bare one drives the slots (norns up to 2.7.3: one port, n + 1)
  params:set("clock_midi_out", 4)
  check(params:get("clock_midi_out_3") == 1 and params:get("clock_midi_out_1") == 0 and params:get("clock_midi_out_2") == 0, "3 + 1: the slot 3 is on and no other")
  check(norns.state.clock.midi_out[3] == 1, "the stored state of the slot follows")
  params:set("clock_midi_out", 2)
  check(params:get("clock_midi_out_1") == 1 and params:get("clock_midi_out_3") == 0, "2: slot 1 on, slot 3 off (one port at a time, as before)")
  params:set("clock_midi_out", 1)
  local any = false
  for i = 1, 16 do if params:get("clock_midi_out_" .. i) == 1 then any = true end end
  check(not any and params:get("clock_midi_out") == 1, "1: every slot off")
  -- the slots drive the bare one (the lowest slot that is on)
  params:set("clock_midi_out_5", 1)
  check(params:get("clock_midi_out") == 6, "slot 5 on: the bare one says 6")
  params:set("clock_midi_out_2", 1)
  check(params:get("clock_midi_out") == 3, "slots 2 and 5 on: the lowest, 3")
  check(params:get("clock_midi_out_5") == 1, "the other slot is still on (the bare one did not turn it off)")
  params:set("clock_midi_out_2", 0)
  check(params:get("clock_midi_out") == 6, "slot 2 off: back to 6")
  params:set("clock_midi_out_5", 0)
  check(params:get("clock_midi_out") == 1, "all off: 1")
  -- what Cheat Codes 2 does (lib/transport.lua): when it sends the clock to a port itself, the system's clock out for that port is switched off
  params:set("clock_midi_out_3", 1)
  local i = 3
  if params:get("clock_midi_out") - 1 == i then params:set("clock_midi_out", 1) end
  check(params:get("clock_midi_out_3") == 0 and params:get("clock_midi_out") == 1, "params:set(\"clock_midi_out\", 1) as Cheat Codes 2 does it switches the slot off")
  -- and what sync_clock_to_loop does: reads it
  check(params:get("clock_midi_out") ~= 1 == false, "reading it (~= 1) works")
  -- a start with stored toggles: the bare one starts in agreement
  local c = fresh({[3] = 1})
  check(params:get("clock_midi_out") == 4 and params:get("clock_midi_out_3") == 1, "stored slot 3: the bare one starts at 4")
  -- the option names follow the vports (port n: name), as the old param showed them
  midi.vports[2].name = "OP-Z"; midi.vports[2].connected = true
  clock.refresh_midi_out_options()
  check(params:lookup_param("clock_midi_out").options[3]:find("OP-Z", 1, true) ~= nil and params:lookup_param("clock_midi_out").options[3]:find("2", 1, true) ~= nil, "the option for vport 2 names the device")
  check(params:lookup_param("clock_midi_out").options[1] == "off", "and the first stays off")
  -- an index out of the slot range or a nil is not a crash
  check(pcall(function() params:set("clock_midi_out", 17) end), "the last port, 16 + 1")
  check(params:get("clock_midi_out_16") == 1, "slot 16 on")
end

if fails == 0 then print("clock_midi_out_test: all passed") end
os.exit(fails == 0 and 0 or 1)
