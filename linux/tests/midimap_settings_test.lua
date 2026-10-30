-- MIDI MAP settings and presets (lua/core/midimap_settings.lua): midimap.conf and midimap-presets/, docs/port/midi-map-plan.md 2.7 and 3.4. run from the repo root:
--   NORNS_PLATFORM=linux lua5.3 linux/tests/midimap_settings_test.lua
-- defaults, round trip, every damaged value, unknown keys kept, preset files (valid, damaged, wrong name, duplicates, too many, a dev line), built-in presets, atomic save
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
util = {scandir = function(dir) local out = {} local p = io.popen("ls -p '" .. map(dir) .. "' 2>/dev/null") for l in p:lines() do out[#out + 1] = l end p:close() return out end,
  clamp = function(x, lo, hi) return math.max(lo, math.min(hi, x)) end}
package.loaded.util = util
local S = require 'core/midimap_settings'
local logs = {}
S.log = function(s) logs[#logs + 1] = s end
local function logged(part) for _, l in ipairs(logs) do if l:find(part, 1, true) then return true end end return false end
local function fresh() logs = {}; os.execute("rm -rf '" .. tmp .. "'/midimap.conf '" .. tmp .. "'/midimap.conf.tmp '" .. tmp .. "'/midimap-presets") end

eq(S.PATH, "/home/we/midimap.conf", "the file is in the home")
eq(S.DIR, "/home/we/midimap-presets/", "the presets are in the home")

-- ---- defaults
fresh()
local st = S.load()
eq(st.preset, "NONE", "default preset")
eq(st.on_clash, "params", "default clash rule: the params MAP wins")
for _, id in ipairs({"e1", "e2", "e3", "k1", "k2", "k3"}) do
  local c = st.ctl[id]
  eq(c.type, "none", id .. " default type")
  eq(c.dev, "ANY", id .. " default device")
  eq(c.ch, 0, id .. " default channel")
  if id:sub(1, 1) == "e" then eq(c.mode, "abs", id .. " default mode"); eq(c.sens, 5, id .. " default sens")
  else eq(c.threshold, 63, id .. " default threshold") end
end
check(logged("not found"), "a missing file is logged and defaults are used")
check(slurp("/home/we/midimap.conf") == nil, "loading writes nothing")

-- ---- set, round trip
fresh()
S.load()
local ok = S.set("e2", "type", "cc"); check(ok, "set type")
S.set("e2", "num", 71); S.set("e2", "dev", "mio"); S.set("e2", "ch", 3); S.set("e2", "mode", "rel2c"); S.set("e2", "sens", 7)
S.set("k3", "type", "note"); S.set("k3", "num", 36); S.set("k3", "dev", "Push 2 1")
S.set("k1", "type", "cc"); S.set("k1", "num", 102); S.set("k1", "threshold", 40)
S.set_clash("both")
local text = slurp("/home/we/midimap.conf")
check(text ~= nil and text:find("^verdandi%-midimap=1\n"), "the file starts with the header")
check(text:find("e2.num=71", 1, true) and text:find("e2.dev=mio", 1, true) and text:find("e2.mode=rel2c", 1, true), "the file has the values")
check(text:find("on_clash=both", 1, true), "the clash switch is saved")
check(text:find("preset=CUSTOM", 1, true), "a change makes the label CUSTOM")
check(slurp("/home/we/midimap.conf.tmp") == nil, "the temporary file is gone (atomic save)")
logs = {}
local again = S.load()
local e2 = again.ctl.e2
eq(e2.type, "cc", "round trip type"); eq(e2.num, 71, "round trip num"); eq(e2.dev, "mio", "round trip dev"); eq(e2.ch, 3, "round trip ch")
eq(e2.mode, "rel2c", "round trip mode"); eq(e2.sens, 7, "round trip sens")
eq(again.ctl.k3.type, "note", "round trip note"); eq(again.ctl.k3.num, 36, "round trip note number"); eq(again.ctl.k3.dev, "Push 2 1", "round trip a name with a number")
eq(again.ctl.k1.threshold, 40, "round trip threshold"); eq(again.on_clash, "both", "round trip clash")
eq(#logs, 0, "a good file logs nothing")
-- clear
S.clear("e2")
eq(S.state.ctl.e2.type, "none", "clear: type none")
eq(S.state.ctl.e2.dev, "ANY", "clear: back to ANY")
eq(S.load().ctl.e2.type, "none", "clear is saved")

-- ---- validation of set
fresh(); S.load()
local function bad(id, f, v, what) local ok2, why = S.set(id, f, v); check(ok2 == false and type(why) == "string", what .. " refused"); end
bad("e1", "num", 128, "CC 128"); bad("e1", "num", -1, "CC -1"); bad("e1", "num", 1.5, "CC 1.5"); bad("e1", "num", "x", "CC x")
bad("e1", "type", "note", "a note on an encoder"); bad("e1", "type", "sysex", "an unknown type")
bad("e1", "ch", 17, "channel 17"); bad("e1", "ch", -1, "channel -1")
bad("e1", "mode", "rel9", "unknown mode"); bad("e1", "sens", 0, "sens 0"); bad("e1", "sens", 10, "sens 10")
bad("k1", "mode", "abs", "a mode on a key"); bad("k1", "threshold", 127, "threshold 127"); bad("k1", "threshold", -1, "threshold -1")
bad("e1", "threshold", 10, "a threshold on an encoder"); bad("e9", "num", 1, "an unknown control")
bad("e1", "dev", "", "an empty device name"); bad("e1", "dev", "a\1b", "a control character in a name"); bad("e1", "dev", string.rep("x", 81), "a name of 81 characters")
bad("e1", "dev", "a\nb", "a newline in a name")
local okc = S.set_clash("nonsense"); check(okc == false, "an unknown clash rule is refused")
eq(S.state.ctl.e1.type, "none", "nothing changed by the refused values")
check(S.set("e1", "dev", "any") and S.state.ctl.e1.dev == "ANY", "any is ANY in any case")
check(S.set("e1", "dev", "  mio  ") and S.state.ctl.e1.dev == "mio", "a stored name is trimmed")

-- ---- damaged files
local function load_text(t) fresh(); put("/home/we/midimap.conf", t); return S.load() end
st = load_text("verdandi-midimap=1\ne1.type=cc\ne1.num=300\ne2.type=cc\ne2.num=21\ne2.mode=zigzag\ne2.sens=99\ne3.type=note\ne3.num=40\n")
eq(st.ctl.e1.type, "none", "e1: CC 300 is refused, the control stays none")
check(logged("e1.num=300"), "e1.num is logged")
eq(st.ctl.e2.type, "cc", "e2 is kept"); eq(st.ctl.e2.num, 21, "e2 num kept"); eq(st.ctl.e2.mode, "abs", "e2: a damaged mode is abs"); eq(st.ctl.e2.sens, 5, "e2: a damaged sens is 5")
check(logged("e2.mode=zigzag") and logged("e2.sens=99"), "both are logged")
eq(st.ctl.e3.type, "none", "e3: a note on an encoder is refused"); check(logged("e3.type=note"), "and logged")
st = load_text("verdandi-midimap=1\nk1.type=cc\nk1.num=5\nk1.threshold=500\nk1.ch=40\nk1.dev=\nk2.type=bogus\non_clash=maybe\n")
eq(st.ctl.k1.threshold, 63, "a damaged threshold is 63"); eq(st.ctl.k1.ch, 0, "a damaged channel is any"); eq(st.ctl.k1.dev, "ANY", "an empty device is ANY")
eq(st.ctl.k1.type, "cc", "the rest of k1 is kept"); eq(st.ctl.k2.type, "none", "k2: an unknown type is none"); eq(st.on_clash, "params", "a damaged clash rule is params")
-- a control with a type and no number is none
st = load_text("verdandi-midimap=1\ne1.type=cc\n")
eq(st.ctl.e1.type, "none", "a type without a number is none"); check(logged("e1"), "and logged")
-- a name with = in it, and trailing blanks
st = load_text("verdandi-midimap=1\ne1.type=cc\ne1.num=1\ne1.dev=a=b c  \n")
eq(st.ctl.e1.dev, "a=b c", "a device name may hold =")
-- unknown keys are ignored with a log line and kept when the file is written again
st = load_text("verdandi-midimap=1\nfuture.thing=7\ne1.type=cc\ne1.num=9\ne1.colour=red\n")
check(logged("future.thing"), "an unknown key is logged"); check(logged("e1.colour"), "an unknown field is logged")
S.save()
text = slurp("/home/we/midimap.conf")
check(text:find("future.thing=7", 1, true) and text:find("e1.colour=red", 1, true), "unknown keys are kept in the file")
-- no header, junk, binary, empty, huge
st = load_text("e1.type=cc\ne1.num=9\n")
eq(st.ctl.e1.num, 9, "a file without the header is still read"); check(logged("header"), "and the missing header is logged")
st = load_text("verdandi-midimap=7\ne1.type=cc\ne1.num=9\n")
eq(st.ctl.e1.num, 9, "a newer version is read as far as understood"); check(logged("newer") or logged("version"), "and says so")
st = load_text("\0\1\2binary\255\254\n")
eq(st.ctl.e1.type, "none", "binary junk gives defaults"); check(#logs > 0, "and a log line")
st = load_text("")
eq(st.ctl.e1.type, "none", "an empty file gives defaults")
st = load_text(string.rep("a=b\n", 20000))
eq(st.ctl.e1.type, "none", "a huge file gives defaults without an error")
st = load_text("verdandi-midimap=1\nno equals sign here\n\n  \ne1.type=cc\ne1.num=2\n")
eq(st.ctl.e1.num, 2, "lines without = are skipped"); check(logged("without"), "and logged")
st = load_text("verdandi-midimap=1\r\ne1.type=cc\r\ne1.num=3\r\n")
eq(st.ctl.e1.num, 3, "CRLF line ends are accepted")

-- ---- the failed save keeps the old file
fresh(); S.load(); S.set("e1", "type", "cc"); S.set("e1", "num", 5)
local before = slurp("/home/we/midimap.conf")
local real_rename2 = os.rename
os.rename = function() return nil end
local saved = S.save()
os.rename = real_rename2
eq(saved, false, "a failed rename reports false"); eq(slurp("/home/we/midimap.conf"), before, "the old file is untouched")

-- ---- built-in presets
fresh(); S.load()
local list = S.preset_list()
eq(list[1].name, "NONE", "the first preset is NONE"); local names = {}
for _, p in ipairs(list) do names[p.name] = p; check(p.builtin == true, p.name .. " is built in") end
check(names["PUSH 2"] ~= nil and names["PUSH 2"].unverified == true, "PUSH 2 is there and marked unverified")
check(names["GENERIC REL 2S"] ~= nil and not names["GENERIC REL 2S"].unverified, "GENERIC REL 2S")
local p2 = names["PUSH 2"]
eq(p2.ctl.e1.num, 71, "PUSH 2 e1 = CC 71"); eq(p2.ctl.e3.num, 73, "PUSH 2 e3 = CC 73"); eq(p2.ctl.e2.mode, "rel2c", "PUSH 2 encoders are two's complement")
eq(p2.ctl.k1.num, 102, "PUSH 2 k1 = CC 102"); eq(p2.ctl.k3.num, 104, "PUSH 2 k3 = CC 104"); eq(p2.ctl.k1.type, "cc", "PUSH 2 keys are CC")
check(p2.label ~= nil and p2.label:upper():find("UNVERIFIED", 1, true), "the preset list shows it as unverified")
for _, p in ipairs(list) do
  for _, id in ipairs({"e1", "e2", "e3", "k1", "k2", "k3"}) do
    check(p.ctl[id] ~= nil, p.name .. " has " .. id)
    check(p.ctl[id].dev == nil or p.ctl[id].dev == "ANY", p.name .. " " .. id .. " does not name a device")
  end
end
-- selecting
S.set("e1", "dev", "mio"); S.set_clash("both")
local oks = S.select_preset("PUSH 2"); check(oks, "select PUSH 2")
eq(S.state.preset, "PUSH 2", "the label is the preset"); eq(S.state.ctl.e1.num, 71, "the mapping is the preset's"); eq(S.state.ctl.e1.dev, "ANY", "a preset sets the device to ANY")
eq(S.state.on_clash, "both", "a preset does not change the clash rule")
eq(S.load().preset, "PUSH 2", "the choice is saved")
S.set("e1", "num", 99)
eq(S.state.preset, "CUSTOM", "a change of a preset's mapping makes it CUSTOM")
check(S.select_preset("NONE") and S.state.ctl.e1.type == "none", "NONE clears all six")
check(not S.select_preset("NO SUCH"), "an unknown preset is refused")
-- step through the list
S.select_preset("NONE")

-- ---- own presets
fresh(); S.load()
S.select_preset("PUSH 2"); S.set("e1", "num", 20); S.set("e1", "dev", "mio"); S.set("e1", "ch", 5)
local okp, why = S.save_preset("My Push")
check(okp, "save a preset: " .. tostring(why))
local ptext = slurp("/home/we/midimap-presets/my-push.midimap")
check(ptext ~= nil and ptext:find("^verdandi%-midimap%-preset=1\n"), "the preset file has its header")
check(ptext:find("name=My Push", 1, true) and ptext:find("e1.num=20", 1, true), "the preset file has the name and the mapping")
check(not ptext:find("%.dev="), "a preset file has no device line")
check(not ptext:find("%.ch="), "a preset file has no channel line")
check(not ptext:find("on_clash", 1, true), "a preset file has no clash rule")
eq(S.state.preset, "My Push", "the saved preset is in use")
local found = S.preset_by_name("My Push"); check(found and not found.builtin, "it is in the list as one of his own")
-- exists
local ok2, why2, existing = S.save_preset("my push")
check(ok2 == false and why2 == "exists" and existing == "My Push", "the same name asks first (slug)")
check(S.save_preset("my push", true), "overwrite")
-- names
for _, n in ipairs({"", "   ", "a/b", "..", "NONE", "PUSH 2", string.rep("x", 19), "a\1b", "\195\164"}) do
  local okn = S.save_preset(n); check(okn == false, "the name '" .. n:gsub("%c", "?") .. "' is refused")
end
-- reload: a new world sees the file
S.load()
check(S.preset_by_name("My Push") ~= nil, "after a load the own preset is still there")
S.select_preset("My Push")
eq(S.state.ctl.e1.num, 20, "own preset applies"); eq(S.state.ctl.e1.dev, "ANY", "own preset: ANY device"); eq(S.state.ctl.e1.ch, 0, "own preset: any channel")
-- delete
check(not S.delete_preset("PUSH 2"), "a built-in preset is not deleted")
check(S.delete_preset("My Push"), "own preset deleted"); check(slurp("/home/we/midimap-presets/my-push.midimap") == nil, "the file is gone")
eq(S.state.preset, "CUSTOM", "the label reads CUSTOM after the delete"); eq(S.state.ctl.e1.num, 20, "the mapping stays")
check(not S.delete_preset("My Push"), "deleting twice is refused")

-- ---- damaged preset files
fresh(); os.execute("mkdir -p /home/we/midimap-presets")
put("/home/we/midimap-presets/ok.midimap", "verdandi-midimap-preset=1\nname=ok\ne1.type=cc\ne1.num=4\ne1.mode=relsm\n")
put("/home/we/midimap-presets/bad-header.midimap", "verdandi-midimap=1\nname=bad header\n")
put("/home/we/midimap-presets/newer.midimap", "verdandi-midimap-preset=9\nname=newer\n")
put("/home/we/midimap-presets/wrong-name.midimap", "verdandi-midimap-preset=1\nname=something else\n")
put("/home/we/midimap-presets/junk.midimap", "\0\1\2\255")
put("/home/we/midimap-presets/empty.midimap", "")
put("/home/we/midimap-presets/huge.midimap", "verdandi-midimap-preset=1\nname=huge\n" .. string.rep("x", 5000))
put("/home/we/midimap-presets/dev-line.midimap", "verdandi-midimap-preset=1\nname=dev line\ne1.type=cc\ne1.num=7\ne1.dev=mio\ne1.ch=4\n")
put("/home/we/midimap-presets/not-a-preset.txt", "verdandi-midimap-preset=1\nname=not a preset\n")
put("/home/we/midimap-presets/NONE.midimap", "verdandi-midimap-preset=1\nname=NONE\n")
put("/home/we/midimap-presets/bad-value.midimap", "verdandi-midimap-preset=1\nname=bad value\ne1.type=cc\ne1.num=999\n")
logs = {}
S.load()
check(S.preset_by_name("ok") ~= nil, "a good file is read")
eq(S.preset_by_name("ok").ctl.e1.mode, "relsm", "its values are read")
for _, n in ipairs({"bad header", "newer", "something else", "huge", "not a preset"}) do check(S.preset_by_name(n) == nil, "'" .. n .. "' is ignored") end
check(logged("bad-header.midimap") and logged("newer.midimap") and logged("wrong-name.midimap") and logged("junk.midimap") and logged("empty.midimap") and logged("huge.midimap"), "every bad file has a log line")
local dl = S.preset_by_name("dev line")
check(dl ~= nil and dl.ctl.e1.num == 7, "a dev line does not make the file invalid")
check(dl.ctl.e1.dev == "ANY" and dl.ctl.e1.ch == 0, "but the device and the channel in it are ignored")
check(S.preset_by_name("bad value") == nil or S.preset_by_name("bad value").ctl.e1.type == "none", "a bad value in a preset file does not give a bad mapping")
local count = 0
for _, p in ipairs(S.preset_list()) do if p.name == "NONE" then count = count + 1 end end
eq(count, 1, "a file named like a built-in preset does not replace or duplicate it")
-- the maximum
fresh(); os.execute("mkdir -p /home/we/midimap-presets")
for i = 1, S.MAX_PRESETS + 3 do
  local n = string.format("p%02d", i)
  put("/home/we/midimap-presets/" .. n .. ".midimap", "verdandi-midimap-preset=1\nname=" .. n .. "\n")
end
logs = {}
S.load()
local own = 0
for _, p in ipairs(S.preset_list()) do if not p.builtin then own = own + 1 end end
eq(own, S.MAX_PRESETS, "no more than the maximum are read"); check(logged("more than"), "and it is logged")
eq(S.MAX_PRESETS, 64, "the maximum is 64")
local okm, whym = S.save_preset("one more"); check(okm == false and tostring(whym):find("64", 1, true), "a new one past the maximum is refused with the number")

if fails == 0 then print("midimap settings: all passed") end
os.execute("rm -rf '" .. tmp .. "'")
os.exit(fails == 0 and 0 or 1)
