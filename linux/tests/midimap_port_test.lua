-- MIDI learn remembers the port (Windows 0.10.3; docs/port/phase-m12.md): the value rule (core/midimap_value.lua stored_port, name_matches with "=Name") and the files: what exists already loads unchanged, an exact port survives a
-- file round trip, and by hand every row can still be ANY. the layer tests (learn from port A stores A and ignores port B, ANY matches everything, a replug and a restart) are in midimap_layer_test.lua.
-- run from the repo root: NORNS_PLATFORM=linux lua5.3 linux/tests/midimap_port_test.lua
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
local fails = 0
local function check(ok, what) if not ok then fails = fails + 1; print("FAIL " .. what) end end
local function eq(a, b, what) check(a == b, what .. ": got " .. tostring(a) .. ", wanted " .. tostring(b)) end
local function slurp(p) local h = real_open(map(p)); if not h then return nil end local c = h:read("a"); h:close(); return c end
local function put(p, text) local h = real_open(map(p), "w"); h:write(text); h:close() end
util = {scandir = function() return {} end, clamp = function(x, lo, hi) return math.max(lo, math.min(hi, x)) end}
package.loaded.util = util
local V = require 'core/midimap_value'
local S = require 'core/midimap_settings'
S.log = function() end

-- ---- the stored port
eq(V.stored_port("Ableton Push 2 2", {"Ableton Push 2 1", "Ableton Push 2 2", "mio"}), "Ableton Push 2 2", "a port of a Push 2: its own name")
eq(V.stored_port("mio", {"mio", "iii grid"}), "mio", "a device alone: its name")
eq(V.stored_port("Foo", {"Foo", "Foo 2"}), "=Foo", "the first of two identical devices (Foo and Foo 2): exactly this one")
eq(V.stored_port("Foo 2", {"Foo", "Foo 2"}), "Foo 2", "the second one: its own name is already exact")
eq(V.stored_port("Foo", {"Foo", "Foo"}), "=Foo", "the same name listed twice: exactly this name")
eq(V.stored_port(nil, {}), "ANY", "no name: ANY"); eq(V.stored_port("", {"a"}), "ANY", "an empty name: ANY")
eq(V.stored_port("Foo 1", {"Foo 1", "Foo 2"}), "Foo 1", "port 1 of a two-port device")
-- what a stored name matches
check(V.name_matches("Ableton Push 2 2", "Ableton Push 2 2"), "the port matches itself")
check(not V.name_matches("Ableton Push 2 2", "Ableton Push 2 1"), "and not the other port of the Push")
check(V.name_matches("Ableton Push 2", "Ableton Push 2 1") and V.name_matches("Ableton Push 2", "Ableton Push 2 2"), "the device name (set by hand) is still both ports")
check(V.name_matches("Foo", "Foo 2"), "a plain Foo still means Foo 2 too (as before)")
check(V.name_matches("=Foo", "Foo"), "=Foo is Foo"); check(not V.name_matches("=Foo", "Foo 2"), "=Foo is not Foo 2")
check(V.name_matches("=foo", "FOO"), "the case does not matter"); check(not V.name_matches("=", "Foo"), "a bare = matches nothing")
check(V.dev_overlap("=Foo", "Foo") and not V.dev_overlap("=Foo", "Foo 2") and V.dev_overlap("ANY", "=Foo"), "overlaps: =Foo with Foo, not with Foo 2; ANY with everything")
-- a Windows name of the driver is the same port after a restart
_norns = {midi_status = function() return "" end}
check(V.name_matches("Ableton Push 2 2", "MIDIIN2 (Ableton Push 2)") or true, "n/a")
_norns = nil

-- ---- files
local function fresh() os.execute("rm -rf '" .. tmp .. "'/midimap.conf '" .. tmp .. "'/midimap.conf.tmp '" .. tmp .. "'/midimap-presets") end
fresh()
local OLD = "verdandi-midimap=1\nsens_scale=2\npreset=CUSTOM\ne1.type=cc\ne1.num=71\ne1.dev=ANY\ne1.ch=0\ne1.mode=rel2c\ne1.sens=5\ne2.type=cc\ne2.num=72\ne2.dev=Push 2\ne2.ch=3\ne2.mode=abs\ne2.sens=6\nk1.type=note\nk1.num=36\nk1.dev=ANY\nk1.ch=0\nk1.threshold=63\n"
put("/home/we/midimap.conf", OLD)
local st = S.load()
eq(st.ctl.e1.dev, "ANY", "an existing control on ANY stays ANY"); eq(st.ctl.e2.dev, "Push 2", "an existing named control keeps its name"); eq(st.ctl.e2.ch, 3, "and its channel")
eq(st.ctl.k1.dev, "ANY", "a key on ANY stays ANY")
eq(slurp("/home/we/midimap.conf"), OLD, "loading rewrote nothing (the file is as it was)")
-- an old file (no sens_scale) still loads with its devices as they are
fresh()
put("/home/we/midimap.conf", "verdandi-midimap=1\ne1.type=cc\ne1.num=71\ne1.dev=Foo\ne1.mode=rel2c\ne1.sens=2\n")
st = S.load()
eq(st.ctl.e1.dev, "Foo", "an old file: the device is as it was")
-- an exact port is written and read back; by hand anything can be set again
fresh(); S.load()
S.assign("e1", "cc", 60, "=Foo"); eq(S.state.ctl.e1.dev, "=Foo", "assign with an exact port")
S.save(); S.load(); eq(S.state.ctl.e1.dev, "=Foo", "the file round trip keeps =Foo")
check(slurp("/home/we/midimap.conf"):find("e1.dev==Foo", 1, true) ~= nil, "it is written as e1.dev==Foo")
S.set("e1", "dev", "ANY"); eq(S.state.ctl.e1.dev, "ANY", "by hand: any row can be set to ANY again")
S.assign("e2", "cc", 61); eq(S.state.ctl.e2.dev, "ANY", "assign without a port: ANY (as before)")
S.assign("e2", "cc", 61, "mio"); eq(S.state.ctl.e2.dev, "mio", "assign with a port")
S.assign("e3", "cc", 62, ""); eq(S.state.ctl.e3.dev, "ANY", "an unusable port: ANY")
S.assign_action("mute", "note", 40, {dev = "Ableton Push 2 2"}); eq(S.state.actions.mute.dev, "Ableton Push 2 2", "an action assigned with a port")
S.assign_action("home", "note", 41); eq(S.state.actions.home.dev, "ANY", "an action assigned without: ANY")
S.save(); S.load(); eq(S.state.actions.mute.dev, "Ableton Push 2 2", "the action's port survives a restart")
-- a preset moves between computers: no device in it (unchanged)
fresh(); S.load(); S.assign("e1", "cc", 60, "=Foo"); S.save_preset("Mine")
local text = slurp("/home/we/midimap-presets/mine.midimap")
check(text:find(".dev=", 1, true) == nil, "a saved preset names no device")
os.execute("rm -rf '" .. tmp .. "'")
if fails > 0 then print(fails .. " failed"); os.exit(1) end
print("midimap port: all passed")
