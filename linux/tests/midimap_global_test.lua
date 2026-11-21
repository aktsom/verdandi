-- MIDI MAP, M32: the top DEVICE and CHANNEL rows ("all mappings", S.state.global): every kind of mapping (a control, an arc encoder, an action) follows them unless it has a device or channel of its own;
-- an old midimap.conf behaves as before; the setting is saved in midimap.conf, presets leave it alone and carry no device. docs/port/phase-m32.md. run from the repo root:
--   NORNS_PLATFORM=linux lua5.3 linux/tests/midimap_global_test.lua
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
local function setup(fn) S.load(); S.select_preset("NONE"); S.set_global("dev", "ANY"); S.set_global("ch", 0); S.clear_action("pin"); S.set_clash("params"); for _, a in ipairs(S.ARC_IDS) do S.clear(a) end; S.set_arc_keys(true); S.set_arc_keys_accel(false); mm.load(); reset_out(); T = T + 100; if fn then fn() end; mm.changed() end

_norns.window_action = function(id) out[#out + 1] = "action:" .. id end
local function fired() local r = {} for _, o in ipairs(out) do if o:match("^action:") then r[#r + 1] = o end end return table.concat(r, " ") end
local function arcs() local r = {} for _, o in ipairs(out) do if o:match("^arc:") then r[#r + 1] = o end end return table.concat(r, " ") end
local function tick() T = T + 1 end -- (the guard time of an action is 0.25 s)
local function note_press(dev, ch, n) tick(); note_on(dev, ch, n, 100); note_off(dev, ch, n) end
-- one of each kind: E2 (a relative CC, 71), A1 (an arc encoder, relative, CC 76), the PIN action as a note (36), the MAIDEN action as a CC button (40) and the MIX action as an encoder step (41)
local function map_all()
  S.set("e2", "num", 71); S.set("e2", "mode", "rel2c")
  S.set("a1", "type", "cc"); S.set("a1", "num", 76); S.set("a1", "mode", "rel2c")
  S.assign_action("pin", "note", 36)
  S.assign_action("maiden", "ccbutton", 40)
  S.assign_action("mix", "step", 41, {mode = "rel2c", dir = "up"})
  mm.changed()
end
-- what one message from one device on one channel does to each kind of mapping: "enc arc pin maiden mix" as a string of the ones that acted
local function who(dev, ch)
  local r = {}
  reset_out(); cc(dev, ch, 71, 1); if acts():find("enc:2:1", 1, true) then r[#r + 1] = "enc" end
  reset_out(); cc(dev, ch, 76, 1); if arcs() ~= "" then r[#r + 1] = "arc" end
  reset_out(); note_press(dev, ch, 36); if fired():find("action:pin", 1, true) then r[#r + 1] = "pin" end
  reset_out(); tick(); cc(dev, ch, 40, 127); cc(dev, ch, 40, 0); if fired():find("action:maiden", 1, true) then r[#r + 1] = "maiden" end
  reset_out(); T = T + 1; cc(dev, ch, 41, 1); T = T + 1; if fired():find("action:mix", 1, true) then r[#r + 1] = "mix" end
  return table.concat(r, " ")
end
local ALL = "enc arc pin maiden mix"

-- ---- the default (the top rows ANY and any channel): every device and every channel, as before
setup(map_all)
eq(S.state.global.dev, "ANY", "the top DEVICE row is ANY by default"); eq(S.state.global.ch, 0, "the top CHANNEL row is any by default")
eq(who(2, 1), ALL, "default: the mio on channel 1 acts on every kind of mapping")
eq(who(5, 7), ALL, "default: another device on channel 7 acts too")
eq(who(3, 1), "", "default: the iii grid is still no controller (as before)")

-- ---- the top DEVICE row names a device: every kind of mapping ignores the other devices
setup(map_all); S.set_global("dev", "mio")
eq(who(2, 1), ALL, "top DEVICE = mio: a message from the mio acts on a control, an arc encoder and every kind of action")
eq(who(5, 1), "", "top DEVICE = mio: a message from the Push 2 is ignored by all of them")
eq(who(1, 1), "", "top DEVICE = mio: and the virtual device")

-- ---- the top CHANNEL row names a channel
setup(map_all); S.set_global("ch", 3)
eq(who(2, 3), ALL, "top CHANNEL = 3: channel 3 acts on every kind of mapping")
eq(who(2, 1), "", "top CHANNEL = 3: channel 1 is ignored by every kind"); eq(who(5, 3), ALL, "top CHANNEL = 3: any device on channel 3")

-- ---- both
setup(map_all); S.set_global("dev", "Push 2"); S.set_global("ch", 2)
eq(who(5, 2), ALL, "device and channel: the right one acts"); eq(who(5, 3), "", "device and channel: the right device on the wrong channel is ignored"); eq(who(2, 2), "", "device and channel: the wrong device on the right channel is ignored")

-- ---- a mapping's own device or channel wins over the top rows, for that mapping only
setup(map_all); S.set_global("dev", "mio")
S.set("e2", "dev", "Push 2"); S.set_action("pin", "dev", "Push 2")
eq(who(5, 1), "enc pin", "own device: E2 and PIN listen to the Push 2 although the top row says mio (the others do not)")
eq(who(2, 1), "arc maiden mix", "own device: and they no longer listen to the mio; the mappings with no device of their own still do")
S.set("e2", "dev", "*"); S.set_action("pin", "dev", "*")
eq(who(5, 1), "enc pin", "ANY (*): E2 and PIN take any device even when the top row names the mio")
eq(who(2, 1), ALL, "ANY (*): including the mio")
setup(map_all); S.set_global("ch", 3)
S.set("e2", "ch", 5); S.set_action("maiden", "ch", S.CH_ANY)
eq(who(2, 5), "enc maiden", "own channel: E2 on 5 and MAIDEN on any channel; the rest wait for channel 3")
eq(who(2, 3), "arc pin maiden mix", "own channel: the top channel still serves the rest (E2 is on 5 now), MAIDEN (any channel) too")
eq(who(2, 9), "maiden", "own channel: MAIDEN with ANY (17) takes channel 9, nothing else does")

-- ---- an old midimap.conf: no global lines, with and without dev and ch lines; same as before
local function write_conf(text) local f = assert(io.open(S.PATH, "w")); f:write(text); f:close() end
write_conf("verdandi-midimap=1\nsens_scale=2\npreset=CUSTOM\non_clash=params\ne2.type=cc\ne2.num=71\ne2.mode=rel2c\ne2.sens=5\n")
S.load(); mm.load(); reset_out()
eq(S.state.global.dev .. "|" .. S.state.global.ch, "ANY|0", "an old file without global lines: ANY and any channel")
eq(S.state.ctl.e2.dev .. "|" .. S.state.ctl.e2.ch, "ANY|0", "an old control without dev and ch lines: ANY and 0, as before")
cc(5, 9, 71, 1); eq(acts(), "enc:2:1", "an old control with no dev and ch lines takes every device and channel")
write_conf("verdandi-midimap=1\nsens_scale=2\npreset=CUSTOM\non_clash=params\ne2.type=cc\ne2.num=71\ne2.dev=mio\ne2.ch=3\ne2.mode=rel2c\ne2.sens=5\n")
S.load(); mm.load(); reset_out()
cc(5, 3, 71, 1); cc(2, 1, 71, 1); eq(acts(), "", "an old control with dev=mio ch=3: the Push 2 and channel 1 are ignored")
cc(2, 3, 71, 1); eq(acts(), "enc:2:1", "and the mio on channel 3 acts")
-- an old file whose control says dev=ANY ch=0 explicitly follows the top row once one is set
write_conf("verdandi-midimap=1\nsens_scale=2\npreset=CUSTOM\non_clash=params\nglobal.dev=mio\nglobal.ch=4\ne2.type=cc\ne2.num=71\ne2.dev=ANY\ne2.ch=0\ne2.mode=rel2c\ne2.sens=5\n")
S.load(); mm.load(); reset_out()
cc(5, 4, 71, 1); eq(acts(), "", "dev=ANY ch=0 follows the top rows: the Push 2 is ignored"); cc(2, 5, 71, 1); eq(acts(), "", "and so is channel 5"); cc(2, 4, 71, 1); eq(acts(), "enc:2:1", "the mio on channel 4 acts")

-- ---- saving and loading the global setting
setup(); S.set_global("dev", "Ableton Push 2 2"); S.set_global("ch", 7)
local f = assert(io.open(S.PATH, "r")); local text = f:read("a"); f:close()
check(text:find("global.dev=Ableton Push 2 2\n", 1, true) and text:find("global.ch=7\n", 1, true), "midimap.conf has global.dev= and global.ch=")
S.set("e2", "dev", "*"); S.set("e2", "ch", S.CH_ANY); S.set("e2", "num", 71)
f = assert(io.open(S.PATH, "r")); text = f:read("a"); f:close()
check(text:find("e2.dev=*\n", 1, true) and text:find("e2.ch=*\n", 1, true), "a mapping with ANY (*) is written as * for the device and the channel")
S.load()
eq(S.state.global.dev .. "|" .. S.state.global.ch, "Ableton Push 2 2|7", "the global setting survives a restart"); eq(S.state.ctl.e2.dev .. "|" .. S.state.ctl.e2.ch, "*|" .. S.CH_ANY, "and so does a mapping's ANY")
write_conf("verdandi-midimap=1\nglobal.dev=\nglobal.ch=99\n"); S.load()
eq(S.state.global.dev .. "|" .. S.state.global.ch, "ANY|0", "a damaged global line falls back to ANY and any channel")
check(not S.set_global("ch", 17) and not S.set_global("dev", "*") and not S.set_global("ch", "x") and not S.set_global("nope", 1), "set_global refuses 17, * and the like")

-- ---- presets leave it alone and carry no device
setup(); S.set_global("dev", "mio"); S.set_global("ch", 4)
local function glob() return S.state.global.dev .. "|" .. S.state.global.ch end
S.select_preset("PUSH 2"); eq(glob(), "mio|4", "selecting the built-in PUSH 2 leaves the global setting alone")
S.select_preset("GENERIC REL 2S"); eq(glob(), "mio|4", "and GENERIC REL 2S"); S.select_preset("NONE"); eq(glob(), "mio|4", "and NONE")
S.set("e2", "type", "cc"); S.set("e2", "num", 71); S.set("e2", "dev", "Push 2"); S.set("e2", "ch", 2)
check(S.save_preset("Mine"), "a preset is saved"); eq(glob(), "mio|4", "saving a preset leaves it alone")
local pf = assert(io.open("/home/we/midimap-presets/mine.midimap", "r")); local ptext = pf:read("a"); pf:close()
check(not ptext:find("global", 1, true) and not ptext:find(".dev", 1, true) and not ptext:find(".ch", 1, true), "the preset file names no device, no channel and no global setting")
S.select_preset("Mine"); eq(glob(), "mio|4", "selecting the saved preset leaves it alone"); eq(S.state.ctl.e2.dev .. "|" .. S.state.ctl.e2.ch, "ANY|0", "and the preset's mapping follows the top rows (ANY, 0)")
check(S.delete_preset("Mine"), "a preset is deleted"); eq(glob(), "mio|4", "deleting a preset leaves it alone")
local g = assert(io.open("/home/we/midimap-presets/hand.midimap", "w")); g:write("verdandi-midimap-preset=1\nname=Hand\nglobal.dev=Evil\nglobal.ch=9\ne1.type=cc\ne1.num=70\ne1.dev=Evil\ne1.ch=9\n"); g:close()
S.select_preset("Hand"); eq(glob(), "mio|4", "a global line in a hand-written preset file is ignored"); eq(S.state.ctl.e1.dev .. "|" .. S.state.ctl.e1.ch, "ANY|0", "and so are its dev and ch lines")

-- ---- the effective values in the other places: overlap
setup(function() S.set("e1", "type", "cc"); S.set("e1", "num", 70); S.set("e1", "mode", "rel2c"); S.set("e2", "type", "cc"); S.set("e2", "num", 70); S.set("e2", "mode", "rel2c"); S.set("e1", "dev", "mio") end)
eq(mm.find_overlap("e2", "cc", 70, "ANY", 0), "e1", "overlap: with the top row at ANY a mapping with no device shares the CC with the one on the mio")
S.set_global("dev", "Push 2")
eq(mm.find_overlap("e2", "cc", 70, "ANY", 0), nil, "overlap: with the top DEVICE row on the Push 2 the two no longer share a message")
S.set_global("dev", "mio"); eq(mm.find_overlap("e2", "cc", 70, "ANY", 0), "e1", "overlap: and they do again on the mio")

-- ---- LEARN: the port the message came from stays the mapping's own device, the channel goes back to the default (follow the top row)
setup(); S.set_global("ch", 5)
S.assign("e2", "cc", 71, "Push 2"); eq(S.state.ctl.e2.dev .. "|" .. S.state.ctl.e2.ch, "Push 2|0", "assign (LEARN): the device it came from, the channel back to the default (0: the top row's)")
S.assign_action("pin", "note", 36, {dev = "Push 2"}); eq(S.state.actions.pin.dev .. "|" .. S.state.actions.pin.ch, "Push 2|0", "assign_action (LEARN): the same for an action")

if fails == 0 then real_print("midimap global: all passed") end
os.execute("rm -rf '" .. tmp .. "'")
os.exit(fails == 0 and 0 or 1)
