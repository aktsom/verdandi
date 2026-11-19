-- MIDI MAP learn when every metro is taken (M26): norns has a fixed pool of metros, and a script (cheat codes 2) can use them all. metro.init then returns nil, and the old learn timer
-- (a metro) raised "attempt to index a nil value (upvalue 'timer')" in the page's key handler. The learn now ticks from a clock coroutine and needs no metro.
--   NORNS_PLATFORM=linux lua5.3 linux/tests/midimap_metro_test.lua
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

tab = require 'tabutil'
util = {scandir = function() return {} end, clamp = function(x, lo, hi) return math.max(lo, math.min(hi, x)) end, time = function() return 0 end}
package.loaded.util = util
local T = 100
_norns = {midi = {}, show_control = function() end, key = function() end, enc = function() end, toast = function() end,
  midimap_arm = function() end, midimap_show = function() end, arc_drag_config = function() end, arc_turn = function() return true end,
  metro_start = function() end, metro_stop = function() end, metro_set_time = function() end, metro_free = function() end}
_menu = {rebuild_params = function() end, page = "MIDIMAP", mode = true, redraw = function() end}
params = {lookup = {}, lookup_param = function() return {name = "x"} end}
pmap = require 'core/pmap'
norns = {pmap = pmap, state = {shortname = "t"}, none = function() end, menu_midi_event = function() end}

-- the real metro pool, every metro taken by a "script"
metro = require 'core/metro'
for i = 1, metro.num_metros do metro.available[i] = false; metro.assigned[i] = true end
check(metro.init(function() end, 1, -1) == nil, "setup: metro.init gives nothing (the pool is used up)")

-- a clock: coroutines that sleep, advanced by the test
local co, wake, now = {}, {}, 0
clock = {
  run = function(f) local c = coroutine.create(f); co[#co + 1] = c; wake[c] = 0; local ok, err = coroutine.resume(c); if ok and coroutine.status(c) == "suspended" then wake[c] = now + (clock._req or 0) end; return c end,
  sleep = function(s) clock._req = s; coroutine.yield() end,
  cleanup = function() co = {}; wake = {} end}
local function advance(sec)
  local target = now + sec
  while true do
    local nextt, who = nil, nil
    for _, c in ipairs(co) do
      if coroutine.status(c) == "suspended" and (nextt == nil or wake[c] < nextt) then nextt, who = wake[c], c end
    end
    if who == nil or nextt > target then break end
    now = nextt; T = 100 + now
    clock._req = nil
    local ok, err = coroutine.resume(who)
    if not ok then real_print("coroutine error: " .. tostring(err)) fails = fails + 1 end
    wake[who] = now + (clock._req or 0)
  end
  now = target; T = 100 + now
end

midi = require 'core/midi'
local V = require 'core/midimap_value'
local S = require 'core/midimap_settings'
S.log = function() end
local mm = require 'core/midimap'
norns.midimap = mm
mm.clock = function() return T end
mm.load()
S.load(); S.select_preset("NONE"); mm.load()
local redraws = 0
mm.on_change = function() redraws = redraws + 1 end
_norns.midi.add(2, "mio", "p2")

-- 1. pick, nothing happens: the time-out ends it, the page is told every tick
local ok, err = pcall(mm.start_pick)
check(ok, "start_pick with no free metro raises no error: " .. tostring(err))
eq(mm.learn.state, "pick", "pick state")
local r0 = redraws
advance(2)
check(redraws > r0 + 4, "the countdown redraws the page while waiting (" .. (redraws - r0) .. ")")
advance(mm.TIMEOUT)
eq(mm.learn.state, "idle", "no click: the learn times out after TIMEOUT")

-- 2. listen, nothing played: time-out
ok, err = pcall(mm.start_listen, "e1")
check(ok, "start_listen with no free metro raises no error: " .. tostring(err))
eq(mm.learn.state, "listen", "listen state")
advance(mm.TIMEOUT + 1)
eq(mm.learn.state, "idle", "nothing played: the listen times out")

-- 3. an action learn (ASSIGN ALL step) times out too
ok, err = pcall(mm.start_listen_action, S.ACTION_IDS[1])
check(ok, "start_listen_action with no free metro raises no error: " .. tostring(err))
advance(mm.TIMEOUT + 1)
eq(mm.learn.state, "idle", "action learn times out")

-- 4. a full learn: an encoder CC arrives, a few more, then silence: the suggestion is finished by the silence (fewer than CONFIRM_MSGS messages)
mm.start_listen("e2")
_norns.midi.event(2, {0xB0, 40, 1}); _norns.midi.event(2, {0xB0, 40, 1})
eq(mm.learn.state, "confirm", "a CC was heard: confirm state")
advance(mm.CONFIRM_SILENCE + 1)
eq(mm.learn.state, "idle", "silence finishes the confirm")
eq(S.state.ctl.e2.num, 40, "the control was learned (CC 40)")

-- 5. restart of the ticker after a script change cleared every clock coroutine
mm.start_pick()
clock.cleanup()
advance(2) -- a script change: nothing ticks any more
mm.start_pick()
advance(mm.TIMEOUT + 1)
eq(mm.learn.state, "idle", "after the clocks were cleared the learn still times out")

for _, l in ipairs(printed) do if l:find("raised an error", 1, true) then check(false, "logged: " .. l) end end
if fails == 0 then real_print("midimap_metro_test: all checks passed") else real_print("midimap_metro_test: " .. fails .. " FAILED") os.exit(1) end
