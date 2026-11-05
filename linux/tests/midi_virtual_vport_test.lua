-- the virtual MIDI device of the Linux desktop is the JACK one ("virtual", in and out): it takes the first free vport like any device (the DAW's clock and notes reach midi.connect() with no argument),
-- while upstream's "virtual" (the ALSA virtual port, the device and the Mac) is still not given a vport by itself. run from the repo root:
--   lua5.3 linux/tests/midi_virtual_vport_test.lua
package.path = "lua/?.lua;lua/core/?.lua;lua/lib/?.lua;" .. package.path
local fails = 0
local function check(ok, what) if not ok then fails = fails + 1; print("FAIL " .. what) end end
util = {clamp = function(x, lo, hi) return math.max(lo, math.min(hi, x)) end}
package.loaded.util = util
norns = {none = function() end}
tab = require "tabutil"
params = {lookup = {}}
midi = nil
_norns = {midi = {}, midi_send = function(dev, data) _norns.sent = {dev = dev, data = data} end}
_menu = {rebuild_params = function() end}
midi = dofile("lua/core/midi.lua")
local function fresh() for i = 1, 16 do midi.vports[i].name = "none" end for k in pairs(midi.devices) do midi.devices[k] = nil end end

fresh()
-- the C side says (4th argument of _norns.midi.add) that this "virtual" is the JACK device
_norns.midi.add(1, "virtual", "devptr", true)
check(midi.vports[1].name == "virtual", "the JACK virtual device takes vport 1 (the first free one)")
_norns.midi.add(2, "keyboard-ish", "dev2")
check(midi.vports[2].name == "keyboard-ish", "the next device the next vport")

fresh()
_norns.midi.add(1, "virtual", "alsaptr") -- upstream's: no flag
check(midi.vports[1].name == "none", "upstream's virtual device (no flag) is not given a vport by itself")
_norns.midi.add(2, "mio", "mioptr")
check(midi.vports[1].name == "mio", "a real device takes vport 1 then")

-- sending to it: the device handle is what the C side gets
fresh()
_norns.midi.add(1, "virtual", "devptr", true)
local m = midi.connect(1)
m:note_on(60, 100, 1)
check(_norns.sent and _norns.sent.dev == "devptr" and _norns.sent.data[1] == 0x90 and _norns.sent.data[2] == 60 and _norns.sent.data[3] == 100, "m:note_on goes to the device with the bytes 90 3c 64")
m:clock()
check(_norns.sent.data[1] == 0xf8, "m:clock sends f8")

if fails == 0 then print("midi_virtual_vport_test: all passed") end
os.exit(fails == 0 and 0 or 1)
