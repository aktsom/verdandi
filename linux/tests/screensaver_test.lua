-- M34 (docs/port/phase-m34.md): the SCREENSAVER setting (SYSTEM > SCREEN, Windows and Linux; OFF by default; macOS and the norns device keep the always-on 15 minute screensaver). run from the repo root:
--   lua5.3 linux/tests/screensaver_test.lua
-- the real lua/core/screen.lua, lua/core/metro.lua, lua/core/ui_settings.lua and lua/core/menu/ui.lua with a fake timer: _norns.metro_start / metro_stop record which metro runs, and "the time passes" is a call
-- of the C callback _norns.metro(36, 1) for a metro that was started (what the C timer does when it fires)
package.path = "lua/?.lua;lua/core/?.lua;lua/lib/?.lua;" .. package.path
local tmp = os.tmpname()
os.remove(tmp)
os.execute("mkdir -p " .. tmp)
local real_getenv, real_print = os.getenv, print
print = function() end
local fails, checks = 0, 0
local function check(ok, what) checks = checks + 1; if not ok then fails = fails + 1; real_print("FAIL " .. what) end end
local function eq(a, b, what) check(a == b, what .. ": got " .. tostring(a) .. ", wanted " .. tostring(b)) end
local function slurp(p) local h = io.open(p); if not h then return nil end local c = h:read("a"); h:close(); return c end
local function put(p, text) local h = io.open(p, "w"); h:write(text); h:close() end

local started, cleared, updated = {}, 0, 0
local function new_world(platform)
  started, cleared, updated = {}, 0, 0
  os.getenv = function(k) if k == "NORNS_PLATFORM" then return platform end return real_getenv(k) end
  _path = {display_settings = tmp .. "/system.display.none"}
  util = {clamp = function(x, a, b) return math.max(a, math.min(b, x)) end}
  _norns = setmetatable({
    metro_start = function(id, time, count) started[id] = {time = time, count = count} end,
    metro_stop = function(id) started[id] = nil end,
    metro_set_time = function() end,
    screen_clear = function() cleared = cleared + 1 end,
    screen_update = function() updated = updated + 1 end,
    ui_look = function() end,
    key = function() end, enc = function() end, toast = function() end,
  }, {__index = function() return function() return 0 end end})
  for _, name in ipairs({"core/metro", "core/screen", "core/ui_settings", "core/menu/ui"}) do package.loaded[name] = nil end
  local screen_mod = require 'core/screen'
  screen = screen_mod -- menu.lua does the same: the global `screen` is core/screen.lua
  local ui = require 'core/ui_settings'
  ui.PATH = tmp .. "/ui.conf"; ui.DIR = tmp .. "/screen-presets/"; ui.log = function() end
  os.execute("mkdir -p '" .. ui.DIR .. "'")
  os.remove(ui.PATH)
  return screen_mod, ui
end
-- the C timer fires: only a metro that was started (and a count of 1 ends it)
local function fire(id)
  local m = started[id]
  if not m then return false end
  if m.count == 1 then started[id] = nil end
  _norns.metro(id, 1)
  return true
end
local function dark(S) return S.update ~= S.update_default end

-- ---- Windows and Linux: OFF by default
for _, platform in ipairs({"linux", "windows"}) do
  local S, ui = new_world(platform)
  local tag = platform .. ": "
  check(ui.state.screensaver == false, tag .. "with nothing saved the setting is OFF")
  check(S.auto_sleep ~= nil and S.auto_sleep() == false, tag .. "and the automatic screensaver is off in screen.lua before anything is loaded")
  S.ping()
  check(started[36] == nil, tag .. "OFF: a key press starts no timer")
  check(not fire(36), tag .. "OFF: there is no timer to fire")
  check(not dark(S), tag .. "OFF: the screen is never darkened by the timer")
  -- a timer event that is already on its way when the setting is OFF does nothing
  require('core/metro')[36].event()
  check(not dark(S) and cleared == 0, tag .. "OFF: a late timer event leaves Screen.update the real one and clears nothing")
  -- Screen.sleep() on purpose works with OFF; ping wakes it
  S.sleep()
  check(dark(S) and cleared == 1, tag .. "OFF: Screen.sleep() darkens the screen on purpose")
  S.ping()
  check(not dark(S), tag .. "OFF: Screen.ping() wakes it, as today")
  check(started[36] == nil, tag .. "OFF: and still starts no timer")

  -- OFF to ON starts the 15 minute timer at once, ON darkens after the time
  if not ui.set_screensaver then real_print("FAIL " .. tag .. "there is no ui.set_screensaver (old code)"); fails = fails + 1; break end
  ui.set_screensaver(true)
  check(S.auto_sleep() == true, tag .. "ON reaches screen.lua")
  check(started[36] ~= nil and started[36].time == 900 and started[36].count == 1, tag .. "OFF to ON starts the 15 minute timer at once")
  check(fire(36) and dark(S), tag .. "ON: the timer darkens the screen after the time")
  S.ping()
  check(not dark(S) and started[36] ~= nil, tag .. "ON: a key wakes it and starts the timer again")
  -- ON to OFF while the screen is dark: it wakes at once, no timer, never left dark
  fire(36)
  check(dark(S), tag .. "(the screen is dark again)")
  ui.set_screensaver(false)
  check(not dark(S), tag .. "ON to OFF while dark: the screen wakes at once and is not left dark")
  check(started[36] == nil, tag .. "ON to OFF stops the timer")
  check(not fire(36), tag .. "no timer fires afterwards"); check(not dark(S), tag .. "and the screen stays awake")
  -- ON to OFF while awake: the timer that runs is stopped
  ui.set_screensaver(true); check(started[36] ~= nil, tag .. "ON again: timer running")
  ui.set_screensaver(false); check(started[36] == nil and not dark(S), tag .. "ON to OFF while awake stops the timer")
  -- the same value again changes nothing (brightness steps call apply too)
  local before = started[36]
  ui.set_screensaver(false); check(started[36] == nil, tag .. "OFF again: still no timer")
  ui.set_screensaver(true); local t1 = started[36]; ui.step_brightness(-1); check(started[36] == t1, tag .. "a brightness step does not restart the timer")

  -- saved and read back at the next start
  ui.set_screensaver(true)
  local text = slurp(ui.PATH)
  check(text:find("screensaver=1\n", 1, true) ~= nil, tag .. "ON is saved in ui.conf: " .. tostring(text))
  S, ui = new_world(platform)
  put(tmp .. "/ui.conf", "brightness=0.7\nscreensaver=1\n")
  ui.PATH = tmp .. "/ui.conf"
  ui.load_and_apply()
  check(ui.state.screensaver == true and S.auto_sleep() == true, tag .. "a saved ON is read back at the next start")
  check(started[36] ~= nil, tag .. "and the timer runs at start")
  S, ui = new_world(platform)
  put(tmp .. "/ui.conf", "brightness=0.7\nscreensaver=0\n"); ui.PATH = tmp .. "/ui.conf"
  ui.load_and_apply()
  check(ui.state.screensaver == false and S.auto_sleep() == false, tag .. "a saved OFF is read back")
  S, ui = new_world(platform)
  put(tmp .. "/ui.conf", "brightness=0.7\npreset=YELLOW\n"); ui.PATH = tmp .. "/ui.conf"
  ui.load_and_apply()
  check(ui.state.screensaver == false and S.auto_sleep() == false, tag .. "an existing ui.conf without the key is OFF")
  S, ui = new_world(platform)
  ui.load_and_apply(); S.ping()
  check(S.auto_sleep() == false and started[36] == nil, tag .. "no ui.conf at all: OFF, no timer")
  S, ui = new_world(platform)
  put(tmp .. "/ui.conf", "screensaver=maybe\n"); ui.PATH = tmp .. "/ui.conf"
  ui.load_and_apply()
  check(ui.state.screensaver == false, tag .. "a damaged value falls back to OFF")
end

-- ---- macOS and the norns device: always on, the setting is ignored, the file is not changed
for _, platform in ipairs({"macos", false}) do
  local S, ui = new_world(platform or nil)
  local tag = (platform or "device") .. ": "
  check(S.auto_sleep() == true, tag .. "the automatic screensaver is always on")
  S.ping()
  check(started[36] ~= nil and started[36].time == 900, tag .. "a key press starts the 15 minute timer, as before")
  check(fire(36) and dark(S), tag .. "the timer darkens the screen after 15 minutes, as before")
  S.ping(); check(not dark(S), tag .. "a key wakes it")
  S.set_auto_sleep(false)
  check(S.auto_sleep() == true, tag .. "screen.lua ignores a request to switch it off")
  ui.set_screensaver(false)
  S.ping(); check(started[36] ~= nil and S.auto_sleep() == true, tag .. "and so does the settings code: the timer still runs")
  fire(36); check(dark(S), tag .. "and still darkens")
  local text = slurp(ui.PATH) or ""
  check(text:find("screensaver", 1, true) == nil, tag .. "ui.conf is not written with the new key: " .. text:gsub("\n", " "))
  S.sleep(); check(dark(S), tag .. "Screen.sleep() still works")
end

-- ---- the page
local function page_for(platform)
  local S, ui = new_world(platform)
  norns = {none = function() end, menu = {status = function() return true end, get_key = function() return "k" end, get_enc = function() return "e" end}}
  package.loaded.textentry = {enter = function() end}
  package.loaded['core/keyboard'] = {ctrl = function() return false end, shift = function() return false end}
  package.loaded['core/clipboard'] = {copy = function() return true end, paste_colour = function() end}
  local page = dofile("lua/core/menu/ui.lua")
  _menu = {set_page = function() end, redraw = function() end, set_mode = function() end, keycode = function() end, keychar = function() end}
  page.init()
  return page, S, ui
end
local function row_of(page, name) for i, r in ipairs(page.rows()) do if r == name then return i end end return nil end
for _, platform in ipairs({"linux", "windows"}) do
  local page, S, ui = page_for(platform)
  local tag = platform .. " page: "
  local rows = table.concat(page.rows(), ",")
  eq(rows, "PRESET,COLOUR,BRIGHTNESS,CONTRAST,SCREENSAVER,SAVE", tag .. "the SCREENSAVER row is after CONTRAST")
  page.pos = row_of(page, "SCREENSAVER")
  local shown = {}
  screen = setmetatable({}, {__index = function() return function() return 0 end end})
  screen.clear = function() shown = {} end
  screen.text = function(s) shown[#shown + 1] = tostring(s) end
  screen.text_right = function(s) shown[#shown + 1] = tostring(s) end
  screen.text_extents = function(s) return #tostring(s) * 5 end
  screen.update = function() end
  screen.set_auto_sleep = S.set_auto_sleep -- (the drawing stand-in stays the global `screen`: the real timer code is reached through it, as on a running norns)
  page.redraw()
  local has = function(s) for _, t in ipairs(shown) do if t:find(s, 1, true) then return true end end return false end
  check(has("SCREENSAVER") and has("OFF"), tag .. "the row shows SCREENSAVER OFF by default")
  page.enc(3, 0); eq(ui.state.screensaver, false, tag .. "a release (delta 0) changes nothing")
  page.enc(3, -1); eq(ui.state.screensaver, false, tag .. "E3 left on OFF stays OFF")
  page.enc(3, 1); page.redraw()
  eq(ui.state.screensaver, true, tag .. "E3 right: ON"); check(has("ON") and not has("OFF"), tag .. "the row shows ON")
  check(slurp(ui.PATH):find("screensaver=1", 1, true) ~= nil, tag .. "saved at once")
  check(started[36] ~= nil, tag .. "and the timer starts at once (through the page)")
  page.enc(3, -1); page.redraw()
  eq(ui.state.screensaver, false, tag .. "E3 left: OFF"); check(slurp(ui.PATH):find("screensaver=0", 1, true) ~= nil, tag .. "saved at once")
  check(started[36] == nil, tag .. "and the timer stops")
  -- the row at the end of a scroll: every row of the page draws without an error
  for i = 1, #page.rows() do page.pos = i; page.redraw() end
  check(#page.rows() == 6, tag .. "six rows (seven with DELETE: the page scrolls like before)")
end
do
  local page = page_for("macos")
  eq(table.concat(page.rows(), ","), "PRESET,COLOUR,BRIGHTNESS,CONTRAST,SAVE", "macos page: no SCREENSAVER row")
  page = page_for(nil)
  eq(table.concat(page.rows(), ","), "PRESET,COLOUR,BRIGHTNESS,CONTRAST,SAVE", "device page: no SCREENSAVER row")
end

os.getenv = real_getenv
os.execute("rm -rf '" .. tmp .. "'")
if fails > 0 then real_print("screensaver_test: " .. fails .. " of " .. checks .. " checks FAILED") os.exit(1) end
real_print("screensaver_test: all " .. checks .. " checks passed")
