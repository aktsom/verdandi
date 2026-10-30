-- MIDI MAP, the layer and the learn flow (lua/core/midimap.lua), through the real lua/core/midi.lua event function and the real lua/core/pmap.lua. docs/port/midi-map-plan.md 2.2, 2.5, 3.2, 3.3. run from the repo root:
--   NORNS_PLATFORM=linux lua5.3 linux/tests/midimap_layer_test.lua
-- mapped messages reach the right key and encoder, device and channel filters (the mio, the iii grid, the keys window, ANY), the params MAP wins a clash, scripts still receive every message, a held
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
  midimap_show = function(s, n) out[#out + 1] = "ring:" .. s .. ":" .. n end}
local function acts() local r = {} for _, o in ipairs(out) do if o:match("^key:") or o:match("^enc:") then r[#r + 1] = o end end return table.concat(r, " ") end
params = {lookup = {}, lookup_param = function(self, id) return {name = "Param " .. tostring(id)} end}
_menu = {rebuild_params = function() end, page = "MIDIMAP", mode = true, redraw = function() end}
pmap = require 'core/pmap'
local pmap_calls = {}
norns = {pmap = pmap, state = {shortname = "testscript"}, none = function() end,
  menu_midi_event = function(data, dev) pmap_calls[#pmap_calls + 1] = {data[1], data[2], data[3], dev} end}
midi = require 'core/midi'
local V = require 'core/midimap_value'
local S = require 'core/midimap_settings'
S.log = function() end
local mm = require 'core/midimap'
norns.midimap = mm
mm.clock = function() return T end
mm.load()

local function add(id, name) _norns.midi.add(id, name, "ptr" .. id) end
add(1, "Verdandi JACK in"); add(2, "mio"); add(3, "iii grid"); add(4, "Verdandi keys"); add(5, "Push 2")
local function send(id, bytes) _norns.midi.event(id, bytes) end
local function cc(id, ch, num, val) send(id, {0xB0 + ch - 1, num, val}) end
local function note_on(id, ch, n, vel) send(id, {0x90 + ch - 1, n, vel}) end
local function note_off(id, ch, n) send(id, {0x80 + ch - 1, n, 0}) end
local function setup(fn) S.load(); S.select_preset("NONE"); S.set_clash("params"); mm.load(); reset_out(); T = T + 100; if fn then fn() end; mm.changed() end

-- ---- nothing mapped: nothing happens
setup()
cc(2, 1, 71, 5); note_on(2, 1, 36, 100); send(2, {0xF8})
eq(acts(), "", "nothing is mapped: no key, no encoder")

-- ---- an encoder, relative, from the mio
setup(function() S.set("e2", "num", 71); S.set("e2", "mode", "rel2c"); S.set("e2", "dev", "mio") end)
cc(2, 1, 71, 1); cc(2, 1, 71, 127); cc(2, 1, 71, 3)
eq(acts(), "enc:2:1 enc:2:-1 enc:2:3", "a relative CC turns E2 (from the mio)")
check(out[1] == "show:2:2:1" and out[2] == "enc:2:1", "the window is shown the turn before the encoder event")
reset_out(); cc(5, 1, 71, 1); eq(acts(), "", "another device is not the mio")
reset_out(); cc(2, 1, 72, 1); eq(acts(), "", "another CC number is not mapped")
reset_out(); cc(2, 1, 71, 0); eq(acts(), "", "relative value 0 is nothing")
-- the whole interface: mio and its ports
reset_out(); add(6, "mio 2"); cc(6, 1, 71, 1); eq(acts(), "enc:2:1", "`mio` also matches the port `mio 2`")
_norns.midi.remove(6)

-- ---- channels
setup(function() S.set("e1", "num", 20); S.set("e1", "mode", "rel2c"); S.set("e1", "ch", 3) end)
cc(2, 3, 20, 1); cc(2, 4, 20, 1); cc(1, 3, 20, 1)
eq(acts(), "enc:1:1 enc:1:1", "channel 3 only (from any device)")
setup(function() S.set("e1", "num", 20); S.set("e1", "mode", "rel2c") end)
cc(2, 1, 20, 1); cc(2, 16, 20, 1)
eq(acts(), "enc:1:1 enc:1:1", "any channel")

-- ---- ANY does not take the iii grid, the keys window; a name does
setup(function() S.set("k1", "type", "note"); S.set("k1", "num", 60) end)
note_on(3, 1, 60, 100); note_on(4, 1, 60, 100)
eq(acts(), "", "ANY ignores the iii grid and the keys window")
note_on(2, 1, 60, 100); note_off(2, 1, 60)
eq(acts(), "key:1:1 key:1:0", "ANY takes the mio")
setup(function() S.set("k1", "type", "note"); S.set("k1", "num", 60); S.set("k1", "dev", "iii grid") end)
note_on(3, 1, 60, 100); note_off(3, 1, 60)
eq(acts(), "key:1:1 key:1:0", "the iii grid by name is allowed")
reset_out(); note_on(2, 1, 60, 100)
eq(acts(), "", "and then the mio is not")

-- ---- different controls from different devices
setup(function()
  S.set("e1", "num", 10); S.set("e1", "mode", "rel2c"); S.set("e1", "dev", "mio")
  S.set("e2", "num", 10); S.set("e2", "mode", "rel2c"); S.set("e2", "dev", "Push 2")
  S.set("e3", "num", 10); S.set("e3", "mode", "rel2c"); S.set("e3", "dev", "Verdandi JACK in")
end)
cc(2, 1, 10, 1); cc(5, 1, 10, 1); cc(1, 1, 10, 1)
eq(acts(), "enc:1:1 enc:2:1 enc:3:1", "the same CC from three devices turns three different encoders")
-- a mapping survives a replug with a new id and vport
_norns.midi.remove(2); reset_out(); add(9, "mio"); cc(9, 1, 10, 1)
eq(acts(), "enc:1:1", "the mio re-added with a new id still matches")
_norns.midi.remove(9); add(2, "mio")
-- a device added after the mapping existed; a name that is absent
setup(function() S.set("e1", "num", 11); S.set("e1", "mode", "rel2c"); S.set("e1", "dev", "Not Here") end)
cc(2, 1, 11, 1); eq(acts(), "", "a mapping to an absent device does not fire")
add(7, "Not Here"); cc(7, 1, 11, 1); eq(acts(), "enc:1:1", "it works the moment the device is there")
_norns.midi.remove(7)

-- ---- absolute encoders: baseline, jump, pause, per source
setup(function() S.set("e3", "num", 30); S.set("e3", "mode", "abs"); S.set("e3", "sens", 5) end)
cc(2, 1, 30, 50); eq(acts(), "", "absolute: the first message is a baseline")
cc(2, 1, 30, 54); eq(acts(), "enc:3:2", "absolute: +4 values = 2 steps")
reset_out(); cc(2, 1, 30, 100); eq(acts(), "", "absolute: a jump of 46 is no turn")
reset_out(); T = T + 2; cc(2, 1, 30, 110); eq(acts(), "", "absolute: the first message after a pause is a baseline")
reset_out(); cc(2, 1, 30, 106); eq(acts(), "enc:3:-2", "absolute: and then it counts again")
reset_out(); cc(5, 1, 30, 20); cc(5, 1, 30, 24); eq(acts(), "enc:3:2", "absolute: a message from another device starts a new baseline (24 - 20)")
reset_out(); cc(2, 1, 30, 106); eq(acts(), "", "absolute: and coming back to the first device starts one again")

-- ---- keys from CCs and notes, threshold
setup(function() S.set("k2", "type", "cc"); S.set("k2", "num", 85); S.set("k2", "threshold", 63) end)
cc(2, 1, 85, 127); cc(2, 1, 85, 40); cc(2, 1, 85, 0)
eq(acts(), "key:2:1 key:2:0", "a CC key: 127 presses, 0 releases")
reset_out(); cc(2, 1, 85, 30); cc(2, 1, 85, 0); eq(acts(), "", "a CC key: 30 is below the threshold")
check(out[1] == nil, "and nothing at all is shown")
reset_out(); cc(2, 1, 85, 127)
eq(out[1], "show:1:2:1", "a key press is shown in the window")
setup(function() S.set("k3", "type", "note"); S.set("k3", "num", 36); S.set("k3", "ch", 2) end)
note_on(2, 1, 36, 100); note_on(2, 2, 37, 100); note_on(2, 2, 36, 100); note_on(2, 2, 36, 0)
eq(acts(), "key:3:1 key:3:0", "a note key: the right note and channel; velocity 0 releases")
-- a key mapped to a CC does not answer to a note of the same number and the reverse
setup(function() S.set("k1", "type", "cc"); S.set("k1", "num", 50) end)
note_on(2, 1, 50, 100); eq(acts(), "", "a CC key ignores a note with the same number")
setup(function() S.set("k1", "type", "note"); S.set("k1", "num", 50) end)
cc(2, 1, 50, 127); eq(acts(), "", "a note key ignores a CC with the same number")

-- ---- K1 is a key like the others
setup(function() S.set("k1", "type", "cc"); S.set("k1", "num", 22) end)
cc(2, 1, 22, 127); cc(2, 1, 22, 0)
eq(acts(), "key:1:1 key:1:0", "K1 can be mapped (a short press opens or closes the menu)")

-- ---- held keys are released
setup(function() S.set("k2", "type", "cc"); S.set("k2", "num", 85) end)
cc(2, 1, 85, 127); reset_out()
_norns.midi.remove(2)
eq(acts(), "key:2:0", "a held key is released when its device is removed")
add(2, "mio")
cc(2, 1, 85, 127); reset_out(); S.set("k2", "num", 86); mm.changed()
eq(acts(), "key:2:0", "a held key is released when the mapping changes")
cc(2, 1, 86, 127); reset_out(); S.clear("k2"); mm.changed()
eq(acts(), "key:2:0", "a held key is released when it is cleared")
reset_out(); cc(2, 1, 86, 0); eq(acts(), "", "after that nothing more arrives from the old mapping")
setup(function() S.set("k2", "type", "cc"); S.set("k2", "num", 85) end)
cc(2, 1, 85, 127); reset_out(); mm.release_all()
eq(acts(), "key:2:0", "release_all releases")
reset_out(); mm.release_all(); eq(acts(), "", "and only what is held")

-- ---- scripts still receive everything, in order, unchanged
local seen_dev, seen_port, seen_all = {}, {}, {}
midi.devices[2].event = function(data) seen_dev[#seen_dev + 1] = table.concat(data, ",") end
midi.vports[midi.devices[2].port].event = function(data) seen_port[#seen_port + 1] = table.concat(data, ",") end
local function run_stream()
  seen_dev, seen_port, pmap_calls = {}, {}, {}
  cc(2, 1, 71, 1); cc(2, 1, 99, 5); note_on(2, 1, 36, 90); note_off(2, 1, 36); send(2, {0xE0, 1, 2}); send(2, {0xF8}); cc(2, 1, 85, 127); cc(2, 1, 85, 0)
  return table.concat(seen_dev, "|"), table.concat(seen_port, "|"), #pmap_calls
end
setup()
local base_dev, base_port, base_pmap = run_stream()
for _, clash in ipairs({"params", "both"}) do
  setup(function()
    S.set("e2", "num", 71); S.set("e2", "mode", "rel2c"); S.set("k2", "type", "cc"); S.set("k2", "num", 85); S.set("k3", "type", "note"); S.set("k3", "num", 36); S.set_clash(clash)
  end)
  local d, p, n = run_stream()
  eq(d, base_dev, "the script's device handler gets the same bytes with the layer on (" .. clash .. ")")
  eq(p, base_port, "the vport handler too (" .. clash .. ")")
  eq(n, base_pmap, "and the params MAP handler is called the same (" .. clash .. ")")
  check(acts() ~= "", "and the layer did act (" .. clash .. ")")
end
midi.devices[2].event = nil
midi.vports[midi.devices[2].port].event = nil

-- ---- the params MAP wins
local function pm(id, dev, ch, ccn) pmap.clear(); pmap.new(id); pmap.assign(id, dev, ch, ccn) end
setup(function() S.set("e2", "num", 71); S.set("e2", "mode", "rel2c"); S.set("e2", "dev", "mio") end)
local port_of_mio = midi.devices[2].port
pm("cutoff", port_of_mio, 1, 71)
cc(2, 1, 71, 1); eq(acts(), "", "a CC in the params MAP of the script: the layer stands back (params wins)")
reset_out(); cc(2, 2, 71, 1); eq(acts(), "enc:2:1", "another channel is not in the params MAP")
pm("cutoff", port_of_mio + 5, 1, 71); reset_out(); cc(2, 1, 71, 1); eq(acts(), "enc:2:1", "another vport is not a clash")
pm("cutoff", port_of_mio, 1, 71); S.set_clash("both"); reset_out(); cc(2, 1, 71, 1)
eq(acts(), "enc:2:1", "with 'both' the layer acts too")
S.set_clash("params"); pmap.clear(); reset_out(); cc(2, 1, 71, 1); eq(acts(), "enc:2:1", "no params entry: no clash")
-- an entry added later wins from then on
pm("cutoff", port_of_mio, 1, 71); reset_out(); cc(2, 1, 71, 1); eq(acts(), "", "an entry added later takes the CC")
-- any device / any channel against a specific entry
setup(function() S.set("e1", "num", 20); S.set("e1", "mode", "rel2c") end)
pm("res", port_of_mio, 4, 20); cc(2, 4, 20, 1); eq(acts(), "", "ANY and any channel: the entry's own device and channel are the params MAP's")
reset_out(); cc(2, 5, 20, 1); eq(acts(), "enc:1:1", "any channel: the other channels are free")
-- the check at assignment and at load
pm("res", port_of_mio, 4, 20)
local list = mm.clashes()
eq(#list, 1, "the check finds one clash"); eq(list[1].id, "e1", "it is E1"); eq(list[1].param, "res", "with the param")
check(mm.clash_text(list[1]):find("CC 20", 1, true) and mm.clash_text(list[1]):find("PARAMS MAP", 1, true), "the text says what and which")
pmap.clear(); eq(#mm.clashes(), 0, "no clash without entries")
pm("res", port_of_mio, 4, 21); eq(#mm.clashes(), 0, "another CC: no clash")
S.set_clash("both"); pm("res", port_of_mio, 4, 20); eq(#mm.clashes(), 0, "with 'both' there is no clash to warn about")
S.set_clash("params")
-- the load check (script_post_init): one log line per clash and one toast
reset_out(); printed = {}
mm.after_script_load()
check(logged("E1") and logged("res"), "the load check logs the clash"); local toasts = 0
for _, o in ipairs(out) do if o:match("^toast:") then toasts = toasts + 1 end end
eq(toasts, 1, "and shows one toast")
reset_out(); pmap.clear(); mm.after_script_load(); eq(#out, 0, "no clash: no toast")
-- the params page in learn: the next CC is the params MAP's
setup(function() S.set("e2", "num", 71); S.set("e2", "mode", "rel2c") end)
norns.pmap.learning = function() return true end
cc(2, 1, 71, 1); eq(acts(), "", "the params page is learning: the layer stands down")
norns.pmap.learning = nil
cc(2, 1, 71, 1); eq(acts(), "enc:2:1", "and acts again after it")

-- ---- realtime and system messages are never looked at (and cost no memory)
setup(function() S.set("e1", "num", 10) end)
local before = collectgarbage("count")
for i = 1, 20000 do mm.event(midi.devices[2], {0xF8}) end
collectgarbage()
local after = collectgarbage("count")
check(after - before < 50, "20000 clock messages do not grow memory (" .. math.floor(after - before) .. " KB)")
eq(acts(), "", "and do nothing")
mm.event(midi.devices[2], {0xF0, 1, 2, 0xF7}); mm.event(midi.devices[2], {}); mm.event(midi.devices[2], {0xB0}); mm.event(nil, {0xB0, 1, 1})
check(true, "a sysex, an empty message, a short one and no device do not raise")

-- ---- an error inside never reaches the script or the params MAP
setup(function() S.set("e1", "num", 10); S.set("e1", "mode", "rel2c") end)
local real_enc = _norns.enc
_norns.enc = function() error("boom") end
printed = {}; pmap_calls = {}
local ok = pcall(send, 2, {0xB0, 10, 1})
check(ok, "an error in the layer does not stop the event function")
eq(#pmap_calls, 1, "the params MAP was still called"); check(logged("midimap"), "and the error is logged")
_norns.enc = real_enc

-- ---------------------------------------------------------------- learn
local function learning() return mm.learn.state end
setup()
eq(learning(), "idle", "learn: idle at first")
mm.start_pick()
eq(learning(), "pick", "learn: PICK after start"); check(table.concat(out, " "):find("arm:1", 1, true), "learn: the window is armed")
check(table.concat(out, " "):find("toast:", 1, true), "learn: a toast says what to do")
-- while a learn is open nothing else acts
S.set("e1", "num", 10); S.set("e1", "mode", "rel2c"); reset_out(); cc(2, 1, 10, 1)
eq(acts(), "", "learn: a mapped CC does not act while learning (and is not learned in PICK)")
mm.pick("e2"); eq(learning(), "listen", "learn: the click picks, LISTEN"); eq(mm.learn.target, "e2", "learn: the target")
check(table.concat(out, " "):find("ring:2:5", 1, true), "learn: the window rings the control")
cc(2, 1, 71, 1)
eq(S.state.ctl.e2.num, 71, "learn: the CC is taken"); eq(S.state.ctl.e2.type, "cc", "learn: type cc"); eq(S.state.ctl.e2.dev, "ANY", "learn: the device stays ANY"); eq(S.state.ctl.e2.ch, 0, "learn: any channel")
eq(learning(), "confirm", "learn: an encoder asks for a few more messages")
check(table.concat(out, " "):find("arm:0", 1, true), "learn: the window is no longer armed after the CC")
cc(2, 1, 71, 127); cc(2, 1, 71, 2); cc(2, 1, 71, 126); cc(2, 1, 71, 1); cc(2, 1, 71, 127)
eq(learning(), "idle", "learn: six messages end it"); eq(S.state.ctl.e2.mode, "rel2c", "learn: the suggestion is set"); check(mm.guess.e2, "learn: marked as a guess")
eq(S.load().ctl.e2.num, 71, "learn: written to the file")
setup(function() S.set("e1", "num", 5) end)
eq(acts(), "", "learn: the learning messages themselves moved nothing")
-- the file was written once at the end, not for every message
-- a key by CC and by note
setup(); mm.start_listen("k2"); eq(learning(), "listen", "learn: start_listen goes straight to LISTEN")
cc(2, 1, 90, 0); eq(learning(), "listen", "learn key: a CC with value 0 is not a press")
note_off(2, 1, 40); eq(learning(), "listen", "learn key: a note off is not a press")
note_on(2, 1, 40, 100); eq(learning(), "idle", "learn key: a note on is taken"); eq(S.state.ctl.k2.type, "note", "learn key: note"); eq(S.state.ctl.k2.num, 40, "learn key: its number")
mm.start_listen("k3"); cc(2, 1, 91, 127); eq(S.state.ctl.k3.type, "cc", "learn key: a CC"); eq(S.state.ctl.k3.num, 91, "learn key: its number")
-- the window's calls: a click on a control picks, a click elsewhere ends a pick but not a listen
mm.install()
setup(); mm.start_pick(); _norns.midimap_pick("k", "2"); eq(mm.learn.target, "k2", "window click on K2 picks k2")
_norns.midimap_pick("x", "0"); eq(learning(), "listen", "a click elsewhere does not end a listen")
mm.cancel(); mm.start_pick(); _norns.midimap_pick("x", "0"); eq(learning(), "idle", "a click elsewhere ends a pick")
mm.start_pick(); _norns.midimap_pick("e", "3"); eq(mm.learn.target, "e3", "window click on E3 picks e3"); mm.cancel()
-- a note is refused for an encoder, listening goes on
setup(); mm.start_listen("e1"); note_on(2, 1, 40, 100)
eq(learning(), "listen", "learn encoder: a note does not end it"); check(mm.learn.msg and mm.learn.msg:find("CC", 1, true), "learn encoder: it says a CC is needed"); eq(S.state.ctl.e1.type, "none", "learn encoder: nothing assigned")
-- realtime, sysex, the iii grid and the keys window are ignored
send(2, {0xF8}); send(3, {0xB0, 5, 100}); send(4, {0xB0, 6, 100}); eq(learning(), "listen", "learn: clock, the iii grid and the keys window are ignored")
cc(2, 1, 5, 64); eq(learning(), "confirm", "learn: the first real CC is taken (from the mio)")
mm.cancel(); eq(learning(), "idle", "learn: cancel")
-- the first message wins; the click on another control re-picks
setup(); mm.start_pick(); mm.pick("e1"); mm.pick("k3"); eq(mm.learn.target, "k3", "learn: another click changes the target")
cc(2, 1, 33, 127); eq(S.state.ctl.k3.num, 33, "learn: assigned to the last target"); eq(S.state.ctl.e1.type, "none", "learn: and not to the first")
-- every way out
local function out_of(how, fn)
  setup(); mm.start_pick(); if how ~= "pick-timeout" then mm.pick("e3") end; reset_out(); fn()
  eq(learning(), "idle", "learn: " .. how .. " leaves learning"); check(table.concat(out, " "):find("arm:0", 1, true), "learn: " .. how .. " disarms the window")
  check(table.concat(out, " "):find("ring:0", 1, true), "learn: " .. how .. " clears the ring")
  eq(S.state.ctl.e3.type, "none", "learn: " .. how .. " changes nothing"); eq(S.load().ctl.e3.type, "none", "learn: " .. how .. " writes nothing")
end
out_of("cancel", function() mm.cancel() end)
out_of("time-out", function() T = T + 16; mm.tick() end)
out_of("pick-timeout", function() T = T + 16; mm.tick() end)
out_of("leaving the page", function() mm.leave() end)
out_of("a device change", function() mm.device_removed(midi.devices[2]) end)
setup(); mm.start_pick(); T = T + 14; mm.tick(); eq(learning(), "pick", "learn: 14 s is not yet the time-out")
-- the time-out message
setup(); mm.start_listen("e1"); T = T + 16; mm.tick(); check(mm.learn.msg == "LEARN STOPPED", "learn: the time-out says LEARN STOPPED")
-- the confirm ends by itself after 3 s of silence
setup(); mm.start_listen("e1"); cc(2, 1, 71, 1); cc(2, 1, 71, 127); T = T + 4; mm.tick()
eq(learning(), "idle", "learn: the confirmation ends after 3 s of silence"); eq(S.state.ctl.e1.num, 71, "learn: the CC stays")
-- a key press during the confirmation ends it too
setup(); mm.start_listen("e1"); cc(2, 1, 71, 1); mm.finish_confirm(); eq(learning(), "idle", "learn: finish_confirm ends it")
-- a clash found at assignment
setup(); pm("res", midi.devices[2].port, 1, 71); mm.start_listen("e2"); cc(2, 1, 71, 1)
check(mm.learn.warn and mm.learn.warn:find("PARAMS MAP", 1, true), "learn: a clash is announced at assignment"); eq(S.state.ctl.e2.num, 71, "learn: and the assignment is kept")
pmap.clear()
-- clearing
setup(function() S.set("e2", "num", 71) end); mm.clear("e2"); eq(S.state.ctl.e2.type, "none", "clear through the layer")
-- the layer is inert without the platform switch
check(mm.enabled == true, "enabled on the desktop build")

if fails == 0 then real_print("midimap layer: all passed") end
os.execute("rm -rf '" .. tmp .. "'")
os.exit(fails == 0 and 0 or 1)
