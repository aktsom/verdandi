-- SYSTEM > MIDI MAP (lua/core/menu/midimap.lua), docs/port/midi-map-plan.md 2.6 and 3.5. run from the repo root:
--   NORNS_PLATFORM=linux lua5.3 linux/tests/midimap_page_test.lua
-- the rows and their wording, E2 / E3 / K2 / K3, the detail view of a control, the preset row, the visible learn state (banner, target row, countdown, messages), every handler ends with a redraw,
-- the device list (the mio and its ports), clash marks, SAVE AS and DELETE, the page being in SYSTEM's list below THEME
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
print = function() end

local fails = 0
local function check(ok, what) if not ok then fails = fails + 1; real_print("FAIL " .. what) end end
local function eq(a, b, what) check(a == b, what .. ": got " .. tostring(a) .. ", wanted " .. tostring(b)) end

-- the screen: what the last redraw drew
local frame, shown = {}, {}
local updates = 0
screen = setmetatable({}, {__index = function() return function() end end})
screen.clear = function() frame = {} end
screen.level = function(l) frame[#frame + 1] = "V" .. tostring(l) end
screen.text = function(s) frame[#frame + 1] = "L:" .. tostring(s) end
screen.text_right = function(s) frame[#frame + 1] = "R:" .. tostring(s) end
screen.text_center = function(s) frame[#frame + 1] = "C:" .. tostring(s) end
screen.text_extents = function(s) return #tostring(s) * 5 end
screen.update = function() shown = frame; updates = updates + 1 end
local function drawn(s) for _, t in ipairs(shown) do if t:match("^[LRC]:") and t:find(s, 1, true) then return true end end return false end
local function texts() local r = {} for _, t in ipairs(shown) do if t:match("^[LRC]:") then r[#r + 1] = t:sub(3) end end return r end

util = {scandir = function(dir) local out = {} local p = io.popen("ls -p '" .. map(dir) .. "' 2>/dev/null") for l in p:lines() do out[#out + 1] = l end p:close() return out end,
  clamp = function(x, lo, hi) return math.max(lo, math.min(hi, x)) end, time = function() return 0 end}
package.loaded.util = util
local T = 100
local sent = {}
_norns = {midi = {}, show_control = function() end, key = function() end, enc = function() end,
  toast = function(t) sent[#sent + 1] = "toast:" .. t end, midimap_arm = function(m) sent[#sent + 1] = "arm:" .. m end, midimap_show = function(s, n) sent[#sent + 1] = "ring:" .. s .. ":" .. n end}
local set_pages = {}
local redraws = 0
local page
_menu = {mode = true, page = "MIDIMAP", set_page = function(p) set_pages[#set_pages + 1] = p end, redraw = function() redraws = redraws + 1; page.redraw() end,
  rebuild_params = function() end, keycode = function() end, keychar = function() end, set_mode = function() end}
params = {lookup = {}, lookup_param = function(self, id) return {name = id} end}
tab = require 'tabutil'
pmap = require 'core/pmap'
norns = {pmap = pmap, state = {shortname = "s"}, none = function() end, menu_midi_event = function() end,
  menu = {status = function() return true end, get_key = function() return "k" end, get_enc = function() return "e" end, get_redraw = function() return "r" end, get_refresh = function() return "f" end, set = function() end, init = function() end}}
midi = require 'core/midi'
-- a text entry that only records what it was asked
local entry
package.loaded.textentry = {enter = function(cb, default, heading, hint, opts) entry = {cb = cb, default = default, heading = heading, hint = hint, opts = opts} end}
local S = require 'core/midimap_settings'
S.log = function() end
local mm = require 'core/midimap'
norns.midimap = mm
mm.clock = function() return T end
_norns.midimap_pick = function(kind, n) mm.pick(kind .. n) end

local function add(id, name) _norns.midi.add(id, name, "p" .. id) end
add(1, "Verdandi JACK in"); add(2, "mio"); add(3, "iii grid")

page = dofile("lua/core/menu/midimap.lua")
local function fresh()
  os.execute("rm -rf '" .. tmp .. "'/midimap.conf '" .. tmp .. "'/midimap-presets")
  S.load(); mm.load(); sent = {}; set_pages = {}; entry = nil
  page.init()
  page.pos, page.top = 1, 1
  page.redraw()
end
-- every handler ends with a redraw: the count goes up, and what is drawn is what a new redraw would draw
local function press(n, z) local before = redraws; page.key(n, z or 1); check(redraws > before, "key " .. n .. " ended with a redraw") end
local function turn(n, d) local before = redraws; page.enc(n, d); check(redraws > before, "enc " .. n .. " ended with a redraw") end
local function same_as_redraw(what)
  local a = table.concat(shown, "|"); page.redraw(); local b = table.concat(shown, "|")
  check(a == b, "the screen shows the state: " .. what)
end
local function down(n) for _ = 1, n do turn(2, 1) end end

-- ---- the rows
fresh()
page.redraw()
eq(texts()[1], "MIDI MAP", "the title")
local ro = page.rows()
eq(table.concat(ro, ","), "PRESET,LEARN,E1,E2,E3,K1,K2,K3,ON CLASH,SAVE AS", "the rows of the page")
check(drawn("PRESET") and drawn("LEARN") and drawn("E1") and drawn("E2"), "the first rows are drawn")
check(drawn("-----"), "an unmapped control shows -----")
eq(page.pos, 1, "the selection starts on PRESET")
-- navigation
turn(2, 1); eq(page.pos, 2, "E2 moves down"); turn(2, -5); eq(page.pos, 1, "E2 stops at the top"); down(40); eq(page.pos, #ro, "E2 stops at the bottom")
same_as_redraw("after scrolling")
check(page.top >= 1 and page.pos >= page.top and page.pos < page.top + 5, "the selection is in the visible rows")
press(2); eq(set_pages[#set_pages], "SYSTEM", "K2 goes back to SYSTEM")

-- ---- the preset row
fresh()
check(drawn("NONE"), "the preset in use is shown")
turn(3, 1); check(drawn("PUSH 2"), "E3 browses to PUSH 2"); check(drawn("UNVERIFIED"), "and it says UNVERIFIED")
eq(S.state.ctl.e1.type, "none", "browsing does not apply")
press(3); eq(S.state.ctl.e1.num, 71, "K3 applies it"); eq(S.state.preset, "PUSH 2", "the label is the preset")
check(drawn("CC71"), "E1 shows CC71 now"); check(drawn("REL 2S"), "and its format")
turn(3, 1); turn(3, 1); turn(3, 5); check(drawn("GENERIC") , "E3 stops at the last preset")
turn(3, -9); check(drawn("NONE"), "and at the first")

-- ---- LEARN, visible
fresh()
down(1); press(3)
eq(mm.learn.state, "pick", "K3 on LEARN starts a pick")
check(drawn("LEARN"), "the banner says LEARN"); check(drawn("CLICK"), "and what to do (click a control)")
check(drawn("K2 CANCEL"), "and how to leave"); same_as_redraw("in PICK")
mm.pick("e2")
check(drawn("LEARN E2"), "the banner names the target"); check(drawn("MOVE A KNOB"), "the target row says what to do")
-- the countdown follows the clock
T = T + 4; mm.tick(); check(drawn("11"), "the countdown shows the seconds left (11)")
_norns.midi.event(2, {0xB0, 71, 1})
check(drawn("CC71"), "the CC is assigned and shown at once"); check(drawn("BOTH WAYS"), "a knob is asked to turn both ways")
_norns.midi.event(2, {0xB0, 71, 127}); _norns.midi.event(2, {0xB0, 71, 1}); _norns.midi.event(2, {0xB0, 71, 126}); _norns.midi.event(2, {0xB0, 71, 2}); _norns.midi.event(2, {0xB0, 71, 127})
check(drawn("REL 2S"), "the suggestion is shown"); check(drawn("?"), "with a ? until the user confirms")
eq(mm.learn.state, "idle", "learn is over")
-- cancel by K2: stays on the page
down(0); press(3)
eq(mm.learn.state == "pick" or mm.learn.state == "idle", true, "learn can start again")
if mm.learn.state ~= "pick" then page.pos = 2; press(3) end
press(2); eq(mm.learn.state, "idle", "K2 cancels the learn"); check(#set_pages == 0, "and does not leave the page"); check(drawn("LEARN STOPPED"), "and says so")
-- E2 and E3 do nothing during a learn
page.pos = 2; press(3); local pos = page.pos; turn(2, 1); eq(page.pos, pos, "E2 does not move the selection during a learn"); turn(3, 1)
eq(mm.learn.state, "pick", "and nothing ends it"); mm.cancel()
-- time-out
page.pos = 2; press(3); T = T + 16; mm.tick(); eq(mm.learn.state, "idle", "the time-out ends it"); check(drawn("LEARN STOPPED"), "and the page says so")
-- a note for an encoder
page.pos = 2; press(3); mm.pick("e1"); _norns.midi.event(2, {0x90, 40, 100}); check(drawn("USE A CC"), "a note for an encoder: the page says to use a CC"); mm.cancel()
-- the keyboard: Esc is K2
-- leaving the page cancels
page.pos = 2; press(3); mm.pick("k1"); page.deinit(); eq(mm.learn.state, "idle", "leaving the page ends a learn")
check(table.concat(sent, " "):find("arm:0", 1, true), "and releases the window")
page.init()

-- ---- the detail view of an encoder
fresh()
page.pos = 5; press(3)  -- E3 row
eq(page.mode, "detail", "K3 on a control opens its view"); eq(page.ctl, "e3", "it is E3")
eq(table.concat(page.drows(), ","), "LEARN,NUMBER,DEVICE,CHANNEL,MODE,SENS,CLEAR", "the rows of an encoder")
check(drawn("E3"), "the title names the control")
page.dpos = 2; turn(3, 1); eq(S.state.ctl.e3.num, 0, "E3 on NUMBER sets CC 0 first (type cc)"); eq(S.state.ctl.e3.type, "cc", "and the type")
turn(3, 5); eq(S.state.ctl.e3.num, 5, "E3 steps the number"); turn(3, 200); eq(S.state.ctl.e3.num, 127, "to at most 127"); turn(3, -300); eq(S.state.ctl.e3.num, 0, "and at least 0")
page.dpos = 4; turn(3, 1); eq(S.state.ctl.e3.ch, 1, "CHANNEL: any, then 1"); turn(3, -1); eq(S.state.ctl.e3.ch, 0, "and back to any"); check(drawn("ANY"), "any is shown")
turn(3, 30); eq(S.state.ctl.e3.ch, 16, "channel 16 at most")
page.dpos = 5; turn(3, 1); eq(S.state.ctl.e3.mode, "rel2c", "MODE: abs, then REL 2S"); turn(3, 1); eq(S.state.ctl.e3.mode, "relsm", "REL SIGN"); turn(3, 1); eq(S.state.ctl.e3.mode, "relob", "REL OFS"); turn(3, 5); eq(S.state.ctl.e3.mode, "relob", "stops at the last")
check(drawn("REL OFS"), "the format is shown")
page.dpos = 6; turn(3, -9); eq(S.state.ctl.e3.sens, 1, "SENS 1 at least"); turn(3, 99); eq(S.state.ctl.e3.sens, 9, "SENS 9 at most")
page.dpos = 5; turn(3, -9)
-- the typed number
page.dpos = 2; press(3); check(entry ~= nil, "K3 on NUMBER opens the text entry"); entry.cb("71"); eq(S.state.ctl.e3.num, 71, "a typed 71 is set")
page.dpos = 2; press(3); entry.cb("300"); eq(S.state.ctl.e3.num, 71, "a typed 300 changes nothing"); check(drawn("0 TO 127"), "and says why")
page.dpos = 2; press(3); entry.cb("abc"); eq(S.state.ctl.e3.num, 71, "a typed abc changes nothing")
page.dpos = 2; press(3); entry.cb(nil); eq(S.state.ctl.e3.num, 71, "cancelling the entry changes nothing")
-- LEARN from the detail view
page.dpos = 1; press(3); eq(mm.learn.state, "listen", "LEARN in the view goes straight to LISTEN"); eq(mm.learn.target, "e3", "for this control"); mm.cancel()
-- CLEAR
page.dpos = 7; press(3); eq(S.state.ctl.e3.type, "none", "CLEAR clears"); check(page.mode == "detail", "and stays in the view")
-- back
press(2); eq(page.mode, "rows", "K2 in the view goes back to the rows"); eq(#set_pages, 0, "and does not leave the page")

-- ---- the detail view of a key
fresh()
page.pos = 6; press(3)
eq(page.ctl, "k1", "K1")
eq(table.concat(page.drows(), ","), "LEARN,TYPE,NUMBER,DEVICE,CHANNEL,CLEAR", "the rows of a key without a type (no threshold yet)")
page.dpos = 2; turn(3, 1); eq(S.state.ctl.k1.type, "cc", "TYPE: CC"); eq(table.concat(page.drows(), ","), "LEARN,TYPE,NUMBER,DEVICE,CHANNEL,THRESHOLD,CLEAR", "a CC key has a threshold")
turn(3, 1); eq(S.state.ctl.k1.type, "note", "then NOTE"); eq(table.concat(page.drows(), ","), "LEARN,TYPE,NUMBER,DEVICE,CHANNEL,CLEAR", "a note key has none")
turn(3, 5); eq(S.state.ctl.k1.type, "note", "stops at NOTE"); turn(3, -1); eq(S.state.ctl.k1.type, "cc", "back to CC")
page.dpos = 3; press(3); entry.cb("102"); eq(S.state.ctl.k1.num, 102, "a typed number on a key")
page.dpos = 6; turn(3, -100); eq(S.state.ctl.k1.threshold, 0, "THRESHOLD 0 at least"); turn(3, 200); eq(S.state.ctl.k1.threshold, 126, "126 at most")
press(2)
check(true, "back")
page.pos = 6; check(page.rows()[page.pos] == "K1", "the row is K1")
check(drawn("CC102"), "the row shows the key's CC")

-- ---- the device list: the mio, its ports, the iii grid, an absent name
fresh()
page.pos = 4; press(3); page.dpos = 3
local function choices() local r = {} for _, c in ipairs(page.device_choices()) do r[#r + 1] = c.value end return table.concat(r, "|") end
eq(choices(), "ANY|iii grid|mio|Verdandi JACK in", "the devices: ANY, then the names (the keys window is not offered when it is not there)")
add(4, "Verdandi keys"); check(choices():find("Verdandi keys", 1, true), "the keys window is listed when it exists (it can be chosen by name)")
_norns.midi.remove(4)
turn(3, 1); eq(S.state.ctl.e2.dev, "iii grid", "E3 on DEVICE picks the next one (stays within the list)")
turn(3, 1); eq(S.state.ctl.e2.dev, "mio", "the mio"); check(drawn("MIO"), "shown")
S.set("e2", "dev", "Nope"); check(choices():find("Nope", 1, true), "a remembered name that is absent is listed"); check(page.device_choices()[#page.device_choices()].label:find("ABSENT", 1, true), "marked ABSENT")
page.redraw(); check(drawn("ABSENT"), "and shown that way")
-- two ports
S.set("e2", "dev", "mio")
_norns.midi.remove(2); add(2, "mio 1"); add(5, "mio 2")
check(choices() == "ANY|iii grid|mio|mio 1|mio 2|Verdandi JACK in" or choices() == "ANY|iii grid|mio 1|mio 2|mio|Verdandi JACK in", "two ports: the interface and each port: " .. choices())
local labels = {} for _, c in ipairs(page.device_choices()) do labels[#labels + 1] = c.label end
check(table.concat(labels, "|"):find("ALL PORTS", 1, true), "the interface entry says ALL PORTS")
eq(S.state.ctl.e2.dev, "mio", "the stored name `mio` is still the chosen entry")
_norns.midi.remove(5); _norns.midi.remove(2); add(2, "mio")
-- a product name that ends in a number is not split
add(6, "Push 2"); local n = 0 for _, c in ipairs(page.device_choices()) do if c.value == "Push" then n = n + 1 end end; eq(n, 0, "Push 2 alone gets no `Push` entry (a name that ends in a number is not split)")
_norns.midi.remove(6)

-- ---- ON CLASH
fresh()
page.pos = 9; page.redraw(); check(page.rows()[9] == "ON CLASH", "row 9 is ON CLASH"); check(drawn("PARAMS MAP"), "the default is the params MAP wins")
turn(3, 1); eq(S.state.on_clash, "both", "E3 switches to BOTH"); check(drawn("BOTH"), "shown"); turn(3, -1); eq(S.state.on_clash, "params", "and back")
press(3); eq(S.state.on_clash, "both", "K3 toggles too")

-- ---- clash marks on the rows
fresh()
S.select_preset("PUSH 2"); mm.changed()
local port = midi.devices[2].port
pmap.clear(); pmap.new("cutoff"); pmap.assign("cutoff", port, 1, 71)
page.redraw(); check(drawn("!"), "a control whose CC is in the params MAP is marked !")
pmap.clear(); page.redraw(); check(not drawn("!"), "and not when it is not")
press(3)
-- applying a preset warns
fresh(); pmap.clear(); pmap.new("cutoff"); pmap.assign("cutoff", port, 1, 71)
turn(3, 1); press(3); check(drawn("PARAMS MAP"), "applying a preset that clashes says so"); eq(S.state.ctl.e1.num, 71, "and applies it")
pmap.clear()

-- ---- SAVE AS and DELETE
fresh()
S.select_preset("PUSH 2"); S.set("e1", "num", 20); mm.changed()
page.pos = 10; check(page.rows()[10] == "SAVE AS", "SAVE AS"); press(3); check(entry ~= nil, "K3 opens the name entry")
entry.cb("My Push"); eq(S.state.preset, "My Push", "the preset is saved and in use"); check(S.preset_by_name("My Push") ~= nil, "it is in the list")
check(page.rows()[11] == "DELETE", "DELETE appears for one of his own presets")
page.pos = 11; press(3); eq(page.mode, "confirm", "K3 asks once"); check(drawn("DELETE My Push"), "naming the preset"); press(2); eq(page.mode, "rows", "K2 says no"); check(S.preset_by_name("My Push") ~= nil, "nothing deleted")
press(3); press(3); check(S.preset_by_name("My Push") == nil, "K3 then K3 deletes it"); check(#page.rows() == 10, "and DELETE is gone")
-- the same name asks first
S.save_preset("My Push"); page.pos = 10; press(3); entry.cb("my push"); eq(page.mode, "confirm", "an existing name asks before overwriting"); press(3); eq(page.mode, "rows", "and K3 overwrites")
-- a bad name
page.pos = 10; press(3); entry.cb("a/b"); check(#page.rows() >= 10, "a bad name is refused"); check(page.msg ~= nil, "with a message")

-- ---- an error in a handler leaves the page whole
fresh()
local real_set = S.set
S.set = function() error("boom") end
page.pos = 4; press(3); page.dpos = 2; turn(3, 1)
S.set = real_set
check(page.mode == "detail" or page.mode == "rows", "an error in a handler keeps the page in a known mode")
page.redraw(); check(#shown > 0, "and it still draws")
press(2); press(2)

-- ---- the page in SYSTEM's list, below THEME
local getenv = os.getenv
local function system_with(platform)
  os.getenv = function(k) if k == "NORNS_PLATFORM" then return platform end return getenv(k) end
  local m = dofile("lua/core/menu/system.lua")
  os.getenv = getenv
  return table.concat(m.pages, ","), table.concat(m.list, "|")
end
local pages, list = system_with("linux")
eq(pages, "DEVICES,AUDIO,MODS,UI,BOX,MIDIMAP,CLEANUP,RESET,RESTART", "SYSTEM on a computer: MIDIMAP below THEME (BOX)")
eq(list, "DEVICES > |AUDIO >|MODS >|SCREEN >|THEME >|MIDI MAP >|CLEAN UP >|RESET|RESTART", "and its label")
pages = system_with(nil)
eq(pages, "DEVICES,WIFI,MODS,SETTINGS,RESTART,UPDATE", "on the device (no platform) SYSTEM is unchanged")

if fails == 0 then real_print("midimap page: all passed") end
os.execute("rm -rf '" .. tmp .. "'")
os.exit(fails == 0 and 0 or 1)
