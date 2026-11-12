-- the MIC / OFF / SYS switch in the Windows build (lua/core/menu.lua with _norns.mic_input, _norns.app_input and _norns.audio_input from norns.exe): OFF at every start (no feedback), nothing remembered,
-- MIC without an input device or SYS without a loopback stay OFF and say why. run from the repo root:
--   lua5.3 linux/tests/input_windows_test.lua
local src = io.open("lua/core/menu.lua"):read("a")
local block = src:match("(%-%- MIC: what norns' input hears.-)\nhook%.system_post_startup")
assert(block, "input block not found")
local mic_off, kept = os.tmpname(), os.tmpname()
os.remove(mic_off)
os.remove(kept)
block = block:gsub('"/home/we/%.mic%-off"', string.format("%q", mic_off))
block = block:gsub('"/home/we/%.norns%-input"', string.format("%q", kept))
local fails = 0
local function check(cond, what) if not cond then fails = fails + 1; print("FAIL " .. what) end end

local mic, sys, can_mic, can_sys, warn = false, false, true, true, nil
local sys_available = true
local sys_why = nil
local function actual()
  if sys and can_sys then return "system", "" end
  if mic and can_mic then return "mic", "" end
  local why = ""
  if sys then why = sys_why or "no loopback device" elseif mic then why = "MIC needs an INPUT: choose one on SYSTEM > AUDIO" end
  return "off", why
end
util = {os_capture = function() error("no jack_lsp on Windows") end, file_exists = function() return false end}
_norns = {
  mic_input = function(live) mic = live end,
  app_input = function(target) sys = target == "system" end,
  audio_input = actual,
  audio_info = function() return {sys_available = sys_available} end,
  set_warning = function(t) warn = t end,
  show_control = function() end,
}
_menu = {}
load(block)()

-- the start: OFF, even when a marker file or audio.conf would say MIC
local f = io.open(kept, "w") f:write("system\n\n\n") f:close()
_menu.check_mic()
check(_menu.input == "off" and not mic and not sys, "the start is OFF: nothing is routed")
os.remove(kept)

_menu.set_input("mic")
check(_menu.input == "mic" and mic, "MIC: the chosen input is routed")
_menu.next_input()
check(_menu.input == "system" and sys and not mic, "the button goes MIC > SYS")
_menu.next_input()
check(_menu.input == "off" and not sys and not mic, "then OFF")
_menu.next_input()
check(_menu.input == "mic", "and MIC again")
check(io.open(kept) == nil, "nothing is remembered for the next start")

can_mic = false
_menu.set_input("off")
_menu.set_input("mic")
check(_menu.input == "off", "MIC with no input device stays OFF")
check(warn and warn:find("MIC needs an INPUT: choose one on SYSTEM > AUDIO", 1, true), "and says why on the device: " .. tostring(warn))
-- the button still reaches SYS when MIC could not open (no INPUT chosen)
_menu.set_input("off")
_menu.next_input()
check(_menu.input == "off" and warn and warn:find("MIC needs an INPUT", 1, true), "button: MIC without an INPUT stays OFF with the note")
_menu.next_input()
check(_menu.input == "system" and sys, "button: the next press reaches SYS without an INPUT")
check(warn and warn:find("SYS can feed back; lower softcut or mute if it howls", 1, true), "SYS on: the hint about feedback: " .. tostring(warn))
_menu.next_input()
check(_menu.input == "off", "button: SYS > OFF")
_menu.next_input()
check(_menu.input == "off" and warn and warn:find("MIC needs an INPUT", 1, true), "button: and MIC again (with its note)")
-- exclusive or ASIO: SYS returns to OFF with the reason, and the next press goes on to MIC rather than doing nothing
can_sys = false; sys_why = "SYS only hears Windows sound in normal mode"
_menu.set_input("off"); _menu.next_input(); _menu.next_input()
check(_menu.input == "off" and warn and warn:find("SYS only hears Windows sound in normal mode", 1, true), "exclusive/ASIO: SYS stays OFF with the reason: " .. tostring(warn))
can_mic = true
_menu.next_input()
check(_menu.input == "mic", "the press after a refused SYS is not lost: MIC")
can_sys = true; sys_why = nil
_menu.set_input("off")
_menu.set_input("mic")
check(_menu.input == "mic" and not (warn or ""):find("INPUT") and not (warn or ""):find("feed back"), "a working input clears the note")
can_sys = false; sys_why = nil
_menu.set_input("system")
check(_menu.input == "off" and warn and warn:find("no loopback device", 1, true), "SYS without a loopback stays OFF with the reason")
-- SYS is not offered when this PortAudio has no WASAPI loopback: the button goes MIC > OFF, and a direct choice stays OFF with the reason
sys_available = false
_menu.set_input("off")
_menu.next_input()
check(_menu.input == "mic", "no loopback: OFF > MIC")
_menu.next_input()
check(_menu.input == "off" and not sys, "no loopback: MIC > OFF (SYS is left out)")
os.remove(mic_off)
os.remove(kept)
print(fails == 0 and "input (windows): all scenarios pass" or (fails .. " failures"))
os.exit(fails == 0)
