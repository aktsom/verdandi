-- SYSTEM > DEVICES with the ALSA raw MIDI route (lua/core/menu/devices.lua, lua/core/virmidi.lua): while NORNS_ALSA_MIDI_OUT_TO is set there is an entry VIRMIDI with the guide; K3 on it when the module is not
-- loaded asks once and loads it without a terminal; the page says what is happening and which Reaper entry to enable. run from the repo root:
--   NORNS_PLATFORM=linux NORNS_ALSA_MIDI_OUT_TO=VirMIDI lua5.3 linux/tests/devices_virmidi_test.lua
package.path = "lua/?.lua;lua/core/?.lua;lua/lib/?.lua;" .. package.path
local fails = 0
local function check(ok, what) if not ok then fails = fails + 1; print("FAIL " .. what) end end
local frame = {}
screen = setmetatable({}, {__index = function() return function() end end})
screen.clear = function() frame = {} end
screen.text = function(s) frame[#frame + 1] = "L:" .. tostring(s) end
screen.text_right = function(s) frame[#frame + 1] = "R:" .. tostring(s) end
screen.text_extents = function(s) return #tostring(s) * 5 end
local function drawn(s) for _, t in ipairs(frame) do if t:find(s, 1, true) then return true end end return false end
local function lines() local r = {} for _, t in ipairs(frame) do if t:match("^[LR]:") then r[#r + 1] = t:sub(3) end end return r end
_menu = {redraw = function() end, set_page = function(p) _menu.page = p end}
package.loaded['core/keyboard'] = {keymap = {us = {}}, selected_map = "us"}
midi = {devices = {}, vports = {}}; grid = {devices = {}, vports = {}}; arc = {devices = {}, vports = {}}; hid = {devices = {}, vports = {}}
for i = 1, 16 do midi.vports[i] = {name = "none"} end
for i = 1, 4 do grid.vports[i] = {name = "none"}; arc.vports[i] = {name = "none"}; hid.vports[i] = {name = "none"} end
-- the C side: how many ALSA ports Verdandi out is linked to, and their names
local link = {0, ""}
_norns = {alsa_midi_link = function() return link[1], link[2] end}
-- the module, faked
local state = {loaded = false, status = "idle", started = 0}
package.loaded['core/virmidi'] = {
  to = function() return "VirMIDI" end, configured = function() return true end, wants_module = function() return true end,
  loaded = function() return state.loaded end, load_status = function() return state.status end,
  start_load = function() state.started = state.started + 1; state.status = "running" return true end,
  COMMAND = "sudo modprobe snd-virmidi midi_devs=1",
  guide_lines = function() return {"REAPER READS RAW MIDI ONLY.", "THE VIRTUAL MIDI CARD", "SNDVIRMIDI BRIDGES IT."} end,
  permanent_lines = function() return {"/etc/modules-load.d/", "snd-virmidi"} end,
  reaper_entry = function(c) return c end, reaper_hw = function(c) return "hw:VirMIDI,0" end,
}
local page = dofile("lua/core/menu/devices.lua")
local function press(n) page.key(n, 1) end

page.init(); page.redraw()
check(page.len == 6 and drawn("VIRMIDI >"), "the setting is on: SYSTEM > DEVICES has a VIRMIDI entry (" .. page.len .. ")")
page.pos = 6; press(3)
check(page.mode == "virmidi", "K3 opens the page"); page.redraw()
check(drawn("REAPER READS RAW MIDI"), "not loaded: the guide")
check(drawn("K3") and drawn("K2"), "and the keys")
local ls = lines(); local wide = false
for _, l in ipairs(ls) do if #l > 25 and not l:match("^K[23]") then wide = true end end
check(not wide, "no line wider than the screen: " .. table.concat(ls, " | "))
-- K2 back, nothing runs
press(2); check(page.mode == "type" and state.started == 0, "K2 goes back and runs nothing")
-- K3 asks once
page.pos = 6; press(3); press(3)
check(page.mode == "confirm_virmidi" and state.started == 0, "K3 asks first, nothing runs yet"); page.redraw()
check(drawn("LOAD SND-VIRMIDI") and drawn("K3 YES"), "the question says what happens (" .. table.concat(lines(), " | ") .. ")")
check(drawn("PASSWORD"), "and that a password may be asked")
press(2); check(page.mode == "virmidi" and state.started == 0, "K2 on the question changes nothing")
press(3); press(3)
check(state.started == 1 and page.mode == "virmidi", "K3 yes starts the load once"); page.redraw()
check(drawn("WAITING"), "while it runs the page says so: " .. table.concat(lines(), " | "))
-- failed: the command to type
state.status = "failed"; page.redraw()
check(drawn("FAILED") and drawn("modprobe"), "failed: the command to type is shown (" .. table.concat(lines(), " | ") .. ")")
-- loaded, nothing linked yet
state.loaded = true; state.status = "ok"; page.redraw()
check(drawn("LOADED"), "loaded: says so")
check(drawn("WAITING FOR A PORT") or drawn("NO PORT"), "and that no port matches yet (" .. table.concat(lines(), " | ") .. ")")
-- linked: the Reaper entry
link = {1, "VirMIDI 3-0"}; page.redraw()
check(drawn("VirMIDI 3-0") and drawn("REAPER"), "linked: names the port and says which Reaper entry to enable (" .. table.concat(lines(), " | ") .. ")")
check(drawn("hw:VirMIDI,0"), "with its hw form")
-- the permanent setup is one more key on the page
press(3); page.redraw()
check(drawn("modules-load.d") or drawn("snd-virmidi"), "K3 on a loaded page shows how to keep it after a reboot (" .. table.concat(lines(), " | ") .. ")")
press(2); check(page.mode == "virmidi" or page.mode == "type", "K2 goes back")

-- the setting off: no entry
package.loaded['core/virmidi'].configured = function() return false end
page = dofile("lua/core/menu/devices.lua"); page.init(); page.redraw()
check(page.len == 5 and not drawn("VIRMIDI"), "the setting off: the usual five entries")

if fails == 0 then print("devices virmidi: all passed") end
os.exit(fails == 0 and 0 or 1)
