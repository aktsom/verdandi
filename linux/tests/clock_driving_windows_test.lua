-- the line in PARAMS > CLOCK that says what drives the clock (Windows build; lua/core/clock.lua clock_driving_text). the function is cut out of the file and run with fakes.
--   lua5.3 linux/tests/clock_driving_windows_test.lua
local src = io.open("lua/core/clock.lua"):read("a")
local fn = src:match("(local function clock_driving_text%(%).-\nend)\n")
assert(fn, "clock_driving_text not found")
local fails = 0
local function check(c, w) if not c then fails = fails + 1; print("FAIL " .. w) end end
local source, tempo, status, peers, sync = "internal", 120, "", 0, false
params = {string = function() return source end}
clock = {get_tempo = function() return tempo end}
_norns = {midi_status = function() return status end, link_info = function() return {peers = peers, sync = sync} end}
local f = load(fn .. "\nreturn clock_driving_text")()
check(f() == "driving: internal, 120.0 bpm", "internal: " .. f())
source = "midi"
check(f() == "midi: no clock coming in", "midi without ticks says so: " .. f())
status = "devices=2\nopen=Fireface UC MIDI\nclock_in=Fireface UC MIDI\n"; tempo = 97.5
check(f() == "driving: midi from Fireface UC MIDI, 97.5 bpm", "midi with ticks names the device: " .. f())
source = "link"; peers = 0
check(f() == "link on: no peers yet, start/stop sync off", "link without peers: " .. f())
peers = 1
check(f() == "driving: link, 1 peer, start/stop sync off", "link with one peer: " .. f())
peers = 3; sync = true
check(f() == "driving: link, 3 peers, start/stop sync on", "link with peers: " .. f())
source = "crow"
check(f() == "driving: crow", "other sources by name")
print(fails == 0 and "clock driving (windows): all scenarios pass" or (fails .. " failures"))
os.exit(fails == 0)
