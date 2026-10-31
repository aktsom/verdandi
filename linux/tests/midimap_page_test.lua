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
  toast = function(t) sent[#sent + 1] = "toast:" .. t end, arc_turn = function(n, t) sent[#sent + 1] = "arc:" .. n .. ":" .. t; return true end, midimap_arm = function(m) sent[#sent + 1] = "arm:" .. m end, midimap_show = function(s, n) sent[#sent + 1] = "ring:" .. s .. ":" .. n end}
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
eq(table.concat(ro, ","), "PRESET,LEARN,E1,E2,E3,K1,K2,K3,A1,A2,A3,A4,ACTIONS,WATCH,ON CLASH,ARC KEYS,MIDI ACTIONS,SAVE AS", "the rows of the page")
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
page.pos = 15; page.redraw(); check(page.rows()[15] == "ON CLASH", "row 15 is ON CLASH"); check(drawn("PARAMS MAP"), "the default is the params MAP wins")
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
page.pos = 18; check(page.rows()[18] == "SAVE AS", "SAVE AS"); press(3); check(entry ~= nil, "K3 opens the name entry")
entry.cb("My Push"); eq(S.state.preset, "My Push", "the preset is saved and in use"); check(S.preset_by_name("My Push") ~= nil, "it is in the list")
check(page.rows()[19] == "DELETE", "DELETE appears for one of his own presets")
page.pos = 19; press(3); eq(page.mode, "confirm", "K3 asks once"); check(drawn("DELETE My Push"), "naming the preset"); press(2); eq(page.mode, "rows", "K2 says no"); check(S.preset_by_name("My Push") ~= nil, "nothing deleted")
press(3); press(3); check(S.preset_by_name("My Push") == nil, "K3 then K3 deletes it"); check(#page.rows() == 18, "and DELETE is gone")
-- the same name asks first
S.save_preset("My Push"); page.pos = 18; press(3); entry.cb("my push"); eq(page.mode, "confirm", "an existing name asks before overwriting"); press(3); eq(page.mode, "rows", "and K3 overwrites")
-- a bad name
page.pos = 18; press(3); entry.cb("a/b"); check(#page.rows() >= 18, "a bad name is refused"); check(page.msg ~= nil, "with a message")

-- ---- an error in a handler leaves the page whole
fresh()
local real_set = S.set
S.set = function() error("boom") end
page.pos = 4; press(3); page.dpos = 2; turn(3, 1)
S.set = real_set
check(page.mode == "detail" or page.mode == "rows", "an error in a handler keeps the page in a known mode")
page.redraw(); check(#shown > 0, "and it still draws")
press(2); press(2)


-- ---- the arc encoders A1 to A4, ARC KEYS and WATCH (docs/port/arc-plan.md)
fresh()
page.pos = 9; page.redraw()
check(page.rows()[9] == "A1" and page.rows()[12] == "A4", "A1 to A4 follow K3")
check(drawn("A1") and drawn("-----"), "an empty arc encoder shows -----")
press(3)
eq(page.mode, "detail", "K3 on A1 opens its view"); eq(page.ctl, "a1", "it is A1")
eq(table.concat(page.drows(), ","), "LEARN,NUMBER,DEVICE,CHANNEL,MODE,GAIN,ACCEL,ONE TURN,CLEAR", "the rows of an arc encoder: GAIN and ACCEL, no SENS")
page.dpos = 2; turn(3, 1); eq(S.state.ctl.a1.num, 0, "NUMBER sets CC 0 first"); turn(3, 76); eq(S.state.ctl.a1.num, 76, "E3 steps the number"); eq(S.state.ctl.a1.type, "cc", "a CC")
page.dpos = 5; turn(3, 1); turn(3, 1); eq(S.state.ctl.a1.mode, "relsm", "MODE steps"); turn(3, 1); eq(S.state.ctl.a1.mode, "relob", "to REL OFS"); check(drawn("REL OFS"), "shown")
page.dpos = 6; page.redraw(); check(drawn("GAIN") and drawn("8"), "GAIN shows its default"); turn(3, 4); eq(S.state.ctl.a1.gain, 12, "E3 steps the gain"); turn(3, 200); eq(S.state.ctl.a1.gain, 64, "to 64 at most"); turn(3, -200); eq(S.state.ctl.a1.gain, 1, "and 1 at least")
turn(3, 7); eq(S.state.ctl.a1.gain, 8, "back to 8")
page.dpos = 7; page.redraw(); check(drawn("ACCEL") and drawn("OFF"), "ACCEL is off by default"); turn(3, 1); eq(S.state.ctl.a1.accel, "low", "ACCEL low"); turn(3, 1); eq(S.state.ctl.a1.accel, "high", "high"); turn(3, 5); eq(S.state.ctl.a1.accel, "high", "stops at high"); turn(3, -9); eq(S.state.ctl.a1.accel, "off", "and at off")
press(2); page.pos = 9; page.redraw(); check(drawn("CC76 REL OFS"), "the row shows the arc encoder's mapping")
-- LEARN from the view, and from the page
press(3); page.dpos = 1; press(3); eq(mm.learn.state, "listen", "LEARN in the view goes to LISTEN"); eq(mm.learn.target, "a1", "for A1"); check(drawn("LEARN A1"), "the banner names it"); check(drawn("MOVE A KNOB"), "and the row says what to do"); mm.cancel()
press(2)
-- ONE TURN
page.pos = 9; press(3); page.dpos = 8; press(3)
eq(page.mode, "turn", "K3 on ONE TURN opens the counting view"); eq(mm.calib_target(), "a1", "calibrating A1"); check(drawn("ONE TURN"), "the view says so"); check(drawn("0"), "and counts from 0")
for _ = 1, 16 do _norns.midi.event(2, {0xB0, 76, 72}) end -- offset binary: 72 = +8 each
check(drawn("128"), "the view shows the units counted (16 x 8 = 128)")
reset_sent = nil
press(3); eq(S.state.ctl.a1.gain, 8, "K3 stores the gain: 1024 / 128 = 8"); eq(page.mode, "detail", "and goes back to the view"); check(page.msg ~= nil and page.msg:find("8", 1, true), "and says it")
page.dpos = 8; press(3); for _ = 1, 4 do _norns.midi.event(2, {0xB0, 76, 72}) end; press(2); eq(mm.calib_target(), nil, "K2 cancels the calibration"); eq(S.state.ctl.a1.gain, 8, "and keeps the gain")
page.dpos = 8; press(3); press(3); check(page.msg ~= nil, "K3 with nothing counted says so"); eq(S.state.ctl.a1.gain, 8, "and keeps the gain")
page.mode = "detail"
-- every control in the turn view ends with a redraw: E2, E3 do nothing there
page.dpos = 8; press(3); turn(2, 1); turn(3, 1); eq(page.mode, "turn", "E2 and E3 leave the counting view alone"); press(2)
-- CLEAR
page.dpos = 9; press(3); eq(S.state.ctl.a1.type, "none", "CLEAR clears an arc encoder"); eq(S.state.ctl.a1.gain, 8, "and its gain")
press(2)
-- device list for an arc encoder is the same list
page.pos = 10; press(3); page.dpos = 3; check(#page.device_choices() >= 2, "the device list is the same for an arc encoder"); press(2)
-- ARC KEYS
fresh()
page.pos = 16; page.redraw(); check(page.rows()[16] == "ARC KEYS", "row 16 is ARC KEYS"); check(drawn("ON"), "ON by default")
turn(3, -1); eq(S.state.arc_keys, false, "E3 down turns it off"); check(drawn("OFF"), "shown"); turn(3, 1); eq(S.state.arc_keys, true, "E3 up turns it on")
press(3); eq(S.state.arc_keys, false, "K3 toggles"); press(3)
-- a typed CC that another control uses: the question
fresh()
S.set("e2", "num", 71)
page.pos = 9; press(3); page.dpos = 2; press(3); entry.cb("71")
eq(page.mode, "confirm", "a typed CC another control uses asks"); check(drawn("CC 71") and drawn("E2"), "the question names the CC and the control"); check(drawn("K3 yes"), "K3 yes, K2 no")
press(2); eq(S.state.ctl.a1.type, "none", "no: nothing is assigned"); eq(S.state.ctl.e2.num, 71, "and E2 keeps it")
page.mode = "detail"; page.ctl = "a1"; page.dpos = 2; press(3); entry.cb("71"); press(3)
eq(S.state.ctl.a1.num, 71, "yes: A1 has it"); eq(S.state.ctl.e2.type, "none", "yes: E2 is cleared"); eq(page.mode, "detail", "back in the view")
page.mode = "rows"
-- the overlap mark and its help line
fresh()
S.set("e2", "num", 72); S.set("a1", "num", 72)
page.pos = 4; page.redraw(); check(drawn("!"), "two controls on one CC: the row is marked !"); check(drawn("ALSO A1"), "and the help line says which")
S.set("a1", "num", 73); page.redraw(); check(not drawn("!"), "no mark when they differ")
-- the learn question on the page
fresh()
S.set("e2", "num", 71)
page.pos = 2; press(3); mm.pick("a1"); _norns.midi.event(2, {0xB0, 71, 65})
eq(mm.learn.state, "ask", "the learn asks"); check(drawn("CC 71 IS E2"), "the page shows the question"); check(drawn("MOVE IT TO A1"), "with both controls"); check(drawn("K3 YES"), "and the keys"); check(drawn("K2 NO"), "and no")
press(2); eq(mm.learn.state, "idle", "K2 answers no"); eq(S.state.ctl.e2.num, 71, "E2 keeps it"); eq(#set_pages, 0, "and the page is still there")
page.pos = 2; press(3); mm.pick("a1"); _norns.midi.event(2, {0xB0, 71, 65}); press(3)
eq(S.state.ctl.a1.num, 71, "K3 answers yes"); eq(S.state.ctl.e2.type, "none", "E2 is cleared"); eq(mm.learn.state, "confirm", "the learn goes on"); mm.cancel()
turn(2, 1); turn(3, 1)
-- WATCH
fresh()
page.pos = 14; page.redraw(); check(page.rows()[14] == "WATCH", "row 14 is WATCH")
press(3); eq(page.mode, "watch", "K3 opens the WATCH view"); check(drawn("WATCH"), "the title"); check(drawn("ONE CLICK EACH WAY"), "it asks for one click each way")
for _, v in ipairs({65, 63, 65, 63, 65, 65}) do _norns.midi.event(2, {0xB0, 76, v}) end
check(drawn("MIO") and drawn("CH 1") and drawn("CC 76"), "the device, the channel and the CC"); check(drawn("65") and drawn("63"), "the last values"); check(drawn("REL OFS"), "the verdict"); check(drawn("65 UP"), "and which is up")
same_as_redraw("in WATCH")
turn(2, 1); turn(3, 1); eq(page.mode, "watch", "the encoders leave WATCH alone"); press(3); eq(page.mode, "watch", "so does K3")
S.set("e1", "num", 76); S.set("e1", "mode", "rel2c"); reset_sent = #sent
_norns.midi.event(2, {0xB0, 76, 1}); eq(#sent, reset_sent, "a mapped CC does nothing while WATCH is open")
press(2); eq(page.mode, "rows", "K2 leaves WATCH"); eq(mm.watching, false, "and stops watching"); eq(#set_pages, 0, "without leaving the page")
-- leaving the page while watching or calibrating stops both
page.pos = 14; press(3); page.deinit(); eq(mm.watching, false, "leaving the page stops WATCH"); page.init()
S.set("a1", "num", 76); page.pos = 9; press(3); page.dpos = 8; press(3); page.deinit(); eq(mm.calib_target(), nil, "leaving the page stops ONE TURN"); page.init()

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

-- ================================================================ MIDI actions (docs/port/midi-actions-plan.md)
local fired = {}
_norns.window_action = function(name) fired[#fired + 1] = name end
local menu_pushed = {}
_norns.midi_actions_menu = function(on) menu_pushed[#menu_pushed + 1] = on end
mm.install()
local function afresh() fresh(); S.clear_all_actions(); S.set_actions_on(true); fired = {}; menu_pushed = {}; page.redraw() end

afresh()
local ar = page.rows()
eq(ar[13], "ACTIONS", "row 13 is ACTIONS"); eq(ar[17], "MIDI ACTIONS", "row 17 is the master switch"); eq(ar[18], "SAVE AS", "SAVE AS follows")
page.pos = 13; page.redraw(); check(drawn("ACTIONS") and drawn("0 OF 14"), "the ACTIONS row says none is set")
S.assign_action("mix", "note", 36); page.redraw(); check(drawn("1 OF 14"), "and counts the ones set")
page.pos = 17; page.redraw(); check(drawn("MIDI ACTIONS") and drawn("ON"), "the master row shows ON")
-- the master row: K3 toggles, E3 right is ON, left is OFF, release and delta 0 do nothing
press(3); eq(S.state.actions_on, false, "K3 on the master row turns it off"); check(drawn("OFF"), "and it shows OFF"); eq(menu_pushed[#menu_pushed], false, "the window menu is told")
local n0 = #menu_pushed; page.key(3, 0); eq(S.state.actions_on, false, "a key release never acts"); turn(3, 0); eq(S.state.actions_on, false, "delta 0 never acts")
turn(3, 1); eq(S.state.actions_on, true, "E3 right: ON"); turn(3, -1); eq(S.state.actions_on, false, "E3 left: OFF"); turn(3, -1); eq(S.state.actions_on, false, "left again stays OFF")
same_as_redraw("master row")
-- a change from the window menu or the shortcut shows on the row at once
_norns.midi_actions_changed(true); page.redraw(); check(drawn("ON"), "the shortcut / menu change shows on the row"); eq(S.state.actions_on, true, "same state")
-- the page fires actions while it is open
fired = {}; _norns.midi.event(2, {0x90, 36, 100}); eq(table.concat(fired, ","), "mix", "an action fires while the page is open")
-- the list
page.pos = 13; press(3); eq(page.mode, "actions", "K3 on ACTIONS opens the list"); check(drawn("ACTIONS") and drawn("ASSIGN ALL"), "the list starts with ASSIGN ALL")
local al = page.arows(); eq(#al, 16, "ASSIGN ALL, 14 actions, CLEAR ALL"); eq(al[1], "ASSIGN ALL", "first"); eq(al[2], "MIX", "MIX"); eq(al[15], "SCREENSHOT", "SCREENSHOT"); eq(al[16], "CLEAR ALL", "last")
turn(2, 1); check(drawn("MIX") and drawn("NOTE 36"), "MIX shows its note"); same_as_redraw("action list")
turn(2, 99); eq(page.apos, 16, "E2 stops at the bottom"); turn(2, -99); eq(page.apos, 1, "and the top")
turn(3, 1); eq(page.mode, "actions", "E3 right on ASSIGN ALL changes nothing"); turn(3, -1); eq(page.mode, "actions", "nor E3 left")
press(2); eq(page.mode, "rows", "K2 goes back to the rows"); eq(page.rows()[page.pos], "ACTIONS", "on the ACTIONS row")
-- the view of one action
page.pos = 13; press(3); turn(2, 1); eq(page.apos, 2, "MIX")
press(3); eq(mm.learn.state, "listen", "K3 on an action row learns it"); eq(mm.learn.target, "mix", "MIX"); eq(page.mode, "actions", "in the list"); check(drawn("LEARN MIX") and drawn("PRESS A BUTTON"), "the banner and the row say so"); mm.cancel()
S.clear_action("mix"); turn(3, -1); eq(page.mode, "actions", "E3 left on an empty action: nothing"); S.assign_action("mix", "note", 36)
turn(3, -1); eq(S.state.actions.mix.type, "none", "E3 left on an action clears it"); check(drawn("MIX CLEARED"), "and says so"); S.assign_action("mix", "note", 36)
turn(3, 1); eq(page.mode, "aview", "E3 right opens the view of MIX"); check(drawn("MIX"), "titled with the action")
eq(table.concat(page.adrows(), ","), "LEARN,KIND,NUMBER,DEVICE,CHANNEL,CLEAR", "a note action's rows")
page.dpos = 2; page.redraw(); check(drawn("KIND") and drawn("NOTE"), "KIND shows NOTE")
turn(2, 0); turn(3, 1); eq(S.state.actions.mix.type, "ccbutton", "E3 on KIND: CC BUTTON"); eq(table.concat(page.adrows(), ","), "LEARN,KIND,NUMBER,DEVICE,CHANNEL,THRESHOLD,CLEAR", "a CC button has a threshold")
turn(3, 1); eq(S.state.actions.mix.type, "step", "STEP"); page.redraw(); check(drawn("ENCODER STEP"), "KIND shows ENCODER STEP"); eq(table.concat(page.adrows(), ","), "LEARN,KIND,NUMBER,DEVICE,CHANNEL,FORMAT,DIRECTION,CLEAR", "an encoder step has a format and a direction")
turn(3, 9); eq(S.state.actions.mix.type, "step", "stops at the last type"); turn(3, -1); eq(S.state.actions.mix.type, "ccbutton", "and back"); turn(3, -1); eq(S.state.actions.mix.type, "note", "NOTE")
page.dpos = 3; turn(3, 1); eq(S.state.actions.mix.num, 37, "E3 on NUMBER steps it"); press(3); check(entry ~= nil, "K3 on NUMBER opens the text entry"); entry.cb("40"); eq(S.state.actions.mix.num, 40, "a typed 40 is set")
press(3); entry.cb("300"); eq(S.state.actions.mix.num, 40, "300 changes nothing"); check(drawn("0 TO 127"), "and says why")
S.set_action("mix", "type", "step"); page.dpos = 6; page.redraw(); check(drawn("FORMAT") and drawn("REL OFS"), "FORMAT shows the format")
turn(3, -1); eq(S.state.actions.mix.mode, "relsm", "E3 steps the format"); turn(3, -9); eq(S.state.actions.mix.mode, "rel2c", "and stops at REL 2S (no abs)")
page.dpos = 7; page.redraw(); check(drawn("DIRECTION") and drawn("UP"), "DIRECTION shows UP"); turn(3, 1); eq(S.state.actions.mix.dir, "down", "E3 right: DOWN"); turn(3, -1); eq(S.state.actions.mix.dir, "up", "E3 left: UP")
S.set_action("mix", "type", "ccbutton"); page.dpos = 6; turn(3, -99); eq(S.state.actions.mix.threshold, 0, "THRESHOLD 0 at least"); turn(3, 999); eq(S.state.actions.mix.threshold, 126, "126 at most")
page.dpos = 1; press(3); eq(mm.learn.state, "listen", "LEARN in the view listens"); eq(mm.learn.target, "mix", "for this action"); check(drawn("LEARN MIX"), "the banner names it"); check(drawn("PRESS A BUTTON"), "and says what to do"); same_as_redraw("action learn")
_norns.midi.event(2, {0x90, 44, 100}); eq(S.state.actions.mix.num, 44, "the note is taken"); eq(S.state.actions.mix.type, "note", "as a note"); check(drawn("MIX = NOTE 44"), "the page says what was set"); eq(page.mode, "aview", "and stays in the view")
page.dpos = 6; page.redraw(); eq(page.adrows()[6], "CLEAR", "CLEAR is last for a note"); press(3); eq(S.state.actions.mix.type, "none", "CLEAR clears the action"); eq(page.mode, "aview", "and stays in the view")
press(2); eq(page.mode, "actions", "K2 goes back to the list"); press(2); eq(page.mode, "rows", "and to the rows")
-- a view for an empty action is whole
page.pos = 13; press(3); turn(2, 5); turn(3, 1); eq(page.mode, "aview", "the view of an empty action opens"); check(drawn("-----") or drawn("NONE"), "it shows it is empty"); turn(2, 1); turn(3, 1); press(2); press(2)
-- ASSIGN ALL
afresh(); page.pos = 13; press(3); press(3)
eq(mm.walk_index(), 1, "K3 on ASSIGN ALL starts the walk"); check(drawn("ASSIGN ALL"), "the page says so"); check(drawn("1/14"), "with the count"); check(drawn("MIX"), "and the action asked for"); check(drawn("SKIP"), "and says how to skip"); same_as_redraw("walk")
_norns.midi.event(2, {0x90, 41, 100}); eq(S.state.actions.mix.num, 41, "a note sets the action asked for"); eq(mm.walk_index(), 2, "and the walk goes on"); check(drawn("2/14"), "the count follows")
turn(2, 1); turn(3, 1); eq(mm.walk_index(), 2, "the encoders leave the walk alone")
press(3); eq(mm.walk_index(), 3, "K3 skips"); eq(S.state.actions.tape.type, "none", "the skipped one stays empty")
page.key(3, 0); eq(mm.walk_index(), 3, "a release never skips")
press(2); eq(mm.walk_index(), nil, "K2 stops the walk"); eq(S.state.actions.mix.num, 41, "and keeps what was set"); eq(page.mode, "actions", "back in the list"); check(drawn("STOPPED AT 3 OF 14"), "and says where it stopped")
-- CLEAR ALL asks once
S.assign_action("tape", "note", 42); page.apos = 16; page.redraw(); press(3); eq(page.mode, "confirm", "CLEAR ALL asks"); check(drawn("CLEAR ALL"), "naming it"); press(2); eq(S.state.actions.mix.num, 41, "no keeps everything"); eq(page.mode, "actions", "and goes back to the list")
page.apos = 16; press(3); press(3); eq(S.count_actions(), 0, "yes clears every action"); eq(page.mode, "actions", "and goes back to the list")
-- an error in a handler is visible
local real = mm.set_actions
mm.set_actions = function() error("boom") end
page.mode = "rows"; page.pos = 17; press(3); check(drawn("ERROR"), "an error in a handler shows on the screen"); eq(page.mode, "rows", "and the page is whole")
mm.set_actions = real
-- the page joins the menu back
page.deinit(); eq(mm.walk_index(), nil, "leaving ends a walk"); page.init()

if fails == 0 then real_print("midimap page: all passed") end
os.execute("rm -rf '" .. tmp .. "'")
os.exit(fails == 0 and 0 or 1)
