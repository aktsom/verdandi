-- SYSTEM > DEVICES when serialosc has the grid (lua/core/menu/devices.lua, lua/core/serialosc_stop.lua; KNOWN-ISSUES 31). run from the repo root:
--   NORNS_PLATFORM=linux lua5.3 linux/tests/devices_serialosc_test.lua
-- the note's guide is on the norns screen too, in short wrapped lines, as an entry that is only there while the note is; K3 asks once, K3 again stops serialosc without a terminal (a command that does not
-- ask for a password: if the system refuses, the command to type is shown); K2 changes nothing; the entry goes when serialosc goes.
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
local redraws = 0
_menu = {redraw = function() redraws = redraws + 1 end, set_page = function(p) _menu.page = p end}
package.loaded['core/keyboard'] = {keymap = {us = {}}, selected_map = "us"}
midi = {devices = {}, vports = {}}; grid = {devices = {}, vports = {}}; arc = {devices = {}, vports = {}}; hid = {devices = {}, vports = {}}
for i = 1, 16 do midi.vports[i] = {name = "none"} end
for i = 1, 4 do grid.vports[i] = {name = "none"}; arc.vports[i] = {name = "none"}; hid.vports[i] = {name = "none"} end
local stops, stop_ok = 0, true
package.loaded['core/serialosc_stop'] = {COMMAND = "sudo systemctl stop serialosc.service", stop = function() stops = stops + 1 return stop_ok end}
local page = dofile("lua/core/menu/devices.lua")
local function press(n) page.key(n, 1) end
local NOTE = "GRID: serialosc has this grid\nStop it: sudo systemctl stop serialosc.service\n(later: sudo systemctl start serialosc.service)"

-- no note: the list is the usual five
_menu.grid_note = nil
page.init(); page.redraw()
check(page.len == 5 and not drawn("SERIALOSC"), "without the note SYSTEM > DEVICES has its usual five entries (" .. page.len .. ")")
-- the note: one more entry
_menu.grid_note = NOTE
page.init(); page.redraw()
check(page.len == 6 and drawn("SERIALOSC >"), "with the note there is a SERIALOSC entry (" .. page.len .. ")")
page.pos = 6; press(3)
check(page.mode == "serialosc", "K3 on it opens the guide")
page.redraw()
local ls = lines()
local ok_width, ok_count = true, #ls <= 8
for _, l in ipairs(ls) do if #l > 25 and not l:match("^K[23]") then ok_width = false end end
check(ok_width, "a line of the guide is wider than the screen (25 characters): " .. table.concat(ls, " | "))
check(ok_count, "the guide has more lines than the screen holds")
check(drawn("serialosc has this"), "the guide says that serialosc has the grid")
check(drawn("systemctl"), "and the command")
check(drawn("K3") and drawn("K2"), "and the keys")
-- K2 goes back, nothing runs
press(2); check(page.mode == "type" and stops == 0, "K2 goes back and runs nothing")
page.pos = 6; press(3); press(3)
check(page.mode == "confirm_serialosc" and stops == 0, "K3 in the guide asks once and runs nothing yet"); page.redraw()
check(drawn("STOP SERIALOSC") and drawn("K3 YES"), "the question says what happens")
press(2); check(page.mode == "serialosc" and stops == 0, "K2 on the question changes nothing")
-- yes: runs the stop, says so
press(3); press(3)
check(stops == 1, "K3 yes ran the stop command once"); check(page.mode == "serialosc", "and stays in the guide"); page.redraw()
check(drawn("STOPPED") and drawn("REPLUG"), "success says it and to replug the grid (" .. table.concat(lines(), " | ") .. ")")
-- refused by the system: the command to type
stop_ok = false; press(3); press(3)
check(stops == 2, "a second try ran the command again"); page.redraw()
check(drawn("FAILED"), "a refusal says so")
do local wide = false for _, l in ipairs(lines()) do if #l > 25 and not l:match("^K[23]") then wide = true end end check(not wide, "a line of the refusal is wider than the screen: " .. table.concat(lines(), " | ")) end; check(drawn("sudo systemctl"), "and shows the command to type")
-- key releases and encoders do nothing
local before = stops
page.key(3, 0); page.key(3, 0); page.enc(2, 1); page.enc(3, 1)
check(stops == before, "a release or an encoder started the command")
-- the note goes: the page leaves the guide and the entry is gone
_menu.grid_note = nil
page.redraw()
check(page.mode == "type" and page.len == 5 and page.pos <= 5, "when serialosc is gone the guide is left and the list is the usual five (mode " .. tostring(page.mode) .. ", len " .. page.len .. ")")
page.redraw(); check(not drawn("SERIALOSC"), "and nothing says SERIALOSC")
if fails == 0 then print("devices serialosc: all passed") end
os.exit(fails == 0 and 0 or 1)
