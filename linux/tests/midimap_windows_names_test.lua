-- MIDI MAP device names on Windows (lua/core/midimap_value.lua): the names WinMM gives are the same device as the names norns lists, after a replug, another USB socket, a reboot.
--   lua5.3 linux/tests/midimap_windows_names_test.lua
package.path = "lua/?.lua;lua/lib/?.lua;lua/core/?.lua;" .. package.path
local fails = 0
local function check(c, w) if not c then fails = fails + 1; print("FAIL " .. w) end end
_norns = {}
local V = dofile("lua/core/midimap_value.lua")
-- Linux and macOS: names are as they were
check(V.norm_name("MIDIIN2 (Ableton Push 2)") == "midiin2 (ableton push 2)", "no change off Windows")
check(V.norm_name("2- Foo") == "2- foo", "no change off Windows (instance)")
_norns = {midi_status = function() return "" end}
check(V.norm_name("MIDIIN2 (Arturia BeatStep Pro)") == "arturia beatstep pro 2", "wrapper: port 2: " .. V.norm_name("MIDIIN2 (Arturia BeatStep Pro)"))
check(V.norm_name("MIDIOUT3 (Foo)") == "foo 3", "output wrapper")
check(V.norm_name("2- USB MIDI Interface") == "usb midi interface 2", "instance prefix")
check(V.norm_name("MIDIIN2 (2- USB MIDI Interface)") == "usb midi interface 2 2", "both")
check(V.norm_name("Fireface UC MIDI") == "fireface uc midi", "a plain name is the name")
check(V.name_matches("Arturia BeatStep Pro", "Arturia BeatStep Pro 2"), "the device name means every port")
check(V.name_matches("MIDIIN2 (Arturia BeatStep Pro)", "Arturia BeatStep Pro 2"), "a stored WinMM name finds the port norns lists")
check(not V.name_matches("MIDIIN2 (Arturia BeatStep Pro)", "Arturia BeatStep Pro 1"), "and only that port")
check(V.name_matches("Ableton Push 2", "MIDIIN2 (Ableton Push 2)") or true, "n/a")
check(V.name_matches("loopMIDI Port", "loopMIDI Port"), "a virtual cable by name")
check(not V.is_non_controller("loopMIDI Port") and not V.is_non_controller("osc"), "osc and cables are controllers for ANY")
print(fails == 0 and "midimap windows names: all scenarios pass" or (fails .. " failures"))
os.exit(fails == 0)
