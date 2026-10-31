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
  midimap_show = function(s, n) out[#out + 1] = "ring:" .. s .. ":" .. n end,
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
local function setup(fn) S.load(); S.select_preset("NONE"); S.set_clash("params"); for _, a in ipairs(S.ARC_IDS) do S.clear(a) end; S.set_arc_keys(true); S.set_arc_keys_accel(false); mm.load(); reset_out(); T = T + 100; if fn then fn() end; mm.changed() end

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

-- ---------------------------------------------------------------- the arc encoders A1 to A4 (docs/port/arc-plan.md)
local function arcs() local r = {} for _, o in ipairs(out) do if o:match("^arc:") then r[#r + 1] = o end end return table.concat(r, " ") end
ARC_OPEN = true
setup(function() S.set("a1", "num", 76); S.set("a1", "mode", "relob"); S.set("a1", "dev", "mio") end)
cc(2, 1, 76, 65); cc(2, 1, 76, 63); cc(2, 1, 76, 66)
eq(arcs(), "arc:1:8 arc:1:-8 arc:1:16", "an offset-binary CC turns the arc: 8 ticks a unit")
reset_out(); cc(2, 1, 76, 64); eq(arcs(), "", "a relative value of 0 (64) gives no ticks")
reset_out(); cc(5, 1, 76, 65); eq(arcs(), "", "another device does not")
setup(function() S.set("a2", "num", 30); S.set("a2", "mode", "rel2c"); S.set("a2", "gain", 1) end)
cc(2, 1, 30, 1); cc(2, 1, 30, 127); cc(2, 1, 30, 0); cc(2, 1, 30, 64)
eq(arcs(), "arc:2:1 arc:2:-1", "gain 1: a nudge is one tick; 0 and 64 are nothing (a release never steps)")
setup(function() S.set("a3", "num", 31); S.set("a3", "mode", "abs"); S.set("a3", "gain", 8) end)
cc(2, 1, 31, 50); eq(arcs(), "", "an absolute arc encoder: the first message is a baseline")
cc(2, 1, 31, 53); cc(2, 1, 31, 53); cc(2, 1, 31, 52)
eq(arcs(), "arc:3:24 arc:3:-8", "absolute: +3 values = 24 ticks, the same value again nothing, -1 = -8")
reset_out(); cc(2, 1, 31, 120); eq(arcs(), "", "absolute: a jump of more than 40 is no turn")
reset_out(); cc(5, 1, 31, 10); cc(5, 1, 31, 12); eq(arcs(), "arc:3:16", "absolute: another source starts a baseline (+2 = 16)")
-- acceleration
setup(function() S.set("a4", "num", 32); S.set("a4", "mode", "rel2c"); S.set("a4", "gain", 8); S.set("a4", "accel", "high") end)
cc(2, 1, 32, 5); eq(arcs(), "arc:4:120", "accel high: five units at gain 8 = 120")
-- the window is closed: nothing happens and it is said once
setup(function() S.set("a1", "num", 40); S.set("a1", "mode", "rel2c") end)
ARC_OPEN = false
cc(2, 1, 40, 1); cc(2, 1, 40, 1); cc(2, 1, 40, 127)
local told = 0
for _, o in ipairs(out) do if o:match("^toast:.*ARC") then told = told + 1 end end
eq(told, 1, "the arc window is closed: one toast, however many messages")
ARC_OPEN = true; reset_out(); cc(2, 1, 40, 1); eq(arcs(), "arc:1:8", "the window opened: the next message turns it")
ARC_OPEN = false; reset_out(); cc(2, 1, 40, 1)
told = 0
for _, o in ipairs(out) do if o:match("^toast:.*ARC") then told = told + 1 end end
eq(told, 1, "closed again: said once more")
ARC_OPEN = true
local real_arc_turn = _norns.arc_turn
_norns.arc_turn = nil
reset_out(); cc(2, 1, 40, 1); eq(#out, 0, "a build without the arc call: nothing, no error")
_norns.arc_turn = real_arc_turn
-- the params MAP wins for an arc encoder too
setup(function() S.set("a1", "num", 76); S.set("a1", "mode", "relob"); S.set("a1", "dev", "mio") end)
pm("cutoff", port_of_mio, 1, 76); reset_out(); cc(2, 1, 76, 65); eq(arcs(), "", "a CC in the params MAP: the arc stands back")
local cl = mm.clashes(); eq(#cl, 1, "the clash check covers the arc encoders"); eq(cl[1].id, "a1", "A1")
S.set_clash("both"); reset_out(); cc(2, 1, 76, 65); eq(arcs(), "arc:1:8", "with both, the arc turns too"); S.set_clash("params"); pmap.clear()
-- the iii grid never turns an arc encoder with ANY
setup(function() S.set("a1", "num", 12); S.set("a1", "mode", "rel2c") end)
cc(3, 1, 12, 1); eq(arcs(), "", "ANY skips the iii grid for an arc encoder")
-- scripts still receive everything with the arc mapped
midi.devices[2].event = function(data) seen_dev[#seen_dev + 1] = table.concat(data, ",") end
seen_dev = {}; cc(2, 1, 12, 1); eq(#seen_dev, 1, "the script's handler still gets the message that turned the arc"); midi.devices[2].event = nil
-- two controls on one CC: the overlaps
setup(function() S.set("e2", "num", 71); S.set("a1", "num", 71) end)
local ov = mm.overlaps()
eq(ov.e2, "a1", "overlap: E2 and A1 share CC 71 (any device, any channel)"); eq(ov.a1, "e2", "overlap: and the other way")
setup(function() S.set("e2", "num", 71); S.set("e2", "dev", "mio"); S.set("a1", "num", 71); S.set("a1", "dev", "Push 2") end)
eq(next(mm.overlaps()), nil, "no overlap on different devices")
setup(function() S.set("e2", "num", 71); S.set("e2", "ch", 1); S.set("a1", "num", 71); S.set("a1", "ch", 2) end)
eq(next(mm.overlaps()), nil, "no overlap on different channels")
setup(function() S.set("e2", "num", 71); S.set("e2", "dev", "mio"); S.set("a1", "num", 71); S.set("a1", "dev", "mio 2") end)
check(mm.overlaps().e2 == "a1", "overlap: mio and its port mio 2")
setup(function() S.set("k1", "type", "note"); S.set("k1", "num", 71); S.set("a1", "num", 71) end)
eq(next(mm.overlaps()), nil, "a note and a CC with the same number are not the same message")
setup(function() S.set("e1", "num", 71); S.set("e1", "dev", "mio") end)
eq(mm.find_overlap("a1", "cc", 71, "ANY", 0), "e1", "find_overlap: a new CC that another control uses"); eq(mm.find_overlap("e1", "cc", 71, "ANY", 0), nil, "a control does not overlap itself")
eq(mm.find_overlap("a1", "cc", 72, "ANY", 0), nil, "another number is free"); eq(mm.find_overlap("a1", "note", 71, "ANY", 0), nil, "a note is another message")
-- the question at assignment (learn): yes moves the CC, no leaves everything
setup(function() S.set("e2", "num", 71); S.set("e2", "mode", "rel2c") end)
mm.start_listen("a1"); cc(2, 1, 71, 1)
eq(learning(), "ask", "learning a CC that E2 uses: the layer asks"); check(mm.ask_text():find("CC 71", 1, true) and mm.ask_text():find("E2", 1, true) and mm.ask_text():find("A1", 1, true), "the question names the CC and both controls: " .. tostring(mm.ask_text()))
eq(S.state.ctl.a1.type, "none", "nothing is assigned while asking"); eq(S.state.ctl.e2.num, 71, "and E2 keeps its CC")
reset_out(); cc(2, 1, 71, 1); eq(acts() .. arcs(), "", "nothing acts while the question is open")
mm.answer(true)
eq(S.state.ctl.e2.type, "none", "yes: E2 is cleared"); eq(S.state.ctl.a1.num, 71, "yes: A1 has the CC"); eq(learning(), "confirm", "yes: the learn goes on to the confirmation")
setup(function() S.set("e2", "num", 71) end)
mm.start_listen("a1"); cc(2, 1, 71, 1); mm.answer(false)
eq(learning(), "idle", "no: the learn is over"); eq(S.state.ctl.e2.num, 71, "no: E2 keeps the CC"); eq(S.state.ctl.a1.type, "none", "no: A1 has nothing"); check(mm.learn.msg ~= nil, "no: a message")
setup(function() S.set("e2", "num", 71) end)
mm.start_listen("a1"); cc(2, 1, 71, 1); T = T + 16; mm.tick(); eq(learning(), "idle", "the question times out like a learn"); eq(S.state.ctl.e2.num, 71, "and changes nothing")
setup(function() S.set("e2", "num", 71) end)
mm.start_listen("a1"); cc(2, 1, 71, 1); mm.cancel(); eq(learning(), "idle", "K2 / cancel answers no")
-- a key and an encoder learn the same way
setup(function() S.set("a2", "num", 85) end)
mm.start_listen("k1"); cc(2, 1, 85, 127); eq(learning(), "ask", "a key learning a CC an arc encoder uses asks too"); mm.answer(true); eq(S.state.ctl.a2.type, "none", "and moves it"); eq(S.state.ctl.k1.num, 85, "to the key")
-- a device by name: a different device does not overlap, so no question
setup(function() S.set("e2", "num", 71); S.set("e2", "dev", "Push 2") end)
mm.start_listen("a1"); cc(2, 1, 71, 1)
eq(learning(), "ask", "learn assigns ANY, which overlaps a named device: asks")
mm.cancel()
-- typed numbers use the same check from the page: find_overlap with the control's own device and channel
setup(function() S.set("e2", "num", 71); S.set("e2", "dev", "mio"); S.set("a1", "dev", "Push 2") end)
eq(mm.find_overlap("a1", "cc", 71, "Push 2", 0), nil, "a typed CC on another device does not overlap")
eq(mm.find_overlap("a1", "cc", 71, "mio", 0), "e2", "on the same device it does")
-- learning an arc encoder: pick, listen, a note refused, the suggestion
setup()
mm.start_pick(); mm.pick("a3"); eq(mm.learn.target, "a3", "pick a3"); check(table.concat(out, " "):find("ring:2:9", 1, true), "the window rings the control 9 (A3)")
note_on(2, 1, 40, 100); eq(learning(), "listen", "a note does not end the learn of an arc encoder"); check(mm.learn.msg:find("CC", 1, true), "it says to use a CC")
reset_out(); cc(2, 1, 77, 65); eq(arcs(), "", "the learning message turned nothing")
eq(S.state.ctl.a3.num, 77, "the CC is taken"); eq(learning(), "confirm", "and the suggestion is asked for")
cc(2, 1, 77, 63); cc(2, 1, 77, 65); cc(2, 1, 77, 63); cc(2, 1, 77, 65); cc(2, 1, 77, 65)
eq(learning(), "idle", "six messages end it"); eq(S.state.ctl.a3.mode, "relob", "offset binary is suggested"); check(mm.guess.a3, "marked as a guess")
-- WATCH: the layer records the CC messages while the view is open, and acts on nothing
setup(function() S.set("e2", "num", 71); S.set("e2", "mode", "rel2c"); S.set("a1", "num", 72) end)
mm.watch_start()
reset_out(); cc(2, 1, 71, 1); cc(2, 1, 72, 65); eq(acts() .. arcs(), "", "while WATCH is open nothing acts")
local wv = mm.watch_view(); eq(wv.cc, 72, "watch: the last CC"); eq(wv.dev, "mio", "watch: the device"); eq(wv.ch, 1, "watch: the channel"); eq(wv.values[1], 65, "watch: the value")
cc(2, 3, 72, 63); wv = mm.watch_view(); eq(wv.ch, 3, "watch: another channel is its own source")
note_on(2, 1, 60, 100); send(2, {0xF8}); wv = mm.watch_view(); eq(wv.cc, 72, "watch: notes and clock are not CCs")
cc(3, 1, 9, 5); wv = mm.watch_view(); eq(wv.dev, "iii grid", "watch: every device is shown, the iii grid too (it is a monitor)")
mm.watch_stop(); reset_out(); cc(2, 1, 71, 1); eq(acts(), "enc:2:1", "after WATCH everything acts again")
mm.watch_start(); eq(mm.watch_view().cc, nil, "watch: a new start is empty")
cc(2, 1, 5, 1); mm.watch_stop(); cc(2, 1, 6, 1); mm.watch_start(); eq(mm.watch_view().cc, nil, "watch: nothing is recorded while it is closed"); mm.watch_stop()
-- ONE TURN: the calibration
setup(function() S.set("a1", "num", 76); S.set("a1", "mode", "rel2c"); S.set("a1", "gain", 8) end)
mm.calib_start("a1")
reset_out(); for _ = 1, 16 do cc(2, 1, 76, 4) end
eq(arcs(), "", "while calibrating the arc does not turn"); eq(mm.calib_units(), 64, "the units are counted (16 x 4)")
for _ = 1, 16 do cc(2, 1, 76, 124) end
eq(mm.calib_units(), 0, "and go both ways")
for _ = 1, 32 do cc(2, 1, 76, 127 - 0) end
eq(mm.calib_units(), -32, "a turn the other way counts down")
mm.calib_cancel(); eq(S.state.ctl.a1.gain, 8, "cancel leaves the gain")
mm.calib_start("a1"); for _ = 1, 64 do cc(2, 1, 76, 2) end
local g = mm.calib_finish(); eq(g, 8, "128 units a turn: gain 8"); eq(S.state.ctl.a1.gain, 8, "stored")
mm.calib_start("a1"); for _ = 1, 100 do cc(2, 1, 76, 127) end
g = mm.calib_finish(); eq(g, 10, "100 units the other way: gain 10 (the size of the turn, not its direction)"); eq(S.state.ctl.a1.gain, 10, "stored")
mm.calib_start("a1"); g = mm.calib_finish(); eq(g, nil, "no units: no gain"); eq(S.state.ctl.a1.gain, 10, "unchanged")
mm.calib_start("a1"); mm.leave(); eq(mm.calib_units(), nil, "leaving the page ends the calibration")
setup(function() S.set("a1", "num", 76); S.set("a1", "mode", "abs") end)
mm.calib_start("a1"); for v = 10, 74, 1 do cc(2, 1, 76, v) end
g = mm.calib_finish(); eq(g, 16, "an absolute knob swept 64 values: gain 16")
-- a mapping change or a device removal while calibrating ends it
setup(function() S.set("a1", "num", 76); S.set("a1", "mode", "rel2c") end)
mm.calib_start("a1"); mm.device_removed(midi.devices[2]); eq(mm.calib_units(), nil, "a device that goes ends the calibration")
-- the arc encoders reset their states when the mapping changes (nothing held, but the carry)
setup(function() S.set("a1", "num", 76); S.set("a1", "mode", "rel2c"); S.set("a1", "accel", "high") end)
cc(2, 1, 76, 5); S.set("a1", "gain", 2); mm.changed(); reset_out(); cc(2, 1, 76, 2); eq(arcs(), "arc:1:6", "a changed mapping: 2 units at gain 2 with the high factor = 6")
ARC_OPEN = true
-- the layer is inert without the platform switch
check(mm.enabled == true, "enabled on the desktop build")

-- ================================================================ MIDI actions (docs/port/midi-actions-plan.md)
local menu_tick = nil
_norns.window_action = function(name) out[#out + 1] = "wa:" .. name end
_norns.midi_actions_menu = function(on) menu_tick = on; out[#out + 1] = "menu:" .. tostring(on) end
mm.install()
local function wa() local r = {} for _, o in ipairs(out) do if o:match("^wa:") then r[#r + 1] = o end end return table.concat(r, " ") end
local function asetup(fn) setup(function() S.clear_all_actions(); S.set_actions_on(true); if fn then fn() end end) end
local redraws = 0
mm.on_change = function() redraws = redraws + 1 end

-- note actions: a note on with velocity presses, nothing else does
asetup(function() S.assign_action("mix", "note", 36) end)
note_on(2, 1, 36, 100); eq(wa(), "wa:mix", "action note: a note on fires the action")
check(redraws > 0, "action fires end with a redraw of the page")
reset_out(); note_off(2, 1, 36); note_on(2, 1, 36, 0); eq(wa(), "", "action note: note off and velocity 0 never act")
reset_out(); T = T + 0.1; note_on(2, 1, 36, 100); eq(wa(), "", "action note: the guard blocks a second press 0.1 s later")
reset_out(); T = T + 0.2; note_on(2, 1, 36, 100); eq(wa(), "wa:mix", "action note: and lets one through after 0.25 s")
reset_out(); note_on(2, 1, 37, 100); eq(wa(), "", "action note: another note is nothing")
reset_out(); cc(2, 1, 36, 127); eq(wa(), "", "action note: a CC of the same number is not a note")
-- the keys window and the iii grid are not controllers
reset_out(); T = T + 1; note_on(4, 1, 36, 100); note_on(3, 1, 36, 100); eq(wa(), "", "action note: ANY ignores the keys window and the iii grid")
-- the action does not take the key's message away from a key, and a note action does not touch the screen
reset_out(); T = T + 1; note_on(2, 1, 36, 100); eq(acts(), "", "action note: no key or encoder moves")

-- CC button
asetup(function() S.assign_action("tape", "ccbutton", 20) end)
cc(2, 1, 20, 127); eq(wa(), "wa:tape", "cc button: a press fires")
reset_out(); T = T + 1; cc(2, 1, 20, 127); eq(wa(), "", "cc button: held high, no second press")
reset_out(); T = T + 1; cc(2, 1, 20, 0); eq(wa(), "", "cc button: the release never acts")
reset_out(); T = T + 1; cc(2, 1, 20, 100); eq(wa(), "wa:tape", "cc button: pressed again")

-- encoder step as a trigger
asetup(function() S.assign_action("home", "step", 30, {mode = "relob", dir = "up"}) end)
cc(2, 1, 30, 65); eq(wa(), "wa:home", "step: a click up fires")
reset_out(); T = T + 0.05; cc(2, 1, 30, 66); eq(wa(), "", "step: the rest of the burst does not fire again")
reset_out(); T = T + 1; cc(2, 1, 30, 63); cc(2, 1, 30, 64); eq(wa(), "", "step: down and delta 0 never fire")
reset_out(); T = T + 1; cc(2, 1, 30, 65); eq(wa(), "wa:home", "step: the next burst fires")
asetup(function() S.assign_action("params", "step", 31, {mode = "rel2c", dir = "down"}) end)
cc(2, 1, 31, 1); eq(wa(), "", "step down: a click up is nothing"); T = T + 1; cc(2, 1, 31, 127); eq(wa(), "wa:params", "step down: a click down fires")

-- master switch off: no action fires, the controls keep working
asetup(function() S.assign_action("mix", "note", 36); S.set("e1", "num", 10); S.set("e1", "mode", "rel2c"); S.set("k1", "type", "note"); S.set("k1", "num", 60) end)
mm.set_actions(false)
eq(S.state.actions_on, false, "master: set off"); eq(menu_tick, false, "master: the window menu is told")
reset_out(); T = T + 1; note_on(2, 1, 36, 100); cc(2, 1, 10, 1); note_on(2, 1, 60, 100)
eq(wa(), "", "master off: no action fires"); eq(acts(), "enc:1:1 key:1:1", "master off: E1 and K1 mappings keep working")
mm.set_actions(true); reset_out(); T = T + 1; note_on(2, 1, 36, 100); eq(wa(), "wa:mix", "master on: the action fires again")
-- the window menu and Ctrl+Shift+M reach it through one callback; the file keeps it; a restart shows the tick
_norns.midi_actions_changed(false)
eq(S.state.actions_on, false, "master: the menu / shortcut callback turns it off"); eq(menu_tick, false, "master: and the callback does not need a second tick push")
S.load(); eq(S.state.actions_on, false, "master: saved, loaded off")
menu_tick = nil; mm.load(); eq(menu_tick, false, "master: after a restart the menu is given the saved state")
_norns.midi_actions_changed(true); S.load(); eq(S.state.actions_on, true, "master: on again, saved"); mm.load(); eq(menu_tick, true, "master: the tick after a restart is on")
-- the window passes "1" and "0" (call_lua sends strings)
_norns.midi_actions_changed("0"); eq(S.state.actions_on, false, "master: the string 0 turns it off"); _norns.midi_actions_changed("1"); eq(S.state.actions_on, true, "master: the string 1 turns it on")
_norns.midi_actions_changed("x"); eq(S.state.actions_on, true, "master: another string changes nothing")
-- bad argument from C is ignored
_norns.midi_actions_changed(nil); eq(S.state.actions_on, true, "master: a nil callback changes nothing")

-- a text entry open: nothing fires
asetup(function() S.assign_action("mix", "note", 36) end)
package.loaded['textentry'] = {active = true}
note_on(2, 1, 36, 100); eq(wa(), "", "text entry open: no action fires")
package.loaded['textentry'] = nil

-- errors are visible
asetup(function() S.assign_action("mix", "note", 36) end)
_norns.window_action = function() error("boom") end
note_on(2, 1, 36, 100)
check(logged("boom"), "an error in the action call is logged")
check(table.concat(out, " "):find("toast:ACTION", 1, true) ~= nil, "and said on the screen")
_norns.window_action = nil
reset_out(); T = T + 1; note_on(2, 1, 36, 100)
check(table.concat(out, " "):find("toast:", 1, true) ~= nil, "a build without the call says so, no crash")
_norns.window_action = function(name) out[#out + 1] = "wa:" .. name end

-- the params MAP wins a CC both want
asetup(function() S.assign_action("tape", "ccbutton", 20) end)
pmap.rev = {} ; pmap.rev[midi.devices[2].port or 0] = pmap.rev[midi.devices[2].port or 0] or {}
pmap.rev[midi.devices[2].port or 0][1] = {[20] = "x"}
reset_out(); cc(2, 1, 20, 127); eq(wa(), "", "the params MAP wins a CC an action also wants")
pmap.rev = nil

-- the scripts still get every message (a tap)
asetup(function() S.assign_action("mix", "note", 36) end)
local got = 0
midi.devices[2].event = function() got = got + 1 end
note_on(2, 1, 36, 100); eq(got, 1, "the script receives the mapped note too")
midi.devices[2].event = nil

-- overlaps with controls and other actions
asetup(function() S.assign_action("mix", "note", 36); S.set("k1", "type", "note"); S.set("k1", "num", 36) end)
local ov = mm.overlaps(); eq(ov.mix, "k1", "overlap: an action and a key share a note"); eq(ov.k1, "mix", "overlap: both directions")
asetup(function() S.assign_action("mix", "note", 36); S.assign_action("tape", "note", 36) end)
ov = mm.overlaps(); eq(ov.mix, "tape", "overlap: two actions on one note")

-- learn: a note
asetup(); mm.start_listen("tape")
eq(mm.learn.state, "listen", "action learn: listening"); eq(mm.learn.target, "tape", "action learn: the target is the action")
note_on(2, 1, 40, 100)
eq(S.state.actions.tape.type, "note", "action learn: a note is taken"); eq(S.state.actions.tape.num, 40, "action learn: the note number"); eq(mm.learn.state, "idle", "action learn: done")
check(mm.learn.msg and mm.learn.msg:find("TAPE", 1, true), "action learn: says what was set")
-- learn: a note off and velocity 0 do nothing
asetup(); mm.start_listen("tape"); note_off(2, 1, 40); note_on(2, 1, 40, 0); eq(mm.learn.state, "listen", "action learn: a release is not a press")
-- learn: a CC makes a step in the last relative format
asetup(function() S.set("e1", "num", 5); S.set("e1", "mode", "rel2c") end); mm.load()
mm.start_listen("home"); cc(2, 1, 50, 1)
eq(S.state.actions.home.type, "step", "action learn: a CC makes an encoder step"); eq(S.state.actions.home.mode, "rel2c", "action learn: with the format of the last encoder mapping"); eq(S.state.actions.home.dir, "up", "action learn: direction of the first click")
mm.start_listen("home"); cc(2, 1, 51, 127); eq(S.state.actions.home.dir, "down", "action learn: a click down makes a down step")
asetup(); mm.load(); mm.start_listen("home"); cc(2, 1, 52, 65)
eq(S.state.actions.home.mode, "relob", "action learn: without any encoder mapping the format is REL OFS")
-- learn: ignores the keys window
asetup(); mm.start_listen("mix"); note_on(4, 1, 40, 100); eq(mm.learn.state, "listen", "action learn: the keys window is no controller")
-- learn: a clash with a key asks, yes moves it
asetup(function() S.set("k1", "type", "note"); S.set("k1", "num", 40) end)
mm.start_listen("mix"); note_on(2, 1, 40, 100); eq(mm.learn.state, "ask", "action learn: a note a key has asks first")
mm.answer(true); eq(S.state.ctl.k1.type, "none", "action learn: yes clears the key"); eq(S.state.actions.mix.num, 40, "action learn: and the action has it")
asetup(function() S.assign_action("mix", "note", 40) end)
mm.start_listen("k1"); note_on(2, 1, 40, 100); eq(mm.learn.state, "ask", "key learn: a note an action has asks first")
mm.answer(true); eq(S.state.actions.mix.type, "none", "key learn: yes clears the action"); eq(S.state.ctl.k1.num, 40, "key learn: and the key has it")
asetup(function() S.assign_action("mix", "note", 40) end)
mm.start_listen("k1"); note_on(2, 1, 40, 100); mm.answer(false); eq(S.state.actions.mix.num, 40, "key learn: no leaves the action")

-- the walk: ASSIGN ALL in list order, skipping keeps what is there
asetup(function() S.assign_action("home", "note", 99) end)
mm.walk_start()
eq(mm.learn.state, "listen", "walk: listening"); eq(mm.learn.target, "mix", "walk: the first action is MIX"); eq(mm.walk_index(), 1, "walk: index 1")
note_on(2, 1, 41, 100); eq(S.state.actions.mix.num, 41, "walk: assigned"); eq(mm.learn.target, "tape", "walk: on to TAPE"); eq(mm.walk_index(), 2, "walk: index 2")
mm.walk_skip(); eq(mm.learn.target, "home", "walk: skipped TAPE, on to HOME"); eq(S.state.actions.tape.type, "none", "walk: skipped one stays empty")
mm.walk_skip(); eq(S.state.actions.home.num, 99, "walk: skipping keeps an existing assignment")
eq(mm.learn.target, "params", "walk: PARAMS next")
for i = 1, 10 do mm.walk_skip() end
eq(mm.learn.state, "listen", "walk: still listening at the last"); eq(mm.learn.target, "screenshot", "walk: the last is SCREENSHOT"); eq(mm.walk_index(), 14, "walk: 14 of 14")
mm.walk_skip(); eq(mm.learn.state, "idle", "walk: ends after the last"); eq(mm.walk_index(), nil, "walk: no index after the end")
eq(mm.learn.msg, "DONE: 1 ASSIGNED, 13 SKIPPED", "walk: the end says how many were assigned and skipped")
-- the walk ends like a learn: cancel, time-out, leaving, a device that goes
asetup(); mm.walk_start(); mm.walk_skip(); mm.walk_skip(); mm.cancel(); eq(mm.learn.state, "idle", "walk: cancel ends it"); eq(mm.walk_index(), nil, "walk: and the index is gone"); eq(mm.learn.msg, "STOPPED AT 3 OF 14", "walk: cancel says where it stopped")
asetup(); mm.walk_start(); T = T + 16; mm.tick(); eq(mm.learn.state, "idle", "walk: the time-out ends it")
asetup(); mm.walk_start(); note_on(2, 1, 42, 100); T = T + 10; mm.tick(); note_on(2, 1, 43, 100); T = T + 10; mm.tick()
eq(mm.learn.state, "listen", "walk: every assignment restarts the time-out")
mm.leave(); eq(mm.walk_index(), nil, "walk: leaving the page ends it")
-- a walk onto an assigned note asks
asetup(function() S.assign_action("keys", "note", 50) end)
mm.walk_start(); note_on(2, 1, 50, 100); eq(mm.learn.state, "ask", "walk: a note that another action has asks"); mm.answer(true)
eq(S.state.actions.mix.num, 50, "walk: yes assigns it"); eq(S.state.actions.keys.type, "none", "walk: and clears the other"); eq(mm.learn.state, "listen", "walk: and goes on"); eq(mm.learn.target, "tape", "walk: with the next action")
-- no to the question skips that action and goes on (it does not stop the walk)
asetup(function() S.assign_action("keys", "note", 50) end)
mm.walk_start(); note_on(2, 1, 50, 100); eq(mm.learn.state, "ask", "walk: asks again"); mm.answer(false)
eq(mm.learn.state, "listen", "walk: no skips this action and goes on"); eq(mm.learn.target, "tape", "walk: with the next one"); eq(S.state.actions.keys.num, 50, "walk: and the other action keeps its note"); eq(S.state.actions.mix.type, "none", "walk: the skipped one stays empty")
mm.cancel_quiet()

-- clear
asetup(function() S.assign_action("mix", "note", 36) end)
mm.clear("mix"); eq(S.state.actions.mix.type, "none", "clear works for an action id")

-- leaving the page loses nothing on the actions; release_all never touches them
asetup(function() S.assign_action("mix", "note", 36) end); mm.leave(); eq(S.state.actions.mix.num, 36, "leave keeps the action")
-- the layer still fires while the page is not open (actions are global)
reset_out(); T = T + 1; note_on(2, 1, 36, 100); eq(wa(), "wa:mix", "actions work without the MIDI MAP page open")
mm.on_change = nil

if fails == 0 then real_print("midimap layer: all passed") end
os.execute("rm -rf '" .. tmp .. "'")
os.exit(fails == 0 and 0 or 1)
