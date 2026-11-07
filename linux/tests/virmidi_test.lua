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

-- ---- the module is seen as loaded from /sys/module or /proc/modules (whichever shows it first)
files["/sys/module/snd_virmidi"] = nil
files["/proc/modules"] = "snd_rawmidi 40960 3 snd_seq_midi - Live 0x0000000000000000\nxsnd_virmidi_x 1 0 - Live 0x0\n"
check(not V.loaded(), "a similar name in /proc/modules is not it")
files["/proc/modules"] = "snd_rawmidi 40960 3 snd_virmidi - Live 0x0000000000000000\nsnd_virmidi 16384 0 - Live 0x0000000000000000\n"
check(V.loaded(), "snd_virmidi in /proc/modules: loaded")
files["/proc/modules"] = nil
-- a load whose DONE file was lost: the module is there, so it is ok, not 'running' for ever
files[V.DONE] = nil; files[V.STATUS] = "1000\n"; V.now = function() return 1005 end
files["/sys/module/snd_virmidi"] = true
check(V.load_status() == "ok", "the module is loaded although the command's answer never came: ok")
files["/sys/module/snd_virmidi"] = nil
-- why a load failed, in plain words
local function detail_for(code) files[V.DONE] = code .. "\n"; files[V.STATUS] = "1000\n"; V.now = function() return 1005 end return V.load_status(), V.load_detail() end
local st, d = detail_for(126); check(st == "failed" and d == "cancelled", "126: the dialog was closed or refused: cancelled (" .. tostring(d) .. ")")
st, d = detail_for(127); check(st == "failed" and d == "no_agent", "127: no authentication agent: no_agent (" .. tostring(d) .. ")")
st, d = detail_for(124); check(st == "failed" and d == "timeout", "124: the command ran out of time: timeout (" .. tostring(d) .. ")")
st, d = detail_for(125); check(st == "failed" and d == "no_pkexec", "125: no way to ask: no_pkexec (" .. tostring(d) .. ")")
st, d = detail_for(1); check(st == "failed" and d == "modprobe", "1: modprobe itself failed: modprobe (" .. tostring(d) .. ")")
st, d = detail_for(9); check(st == "failed" and d == "failed", "any other code: failed (" .. tostring(d) .. ")")
st, d = detail_for(0); check(st == "ok" and d == nil, "0: ok, no reason (" .. tostring(d) .. ")")
files[V.DONE] = nil; files[V.STATUS] = "1000\n"; V.now = function() return 1010 end
check(V.load_status() == "running" and V.load_detail() == nil, "waiting: running, no reason")
V.now = function() return 1000 + 400 end
check(V.load_status() == "failed" and V.load_detail() == "timeout", "no answer in time: failed, timeout")
V.now = function() return 1000 end
for _, why in ipairs({"cancelled", "no_agent", "timeout", "no_pkexec", "modprobe", "failed"}) do
  local lines = V.failure_lines(why)
  local text = table.concat(lines, " ")
  check(#lines >= 2 and text:find("sudo modprobe snd-virmidi", 1, true), why .. ": plain lines and the command to type in a terminal: " .. text)
end
check(table.concat(V.failure_lines("cancelled"), " "):upper():find("CLOSED") or table.concat(V.failure_lines("cancelled"), " "):upper():find("CANCEL"), "cancelled says the dialog was closed")
check(table.concat(V.failure_lines("timeout"), " "):upper():find("NO ANSWER"), "timeout says no answer came")
check(table.concat(V.failure_lines("no_agent"), " "):upper():find("AGENT") or table.concat(V.failure_lines("no_agent"), " "):upper():find("DIALOG"), "no_agent names the missing dialog")

-- ---- the card and the Reaper entry (hw:VirMIDI,<device>) follow /proc/asound
files["/proc/asound/cards"] = nil
check(V.card() == nil and #V.hw_entries() == 0, "no card: no entry")
files["/proc/asound/cards"] = " 0 [PCH            ]: HDA-Intel - HDA Intel PCH\n                      HDA Intel PCH at 0xf7210000 irq 130\n 2 [VirMIDI        ]: VirMIDI - VirMIDI\n                      Virtual MIDI Card 1\n"
check(V.card() == 2, "the VirMIDI card is card 2 (" .. tostring(V.card()) .. ")")
files["/proc/asound/card2/midi0"] = "Virtual Raw MIDI (16 ports)\n"
local hw = V.hw_entries()
check(#hw == 1 and hw[1] == "hw:VirMIDI,0", "one device: hw:VirMIDI,0 (" .. table.concat(hw, ",") .. ")")
files["/proc/asound/card2/midi1"] = "Virtual Raw MIDI (16 ports)\n"
hw = V.hw_entries()
check(#hw == 2 and hw[2] == "hw:VirMIDI,1", "two devices: the second is hw:VirMIDI,1 (" .. table.concat(hw, ",") .. ")")
files["/proc/asound/cards"] = " 3 [VirMIDI        ]: VirMIDI - VirMIDI\n                      Virtual MIDI Card 1\n"
files["/proc/asound/card2/midi0"] = nil; files["/proc/asound/card2/midi1"] = nil
files["/proc/asound/card3/midi0"] = "Virtual Raw MIDI (16 ports)\n"
check(V.card() == 3 and V.hw_entries()[1] == "hw:VirMIDI,0", "the card number follows the system (card 3), the device index is the device's")
files["/proc/asound/cards"] = " 1 [Device         ]: USB-Audio - USB Audio Device\n                      C-Media at usb-0000:00:14.0-1\n"
check(V.card() == nil, "another card is not it")

os.getenv = real_getenv
if fails == 0 then print("virmidi_test: all passed") end
os.exit(fails == 0 and 0 or 1)
