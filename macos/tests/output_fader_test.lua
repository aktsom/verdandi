-- scenarios for the OUT fader and MUTE on the macOS window (lua/core/menu.lua) and the
-- mouse on the MIX page (lua/core/menu/mix.lua). run from the repo root:
--   <lua 5.3> macos/tests/output_fader_test.lua
-- params, the window and the menu are faked
local fails = 0
local function check(cond, what)
  if not cond then
    fails = fails + 1
    print("FAIL " .. what)
  end
end

util = {clamp = function(x, lo, hi) return math.max(lo, math.min(hi, x)) end}
norns = {state = {mix = {output = 0}}, encoders = {set_accel = function() end, set_sens = function() end}}
local hooks = {}
hook = {system_post_startup = {register = function(_, name, f) hooks[name] = f end}}

-- params: dB controls, raw 0-1 = -60..+6 dB, raw 0 = -inf; the action of output_level as in
-- lua/core/audio.lua
local function to_db(raw) return raw <= 0 and -math.huge or -60 + raw * 66 end
local function to_raw(db) return db == -math.huge and 0 or util.clamp((db + 60) / 66, 0, 1) end
local values, set_log = {}, {}
params = {lookup = {}}
for _, id in ipairs({"output_level", "input_level", "monitor_level", "engine_level", "softcut_level", "tape_level"}) do
  params.lookup[id] = true
  values[id] = 0
end
local function changed(id)
  table.insert(set_log, id)
  if id == "output_level" then
    norns.state.mix.output = values[id]
    _menu.output_changed(values[id])
  end
end
function params:get(id) return values[id] end
function params:set(id, v) values[id] = v; changed(id) end
function params:get_raw(id) return to_raw(values[id]) end
function params:set_raw(id, r) values[id] = to_db(r); changed(id) end
function params:delta(id, d) values[id] = to_db(util.clamp(to_raw(values[id]) + d / 100, 0, 1)); changed(id) end

local shown = {}
_norns = {show_control = function(kind, n, v) if kind == 5 then shown = {n = n, muted = v} end end}
_menu = {mode = false, redraw = function() end}

-- the block from menu.lua, with its m (the menu pages) given
local src = io.open("lua/core/menu.lua"):read("a")
local block = src:match("(%-%- the OUT fader and MUTE right of E3.-_norns%.screen_mouse = function.-\nend)\n")
assert(block, "fader block not found")
local m = {}
load("local m = ...\n" .. block)(m)

-- startup: the fader shows the level
values.output_level = 0
hooks["menu-out"]()
check(shown.n == math.floor(to_raw(0) * 1000 + 0.5) and shown.muted == 0, "startup shows the level")

-- the fader sets the level
_norns.output_fader("0.5")
check(math.abs(params:get_raw("output_level") - 0.5) < 1e-9, "fader 0.5 sets the level")
check(shown.n == 500 and shown.muted == 0, "and shows it")

-- MUTE: silence, the level kept, also as the one saved for the next start
local before = values.output_level
_norns.output_mute()
check(values.output_level == -math.huge and shown.muted == 1 and shown.n == 0, "mute: silent, lit")
check(norns.state.mix.output == before, "the saved level is the one before muting")
_norns.output_mute()
check(values.output_level == before and shown.muted == 0, "unmute: the level is back")

-- moving the fader while muted unmutes
_norns.output_mute()
_norns.output_fader("0.25")
check(math.abs(params:get_raw("output_level") - 0.25) < 1e-9 and shown.muted == 0, "fader while muted: unmuted at the fader")
_norns.output_mute()
_norns.output_mute()
check(math.abs(params:get_raw("output_level") - 0.25) < 1e-9, "mute twice after that: as before")

-- turned up elsewhere (E2 on the MIX page) while muted: unmuted
_norns.output_mute()
params:delta("output_level", 10)
check(values.output_level > -math.huge and shown.muted == 0, "turned up while muted: no longer muted")
_norns.output_mute()
check(values.output_level == -math.huge, "mute after that mutes")
_norns.output_mute()

-- a double click on the fader: 0 dB, also out of mute
_norns.output_fader("0.9")
_norns.output_reset()
check(values.output_level == 0 and shown.muted == 0, "double click: 0 dB")
_norns.output_mute()
_norns.output_reset()
check(values.output_level == 0 and shown.muted == 0, "double click while muted: 0 dB, unmuted")
_norns.output_mute()
check(values.output_level == -math.huge, "mute after that mutes")
_norns.output_mute()
check(values.output_level == 0, "and unmutes to 0 dB")

-- the wheel over the fader
local r = params:get_raw("output_level")
_norns.output_step("3")
check(math.abs(params:get_raw("output_level") - (r + 0.03)) < 1e-9, "wheel steps the level")

-- the mouse on the screen goes to the menu page that takes it
local got
m.MIX = {mouse = function(x, y, kind, v) got = {x, y, kind, v} end}
m.HOME = {}
_menu.mode, _menu.page = true, "MIX"
_norns.screen_mouse("12", "30", "down", "0")
check(got and got[1] == 12 and got[2] == 30 and got[3] == "down" and got[4] == 0, "MIX gets the mouse as numbers")
got = nil
_menu.page = "HOME"
_norns.screen_mouse("12", "30", "down", "0")
check(got == nil, "a page without a mouse handler gets nothing")
_menu.mode, _menu.page = false, "MIX"
_norns.screen_mouse("12", "30", "down", "0")
check(got == nil, "nothing while a script plays")

-- the MIX page: columns out in mon eng cut tp, 22 pixels each, bars 48 high from y 55.5
local mix = dofile("lua/core/menu/mix.lua")
mix.mouse(5, 31.5, "down", 0)
check(math.abs(params:get_raw("output_level") - 0.5) < 1e-9 and mix.sel == 1, "out column, half way up: 0.5, out/in selected")
mix.mouse(80, 7.5, "drag", 0)
check(math.abs(params:get_raw("output_level") - 1) < 1e-9, "dragging stays on its column, to the top: 1")
mix.mouse(80, 70, "drag", 0)
check(params:get_raw("output_level") == 0, "below the bar: 0")
mix.mouse(80, 70, "up", 0)
mix.mouse(70, 55.5 - 12, "down", 0)
check(math.abs(params:get_raw("engine_level") - 0.25) < 1e-9 and mix.sel == 2, "eng column: its level, mon/eng selected")
mix.mouse(70, 0, "up", 0)
local tape = params:get_raw("tape_level")
mix.mouse(120, 40, "wheel", 2)
check(math.abs(params:get_raw("tape_level") - (tape + 0.02)) < 1e-9 and mix.sel == 3, "wheel on tp steps it, cut/tp selected")
mix.mouse(127, 0, "drag", 0)
check(math.abs(params:get_raw("tape_level") - (tape + 0.02)) < 1e-9, "a drag without a press changes nothing")
-- a double click: its first press set the level, the double click sets 0 dB; a drag after it
-- does nothing
mix.mouse(50, 10, "down", 0)
mix.mouse(50, 10, "up", 0)
mix.mouse(50, 10, "double", 0)
check(values.monitor_level == 0 and mix.sel == 2, "double click on mon: 0 dB, mon/eng selected")
mix.mouse(50, 50, "drag", 0)
check(values.monitor_level == 0, "dragging after a double click changes nothing")
mix.mouse(50, 50, "up", 0)

print(fails == 0 and "output fader: all scenarios pass" or (fails .. " failures"))
os.exit(fails == 0)
