-- lua/core/virmidi.lua: the guided setup of the ALSA raw MIDI route for Reaper (snd-virmidi). run from the repo root:
--   lua5.3 linux/tests/virmidi_test.lua
-- the setting (NORNS_ALSA_MIDI_OUT_TO), whether the kernel module is loaded, the notes (what to say and when), the Reaper entry to enable, the load without a terminal (pkexec, never sudo, the command to type when it
-- cannot be done), and the permanent setup text. the system is faked: a table of files and a recorder for commands.
package.path = "lua/?.lua;lua/core/?.lua;lua/lib/?.lua;" .. package.path
local fails = 0
local function check(ok, what) if not ok then fails = fails + 1; print("FAIL " .. what) end end
local real_getenv = os.getenv
local env = {}
os.getenv = function(k) if env[k] ~= nil then return env[k] ~= false and env[k] or nil end return real_getenv(k) end
util = dofile("lua/lib/util.lua"); package.loaded.util = util
local V = require 'core/virmidi'

-- ---- the setting
env.NORNS_ALSA_MIDI_OUT_TO = nil
check(V.to() == "" and not V.configured(), "off by default")
env.NORNS_ALSA_MIDI_OUT_TO = "VirMIDI"
check(V.to() == "VirMIDI" and V.configured(), "on with a prefix")
env.NORNS_ALSA_MIDI_OUT_TO = "  "
check(not V.configured(), "blanks are off")
env.NORNS_ALSA_MIDI_OUT_TO = "VirMIDI"
check(V.wants_module("VirMIDI") and V.wants_module("virmidi 3-0") and V.wants_module("Virtual Raw MIDI 3-0") and V.wants_module("Synth;VirMIDI"), "a prefix that names the virtual MIDI card needs the module")
check(not V.wants_module("Arturia BeatStep Pro") and not V.wants_module("Midi Through") and not V.wants_module(""), "another prefix does not")

-- ---- the module
local files = {}
V.exists = function(p) return files[p] == true end
check(not V.loaded(), "not loaded: no /sys/module/snd_virmidi")
files["/sys/module/snd_virmidi"] = true
check(V.loaded(), "loaded: /sys/module/snd_virmidi is there")
files["/sys/module/snd_virmidi"] = nil

-- ---- the notes
local function N(t) t.to = t.to or "VirMIDI"; return V.note(t) end
check(N({to = ""}) == nil, "setting off: no note")
local n = N({count = 0, loaded = false})
check(n and n:find("snd-virmidi", 1, true) and n:find("DEVICES", 1, true), "not loaded: the note says so and where to go: " .. tostring(n))
check(#n <= 78, "a note is one line of the window (at most 78 characters): " .. #n)
n = N({count = 0, loaded = true})
check(n and n:find("VirMIDI", 1, true) and n:find("no port", 1, true) or (n and n:lower():find("waiting", 1, true)), "loaded, nothing matches yet: it says it waits: " .. tostring(n))
check(N({to = "Arturia BeatStep Pro", count = 0, loaded = false}) == nil, "a prefix that is not the virtual card: no module note")
n = N({count = 1, names = "VirMIDI 3-0", loaded = true, since = 100, now = 105})
check(n and n:find("REAPER", 1, true) and n:find("VirMIDI 3-0", 1, true), "just connected: the Reaper entry to enable: " .. tostring(n))
check(#n <= 78, "also one line: " .. #n)
check(N({count = 1, names = "VirMIDI 3-0", loaded = true, since = 100, now = 130}) == nil, "after 20 seconds the note goes (the page keeps the text)")
n = N({count = 1, names = "VirMIDI 3-0, VirMIDI 3-1", loaded = true, since = 100, now = 101})
check(n and n:find("VirMIDI 3-0", 1, true), "several: the first is named")

-- ---- the Reaper entry
check(V.reaper_entry("VirMIDI 3-0") == "VirMIDI 3-0" and V.reaper_hw("VirMIDI 3-0") == "hw:VirMIDI,0" and V.reaper_hw("VirMIDI 5-2") == "hw:VirMIDI,2" and V.reaper_hw("Synth") == nil, "the name to enable and its hw form")

-- ---- the load, without a terminal
local ran = {}
V.exec = function(cmd) ran[#ran + 1] = cmd return true end
V.is_root = function() return false end
V.have = function(prog) return prog == "pkexec" end
V.read = function(p) return files[p] end
V.write = function(p, text) files[p] = text return true end
V.remove = function(p) files[p] = nil end
V.now = function() return 1000 end
check(V.load_status() == "idle", "nothing started: idle")
check(V.start_load() == true, "start: launched")
check(#ran == 1 and ran[1]:find("pkexec", 1, true) and ran[1]:find("modprobe snd-virmidi", 1, true) and ran[1]:find("midi_devs=1", 1, true), "it asks polkit (pkexec) to modprobe snd-virmidi midi_devs=1: " .. tostring(ran[1]))
check(not ran[1]:find("sudo", 1, true), "never sudo")
check(ran[1]:find("&%s*$") ~= nil or ran[1]:find("&", 1, true), "in the background (the password dialog must not freeze norns)")
check(V.load_status() == "running", "running while the dialog is open")
files[V.DONE] = "0\n"
check(V.load_status() == "ok", "the command finished with 0: ok")
files[V.DONE] = "126\n"
check(V.load_status() == "failed", "a refusal or a missing agent: failed")
files[V.DONE] = nil; V.remove(V.STATUS)
-- a start that was never answered for two minutes is failed, not running for ever
check(V.start_load() == true, "start again")
V.now = function() return 1000 + 200 end
check(V.load_status() == "failed", "no answer for 2 minutes: failed")
V.now = function() return 1000 end
-- no pkexec: nothing is started, and it is failed at once, the command to type is the answer
ran = {}; files[V.DONE] = nil; V.remove(V.STATUS)
V.have = function() return false end
check(V.start_load() == false and #ran == 0 and V.load_status() == "failed", "without pkexec: nothing runs, failed")
-- already root: modprobe directly
V.have = function(prog) return prog == "pkexec" end
V.is_root = function() return true end
V.remove(V.STATUS); files[V.DONE] = nil
V.start_load()
check(ran[1] and ran[1]:find("modprobe snd-virmidi", 1, true) and not ran[1]:find("pkexec", 1, true), "root: modprobe directly")
-- already loaded: nothing to start
files["/sys/module/snd_virmidi"] = true; ran = {}
check(V.start_load() == false and #ran == 0, "loaded already: nothing is started")

-- ---- what to type, and the permanent setup
check(V.COMMAND == "sudo modprobe snd-virmidi midi_devs=1", "the command to type")
local perm = table.concat(V.permanent_lines(), "\n")
check(perm:find("/etc/modules-load.d/", 1, true) and perm:find("snd-virmidi", 1, true) and perm:find("midi_devs=1", 1, true) and perm:find("/etc/modprobe.d/", 1, true), "the permanent setup names both files and the option")
check(#V.guide_lines() >= 3, "a guide of a few lines")

os.getenv = real_getenv
if fails == 0 then print("virmidi_test: all passed") end
os.exit(fails == 0 and 0 or 1)
