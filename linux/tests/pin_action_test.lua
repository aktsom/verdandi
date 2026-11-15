-- MIDI MAP on Windows: the PIN action (the KEYS slot): its name, learning it with the port, a mapped note toggling it once, the old "keys" lines of a file read as "pin", Linux keeps "keys". run from the repo root:
--   NORNS_PLATFORM=linux lua5.3 linux/tests/midimap_layer_test.lua
--   NORNS_PLATFORM=windows lua5.3 linux/tests/pin_action_test.lua   (and NORNS_PLATFORM=linux for the Linux half)
-- key is released when it must be, the learn states and every way out of them
package.path = "lua/?.lua;lua/core/?.lua;lua/lib/?.lua;" .. package.path
local tmp = os.tmpname()
os.remove(tmp)
os.execute("mkdir -p " .. tmp)
local real_open, real_remove, real_rename, real_execute = io.open, os.remove, os.rename, os.execute
local function map(p) return (p:gsub("^/home/we", tmp)) end
io.open = function(p, m) return real_open(map(p), m) end
os.remove = function(p) return real_remove(map(p)) end
os.rename = function(a, b) return real_rename(map(a), map(b)) end
os.execute = function(cmd) return real_execute((cmd:gsub("/home/we", tmp))) end
local real_print = print
local printed = {}
print = function(...) local a = ... printed[#printed + 1] = tostring(a) end

local fails = 0
local function check(ok, what) if not ok then fails = fails + 1; real_print("FAIL " .. what) end end
local function eq(a, b, what) check(a == b, what .. ": got " .. tostring(a) .. ", wanted " .. tostring(b)) end
local function logged(part) for _, l in ipairs(printed) do if l:find(part, 1, true) then return true end end return false end

tab = require 'tabutil'
util = {scandir = function(dir) local out = {} local p = io.popen("ls -p '" .. map(dir) .. "' 2>/dev/null") for l in p:lines() do out[#out + 1] = l end p:close() return out end,
  clamp = function(x, lo, hi) return math.max(lo, math.min(hi, x)) end, time = function() return 0 end}
package.loaded.util = util

-- the world: what the layer sends out, and the pieces of norns it listens to
local out = {}
local function reset_out() out = {} end
local T = 100 -- the clock
_norns = {midi = {},
  show_control = function(kind, n, v) out[#out + 1] = "show:" .. kind .. ":" .. n .. ":" .. v end,
  key = function(n, z) out[#out + 1] = "key:" .. n .. ":" .. z end,
  enc = function(n, d) out[#out + 1] = "enc:" .. n .. ":" .. d end,
  toast = function(t) out[#out + 1] = "toast:" .. t end,
  midimap_arm = function(m) out[#out + 1] = "arm:" .. m end,
  midimap_show = function(s, n) out[#out + 1] = "ring:" .. s .. ":" .. n end,
  arc_drag_config = function(m) _G.DRAG_SENT = (_G.DRAG_SENT or "") .. "drag:" .. m .. " " end,
  arc_turn = function(n, ticks) out[#out + 1] = "arc:" .. n .. ":" .. ticks; return _G.ARC_OPEN ~= false end}
local function acts() local r = {} for _, o in ipairs(out) do if o:match("^key:") or o:match("^enc:") then r[#r + 1] = o end end return table.concat(r, " ") end
params = {lookup = {}, lookup_param = function(self, id) return {name = "Param " .. tostring(id)} end}
_menu = {rebuild_params = function() end, page = "MIDIMAP", mode = true, redraw = function() end}
pmap = require 'core/pmap'
local pmap_calls = {}
norns = {pmap = pmap, state = {shortname = "testscript"}, none = function() end,
  menu_midi_event = function(data, dev) pmap_calls[#pmap_calls + 1] = {data[1], data[2], data[3], dev} end}
midi = require 'core/midi'
local V = require 'core/midimap_value'
-- these tests are about what the layer does with messages (filters, clashes, learn, held keys): they were written with the speeds of the OLD sensitivity scale (sens 5 = one step per unit); the new scale's own numbers are in midimap_sens_test.lua
for k = 1, 9 do V.SENS_SPEED[k] = 2 ^ ((k - 5) / 2) end
local S = require 'core/midimap_settings'
S.log = function() end
local mm = require 'core/midimap'
norns.midimap = mm
mm.clock = function() return T end
mm.load()

local function add(id, name) _norns.midi.add(id, name, "ptr" .. id) end
add(1, "virtual"); add(2, "mio"); add(3, "iii grid"); add(4, "Verdandi keys"); add(5, "Push 2")
local function send(id, bytes) _norns.midi.event(id, bytes) end
local function cc(id, ch, num, val) send(id, {0xB0 + ch - 1, num, val}) end
local function note_on(id, ch, n, vel) send(id, {0x90 + ch - 1, n, vel}) end
local function note_off(id, ch, n) send(id, {0x80 + ch - 1, n, 0}) end
local function setup(fn) S.load(); S.select_preset("NONE"); S.set_clash("params"); for _, a in ipairs(S.ARC_IDS) do S.clear(a) end; S.set_arc_keys(true); S.set_arc_keys_accel(false); mm.load(); reset_out(); T = T + 100; if fn then fn() end; mm.changed() end
local WINDOWS = os.getenv("NORNS_PLATFORM") == "windows"
local function learning() return mm.learn.state end
local function setup2() S.load(); S.select_preset("NONE"); mm.load(); reset_out(); T = T + 100 end
local function has(list, id) for _, v in ipairs(list) do if v == id then return true end end return false end
local function wa() local r = {} for _, o in ipairs(out) do if o:match("^wa:") then r[#r + 1] = o end end return table.concat(r, " ") end
_norns.window_action = function(name) out[#out + 1] = "wa:" .. name end
add(11, "Ableton Push 2 1"); add(12, "Ableton Push 2 2")

if WINDOWS then
  check(has(S.ACTION_IDS, "pin") and not has(S.ACTION_IDS, "keys"), "Windows: the action is pin, there is no keys")
  eq(S.ACTION_IDS[8], "pin", "pin is in the place of keys (the 8th of 14)")
  eq(#S.ACTION_IDS, 14, "still 14 actions")
  -- learned from a note: the port is stored (like every other action)
  setup2()
  mm.start_listen_action("pin"); note_on(12, 1, 44, 100)
  eq(S.state.actions.pin.type, "note", "pin learned from a note"); eq(S.state.actions.pin.num, 44, "its number")
  eq(S.state.actions.pin.dev, "Ableton Push 2 2", "the learned port is stored")
  mm.cancel()
  -- a press from the learned port toggles it once; the same note from the other port and a release do nothing
  reset_out(); T = T + 1
  note_on(11, 1, 44, 100); note_off(11, 1, 44)
  eq(wa(), "", "the same note from the other port does nothing")
  note_on(12, 1, 44, 100); note_off(12, 1, 44)
  eq(wa(), "wa:pin", "a press from the learned port is one pin action (the release is nothing)")
  -- the master switch of the actions
  reset_out(); S.set_actions_on(false); T = T + 1; note_on(12, 1, 44, 100); eq(wa(), "", "with the actions switched off nothing is toggled"); S.set_actions_on(true)
  -- saved and read back: the file says act.pin.*
  setup2()
  eq(S.state.actions.pin.num, 44, "the mapping survived a reload")
  local f = io.open("/home/we/midimap.conf", "r"); local text = f and f:read("a") or ""; if f then f:close() end
  check(text:find("act.pin.num=44", 1, true) ~= nil, "the file has act.pin.num=44")
  check(text:find("act.keys", 1, true) == nil, "and no act.keys line")
  -- a file from before (the KEYS action was mapped, and did nothing): its lines are read as pin
  local g = io.open("/home/we/midimap.conf", "w")
  g:write("verdandi-midimap=1\nactions=1\nact.keys.type=note\nact.keys.num=77\nact.keys.dev=ANY\n"); g:close()
  setup2()
  eq(S.state.actions.pin.num, 77, "an old act.keys.num line is read as pin")
else
  check(has(S.ACTION_IDS, "keys") and not has(S.ACTION_IDS, "pin"), "Linux: the action is still keys, there is no pin")
  eq(S.ACTION_IDS[8], "keys", "keys is the 8th")
end
if fails == 0 then real_print("pin_action_test: ok") else real_print("pin_action_test: " .. fails .. " FAILED") os.exit(1) end
