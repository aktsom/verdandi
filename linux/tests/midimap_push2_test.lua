-- the built-in PUSH 2 preset (M26): the owner's mapping, saved from the real Push 2, compared control by control and action by action; run on every platform:
--   NORNS_PLATFORM=linux lua5.3 linux/tests/midimap_push2_test.lua   (also windows and macos: the Mac has "keys" where the others have "pin", and the pin line is skipped there without a word)
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
local function put(p, text) os.execute("mkdir -p '" .. tmp .. "/midimap-presets'"); local h = real_open(map(p), "w"); h:write(text); h:close() end
util = {scandir = function(dir) local out = {} local p = io.popen("ls -p '" .. map(dir) .. "' 2>/dev/null") for l in p:lines() do out[#out + 1] = l end p:close() return out end,
  clamp = function(x, lo, hi) return math.max(lo, math.min(hi, x)) end}
package.loaded.util = util
local S = require 'core/midimap_settings'
local logs = {}
S.log = function(s) logs[#logs + 1] = s end
local function logged(part) for _, l in ipairs(logs) do if l:find(part, 1, true) then return true end end return false end
local function fresh() logs = {}; os.execute("rm -rf '" .. tmp .. "'/midimap.conf '" .. tmp .. "'/midimap.conf.tmp '" .. tmp .. "'/midimap-presets") end
local PLAT = os.getenv("NORNS_PLATFORM")
local PINID = (PLAT == "windows" or PLAT == "linux") and "pin" or "keys"

-- the owner's values (the saved preset file, without its name line)
local CTL = {
  e1 = {num = 15, mode = "rel2c", sens = 5}, e2 = {num = 71, mode = "rel2c", sens = 5}, e3 = {num = 72, mode = "rel2c", sens = 5},
  k1 = {num = 9, threshold = 63}, k2 = {num = 102, threshold = 63}, k3 = {num = 103, threshold = 63},
}
local ARC = {a1 = 75, a2 = 76, a3 = 77, a4 = 78}
local ACT = {mix = 20, tape = 21, home = 22, params = 23, arc = 24, pin = 25, mute = 27, detach = 26}
local NONE_ACT = {"input", "grid", "maiden", "manual", "fullscreen", "screenshot"}

local function compare(where)
  for id, want in pairs(CTL) do
    local c = S.state.ctl[id]
    eq(c.type, "cc", where .. " " .. id .. " type"); eq(c.num, want.num, where .. " " .. id .. " number"); eq(c.dev, "ANY", where .. " " .. id .. " device"); eq(c.ch, 0, where .. " " .. id .. " channel")
    if want.mode then eq(c.mode, want.mode, where .. " " .. id .. " mode"); eq(c.sens, want.sens, where .. " " .. id .. " sensitivity (the current scale)") end
    if want.threshold then eq(c.threshold, want.threshold, where .. " " .. id .. " threshold") end
  end
  for id, num in pairs(ARC) do
    local c = S.state.ctl[id]
    eq(c.type, "cc", where .. " " .. id .. " type"); eq(c.num, num, where .. " " .. id .. " number"); eq(c.mode, "rel2c", where .. " " .. id .. " mode"); eq(c.gain, 3, where .. " " .. id .. " gain"); eq(c.accel, "off", where .. " " .. id .. " accel"); eq(c.dev, "ANY", where .. " " .. id .. " device"); eq(c.ch, 0, where .. " " .. id .. " channel")
  end
  for name, num in pairs(ACT) do
    local id = name == "pin" and PINID or name
    if id == "keys" then
      check(S.state.actions.keys == nil or S.state.actions.keys.type == "none", where .. " the Mac has no pin: nothing is set on keys")
    else
      local a = S.state.actions[id]
      eq(a.type, "step", where .. " act." .. id .. " type"); eq(a.num, num, where .. " act." .. id .. " number"); eq(a.mode, "rel2c", where .. " act." .. id .. " mode"); eq(a.dir, "down", where .. " act." .. id .. " direction"); eq(a.dev, "ANY", where .. " act." .. id .. " device"); eq(a.ch, 0, where .. " act." .. id .. " channel")
    end
  end
  for _, id in ipairs(NONE_ACT) do eq(S.state.actions[id].type, "none", where .. " act." .. id .. " is none") end
end

-- ---- the preset as it is in the list
fresh(); S.load()
local p
for _, q in ipairs(S.preset_list()) do if q.name == "PUSH 2" then p = q end end
check(p ~= nil and p.builtin == true, "PUSH 2 is a built-in preset")
eq(p.label, "PUSH 2", "the label has no (UNVERIFIED)"); check(not p.unverified, "it is not unverified"); check(p.arcs ~= nil and p.actions ~= nil, "it carries the arc encoders and the actions")
for _, id in ipairs({"e1", "e2", "e3", "k1", "k2", "k3"}) do check(p.ctl[id].dev == nil or p.ctl[id].dev == "ANY", "no device in " .. id) end
check(#logs == 0 or not logged("built-in PUSH 2"), "building it said nothing (every value passed its checks)")

-- ---- select it: every control and every action
fresh(); S.load()
S.set("e1", "dev", "mio"); S.set("e1", "ch", 4)
check(S.select_preset("PUSH 2"), "select PUSH 2")
eq(S.state.preset, "PUSH 2", "the label is PUSH 2")
compare("selected:")
-- the sensitivity is not converted a second time: saved with sens_scale=2, read back it is the same number
local text = slurp("/home/we/midimap.conf")
check(text:find("sens_scale=2", 1, true) ~= nil, "the settings file says sens_scale=2")
check(text:find("e1.sens=5", 1, true) and text:find("e2.sens=5", 1, true) and text:find("e3.sens=5", 1, true), "the file has sens=5 for the three encoders (the current scale)")
S.load(); compare("after a reload:")
eq(S.state.ctl.e2.sens, 5, "e2 sens is still 5 after the reload (not converted twice)")
for i = 1, 3 do S.load() end
eq(S.state.ctl.e1.sens, 5, "and after three more reloads")
-- as a preset file of the owner's, written by hand with sens_scale=2: the same numbers
local own = "verdandi-midimap-preset=1\nname=My Own\nsens_scale=2\ne1.type=cc\ne1.num=15\ne1.mode=rel2c\ne1.sens=5\n"
put("/home/we/midimap-presets/my-own.midimap", own)
S.reload_presets()
local q; for _, x in ipairs(S.preset_list()) do if x.name == "My Own" then q = x end end
eq(q and q.ctl.e1.sens, 5, "an own preset file with sens_scale=2 and sens=5 is read as 5 (the built-in uses the same numbers)")

-- ---- a settings file with preset=PUSH 2 loads, and keeps what the file holds (the mappings are the file's, not the preset's)
fresh()
put("/home/we/midimap.conf", "verdandi-midimap=1\nsens_scale=2\npreset=PUSH 2\ne1.type=cc\ne1.num=33\ne1.mode=rel2c\ne1.sens=7\n")
S.load()
eq(S.state.preset, "PUSH 2", "preset=PUSH 2 in a settings file is accepted")
eq(S.state.ctl.e1.num, 33, "the mapping of the file is kept (a saved file changes its meaning only when the preset is chosen again)"); eq(S.state.ctl.e1.sens, 7, "its sensitivity too")
check(not logged("no such preset"), "no complaint about the preset")

-- ---- the owner's own files are not touched by the update (loading, listing and reloading write nothing)
fresh()
local conf = "verdandi-midimap=1\nsens_scale=2\npreset=CUSTOM\ne1.type=cc\ne1.num=44\ne1.mode=rel2c\ne1.sens=3\n"
local pre = "verdandi-midimap-preset=1\nname=Studio\nsens_scale=2\ne1.type=cc\ne1.num=45\ne1.mode=rel2c\ne1.sens=4\nact.mix.type=note\nact.mix.num=60\n"
put("/home/we/midimap.conf", conf); put("/home/we/midimap-presets/studio.midimap", pre)
S.load(); S.reload_presets(); S.preset_list()
eq(slurp("/home/we/midimap.conf"), conf, "midimap.conf is byte for byte the same after loading")
eq(slurp("/home/we/midimap-presets/studio.midimap"), pre, "an own preset file is byte for byte the same")
eq(S.state.ctl.e1.num, 44, "and the loaded mapping is the file's")

-- ---- a preset file saved under the old name PUSH 2 does not break anything: the name is a built-in one, the file is ignored with a line in the log
fresh()
put("/home/we/midimap-presets/push-2.midimap", "verdandi-midimap-preset=1\nname=PUSH 2\ne1.type=cc\ne1.num=71\ne1.mode=rel2c\n")
logs = {}
S.load()
local n = 0; for _, x in ipairs(S.preset_list()) do if x.name == "PUSH 2" then n = n + 1; check(x.builtin, "the PUSH 2 in the list is the built-in one") end end
eq(n, 1, "one PUSH 2 in the list")
check(logged("push-2.midimap") or logged("built-in"), "the old file is said in the log")
S.select_preset("PUSH 2"); eq(S.state.ctl.e1.num, 15, "choosing PUSH 2 gives the owner's mapping, not the old file's")

-- ---- an action that does not exist on this platform is skipped without a word (the Mac has keys, not pin); a made-up one too
local before = #logs
fresh(); S.load(); S.select_preset("PUSH 2")
check(not logged("act.pin") and not logged("act.keys"), "no line about pin or keys in the log")
check(S.state.actions.pin == nil or PINID == "pin", "the Mac has no pin action to fill")

-- ---- the mechanism for presets that really are unverified is still there
table.insert(S.BUILTIN, {name = "TEST UNVERIFIED", label = "TEST UNVERIFIED", builtin = true, unverified = true, ctl = {}})
local found
for _, x in ipairs(S.preset_list()) do if x.name == "TEST UNVERIFIED" then found = x end end
check(found ~= nil and found.unverified == true, "a built-in marked unverified is still marked")
table.remove(S.BUILTIN)

if fails == 0 then print("midimap push2: all passed") end
os.execute("rm -rf '" .. tmp .. "'")
os.exit(fails == 0 and 0 or 1)
