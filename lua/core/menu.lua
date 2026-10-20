-- menu.lua
-- norns screen-based navigation module

local tab = require 'tabutil'
local util = require 'util'
local fileselect = require 'fileselect'
local listselect = require 'listselect'
local textentry = require 'textentry'
local gamepad = require 'gamepad'
local hook = require 'core/hook'

_menu = {}

-- global functions for scripts
key = norns.none
enc = norns.none
redraw = norns.blank
cleanup = norns.none
refresh = norns.none

-- tuning
local KEY1_HOLD_TIME = 0.25

_menu.mode = false
_menu.page = "HOME"
_menu.panel = 3
_menu.panels = {"MIX", "TAPE", "HOME", "PARAMS"}
_menu.alt = false
_menu.scripterror = false
_menu.locked = false
_menu.errormsg = ""
_menu.shownav = false
_menu.showstats = false
_menu.previewfile = ""
_menu.binarystates = {triggered = {}, on = {}}

-- menu pages
local m = {}
_menu.m = m

-- METROS
local pending = false
-- metro for key hold detection
local metro = require 'core/metro'
local t = metro[31]
t.time = KEY1_HOLD_TIME
t.count = 1
t.event = function(_)
  _menu.key(1,1)
  pending = false
  if _menu.mode == true then _menu.redraw() end
end
-- metro for page status updates
_menu.timer = metro[32]
-- metro for nav vanish
local nav_vanish = metro[35]
nav_vanish.time = 1
nav_vanish.event = function()
  _menu.shownav = false
  if _menu.mode == true then _menu.redraw() end
  nav_vanish:stop()
end
-- screen.lua has metro[35] for screensaver

-- FIXME: get rid of norns.menu -- just put stuff in _menu
-- assigns key/enc/screen handlers after user script has loaded
norns.menu = {}
norns.menu.init = function() _menu.set_mode(_menu.mode) end -- used by fileselect.lua
norns.menu.status = function() return _menu.mode end
norns.menu.set = function(new_enc, new_key, new_redraw, new_refresh)
  _menu.penc = new_enc
  _menu.key = new_key
  _menu.redraw = new_redraw
  _menu.refresh = new_refresh
end
norns.menu.get_enc = function() return _menu.penc end
norns.menu.get_key = function() return _menu.key end
norns.menu.get_redraw = function() return _menu.redraw end
norns.menu.get_refresh = function() return _menu.refresh end
norns.menu.toggle = function(status) _menu.set_mode(status) end

norns.scripterror = function(msg)
  if msg == nil then msg = "" end
  print("### SCRIPT ERROR: "..msg)
  if util.string_starts(msg,"missing") then
    print("### try 'SYSTEM > RESTART'")
  elseif util.string_starts(msg,"version") then
    print("### try 'SYSTEM > UPDATE'")
    print("### or check for new disk image")
  end
  _menu.errormsg = msg
  _menu.scripterror = true
  _menu.locked = true
  _menu.set_page("HOME")
  _menu.set_mode(true)
end

norns.init_done = function(status)
  _menu.set_page("HOME")
  _menu.panel = 3
  if status == true then
    _menu.scripterror = false
    m["PARAMS"].pos = 0
    _menu.locked = false
    _menu.set_mode(false)
  end
  m["PARAMS"].reset()
end




-- input redirection

-- the next menu page for E1 / L1 R1. on a computer the encoders are endless knobs
-- without stops, so the pages go round (PARAMS -> MIX); on the device they stop at the ends
local wrap_panels = os.getenv("NORNS_PLATFORM") ~= nil
local function next_panel(delta)
  if wrap_panels then
    return (_menu.panel - 1 + delta) % #_menu.panels + 1
  end
  return util.clamp(_menu.panel+delta,1,4)
end

_menu.enc = function(n, delta)
  if n==1 and _menu.alt == false then
    --mix:delta("output",delta)
    local c = next_panel(delta)
    if c ~= _menu.panel then
      _menu.shownav = true
      _menu.panel = c
      _menu.set_page(_menu.panels[_menu.panel])
      nav_vanish:start()
    end
  else _menu.penc(n, delta) end
end


_norns.key = function(n, z)
  -- key 1 detect for short press
  if n == 1 then
    if z == 1 then
      _menu.alt = true
      pending = true
      t:start()
    elseif z == 0 and pending == true then
      _menu.alt = false
      if _menu.mode == true and _menu.locked == false then
        _menu.set_mode(false)
      else _menu.set_mode(true) end
      t:stop()
      pending = false
    elseif z == 0 then
      _menu.alt = false
      _menu.key(n,z) -- always 1,0
      if _menu.mode == true then _menu.redraw() end
    else
      _menu.key(n,z) -- always 1,1
    end
    -- key 2/3 pass
  else
    _menu.key(n,z)
  end
  screen.ping()
end

-- _menu.set mode
--- macOS window (matron/src/platform/macos/sdl_bridge.cc): the device has a button row
-- with the four pages, GRID, MAIDEN and MANUAL; the page buttons light up
local function show_page()
  if _norns.show_control then
    local p = 0
    if _menu.mode then p = tab.key(_menu.panels, _menu.page) or _menu.panel end
    _norns.show_control(3, p, 0)
  end
end

-- MIC: what norns' input hears. "mic": the Mac's own input (microphone or interface,
-- system:capture -> crone:input_1/2), "system": every other app's sound (a video in a
-- browser ...), "app": one app (Devices > Audio Input), "off": nothing. the Mac's input is
-- unplugged and plugged back in, so loud speakers cannot feed back into the microphone; the
-- apps are tapped by the window (_norns.app_input). the button goes MIC > SYS > OFF.
-- the choice is kept for the next start: ~/.mic-off unless it was "mic", ~/.norns-input for
-- "system" and "app" (with the app)
_menu.input = "mic"
_menu.mic_live = true -- the Mac's own input reaches norns
local MIC_OFF = "/home/we/.mic-off"
local INPUT_KEPT = "/home/we/.norns-input"
local mic_links = {}
local mic_checked = false
local INPUT_SHOWN = {off = 0, mic = 1, system = 2, app = 3}
local INPUT_LABEL = {off = "off", mic = "mic / interface", system = "all apps (system audio)"}

local function show_input()
  if _norns.show_control then _norns.show_control(4, INPUT_SHOWN[_menu.input] or 0, 0) end
end

-- the system:capture -> crone:input_1/2 connections, from jack_lsp -c
local function capture_links()
  local links, port = {}, nil
  for line in (util.os_capture("jack_lsp -c", true) or ""):gmatch("[^\n]+") do
    local peer = line:match("^%s+(%S+)")
    if peer == nil then
      port = line:match("^(%S+)")
    elseif port and port:match("^crone:input_[12]$") and peer:match("^system:capture_%d+$") then
      table.insert(links, {peer, port})
    end
  end
  return links
end

local function set_capture(live)
  if live then
    for _, l in ipairs(mic_links) do _norns.execute("jack_connect " .. l[1] .. " " .. l[2]) end
    mic_links = {}
  else
    for _, l in ipairs(capture_links()) do
      _norns.execute("jack_disconnect " .. l[1] .. " " .. l[2])
      table.insert(mic_links, l)
    end
  end
  _menu.mic_live = live
end

-- mode "mic", "system", "app" (bundle id and name of the app) or "off"; quiet: no note on
-- the device
function _menu.set_input(mode, bundle, name, quiet)
  if (mode == "system" or mode == "app") and not _norns.app_input then mode = "off" end
  if mode == "app" and not bundle then mode = "off" end
  set_capture(mode == "mic")
  if _norns.app_input then
    local label = not quiet and (INPUT_LABEL[mode] or name or bundle) or nil
    if mode == "system" then
      _norns.app_input("system", label)
    elseif mode == "app" then
      _norns.app_input(bundle, label)
    else
      _norns.app_input(nil, label)
    end
  end
  _menu.input = mode
  if mode == "mic" then
    os.remove(MIC_OFF)
  else
    local f = io.open(MIC_OFF, "w")
    if f then f:close() end
  end
  if mode == "system" or mode == "app" then
    local f = io.open(INPUT_KEPT, "w")
    if f then
      f:write(mode, "\n", bundle or "", "\n", name or "", "\n")
      f:close()
    end
  else
    os.remove(INPUT_KEPT)
  end
  show_input()
end

-- the Mac's own input on or off (as before there were apps to hear)
function _menu.set_mic(live)
  _menu.set_input(live and "mic" or "off")
end

-- Devices > Audio Input chose (platform/macos/mac_menu.m)
_norns.input_chosen = function(mode, bundle, name)
  _menu.set_input(mode, bundle ~= "" and bundle or nil, name ~= "" and name or nil)
end

-- the tap stopped on its own (the window said why)
_norns.input_ended = function()
  if _menu.input == "system" or _menu.input == "app" then _menu.set_input("off", nil, nil, true) end
end

-- the MIC button
local INPUT_NEXT = {mic = "system", system = "off", off = "mic", app = "off"}
function _menu.next_input()
  local mode = INPUT_NEXT[_menu.input] or "mic"
  if mode == "system" and not _norns.app_input then mode = "off" end
  _menu.set_input(mode)
end

-- when norns is up (crone has connected the input again): take it off if it was off
function _menu.check_mic()
  if mic_checked or not _norns.show_control then return end
  mic_checked = true
  local f = io.open(INPUT_KEPT)
  if f then
    local mode, bundle, name = f:read("l"), f:read("l"), f:read("l")
    f:close()
    if mode == "system" or (mode == "app" and bundle and bundle ~= "") then
      -- said on the device: the apps go quiet into norns again
      _menu.set_input(mode, bundle ~= "" and bundle or nil, name ~= "" and name or nil)
      return
    end
  end
  if util.file_exists(MIC_OFF) then _menu.set_input("off", nil, nil, true) else show_input() end
end
hook.system_post_startup:register("menu-mic", _menu.check_mic)

-- the OUT fader and MUTE right of E3 on the window: output_level, as on the MIX page.
-- MUTE keeps the level it had and gives it back; the level saved for the next start is that
-- one, not silence
local out_unmuted = nil

local function show_output()
  if _norns.show_control and params.lookup["output_level"] then
    _norns.show_control(5, math.floor(params:get_raw("output_level") * 1000 + 0.5), out_unmuted and 1 or 0)
  end
end

-- output_level changed (its action, lua/core/audio.lua)
function _menu.output_changed(db)
  if out_unmuted then
    if db == -math.huge then
      norns.state.mix.output = out_unmuted
    else
      -- turned up while muted: no longer muted
      out_unmuted = nil
    end
  end
  show_output()
end

_norns.output_fader = function(raw)
  out_unmuted = nil
  params:set_raw("output_level", tonumber(raw) or 0)
end

_norns.output_step = function(d)
  params:delta("output_level", tonumber(d) or 0)
end

_norns.output_mute = function()
  if out_unmuted then
    local db = out_unmuted
    out_unmuted = nil
    params:set("output_level", db)
  else
    out_unmuted = params:get("output_level")
    params:set("output_level", -math.huge)
  end
  show_output()
end

hook.system_post_startup:register("menu-out", show_output)

-- the mouse on the oled (x 0-127, y 0-63; kind "down", "drag", "up", "wheel" with its
-- steps), for the menu page that takes it (MIX)
_norns.screen_mouse = function(x, y, kind, value)
  local page = _menu.mode and m[_menu.page]
  if page and page.mouse then
    page.mouse(tonumber(x), tonumber(y), kind, tonumber(value) or 0)
  end
end

-- 1-4: menu page (clicking the page that is up goes back to the script), 5: the manual of
-- norns for macOS, 6: the next audio input (MIC > SYS > OFF)
_norns.window_button = function(n)
  if n >= 1 and n <= 4 then
    if _menu.mode and _menu.page == _menu.panels[n] and not _menu.locked then
      _menu.set_mode(false)
    else
      if not _menu.mode then _menu.set_mode(true) end
      _menu.goto_panel(n)
    end
  elseif n == 5 and _norns.open_url then
    local manual = os.getenv("NORNS_MANUAL")
    if manual then _norns.open_url(manual) end
  elseif n == 6 then
    _menu.next_input()
  end
end

_menu.set_mode = function(mode)
  if mode == false then -- ACTIVATE PLAY MODE
    if _menu.mode == true then _norns.screen_restore() end
    _menu.mode = false
    m[_menu.page].deinit()
    screen.clear()
    screen.update()
    redraw = norns.script.redraw
    refresh = norns.script.refresh
    _menu.key = key
    norns.encoders.callback = enc
    norns.enc.resume()
    redraw()
  elseif mode == true then -- ACTIVATE MENU MODE
    if _menu.mode == false then _norns.screen_save() end
    _menu.mode = true
    _menu.alt = false
    redraw = norns.none
    refresh = norns.none
    screen.font_face(1)
    screen.font_size(8)
    screen.line_width(1)
    norns.encoders.callback = _menu.enc
    norns.encoders.set_accel(1,false)
    norns.encoders.set_sens(1,8)
    norns.encoders.set_accel(2,false)
    norns.encoders.set_sens(2,2)
    norns.encoders.set_accel(3,true)
    norns.encoders.set_sens(3,2)
    _menu.set_page(_menu.page)
  end
  show_page()
end

-- set page
_menu.set_page = function(page)
  m[_menu.page].deinit()
  _menu.page = page
  _menu.key = m[page].key
  _menu.penc = m[page].enc
  _menu.redraw = m[page].redraw
  _menu.refresh = m[page].refresh
  _menu.keyboardcode = m[page].keycode
  _menu.keyboardchar = m[page].keychar
  _menu.custom_gamepad_axis = m[page].gamepad_axis
  _menu.custom_gamepad_dpad = m[page].gamepad_dpad
  _menu.custom_gamepad_button = m[page].gamepad_button
  _menu.custom_gamepad_analog = m[page].gamepad_analog
  m[page].init()
  _menu.redraw()
  show_page()
end

-- go to one of the four pages (MIX TAPE HOME PARAMS), keeping E1 in step
function _menu.goto_panel(n)
  _menu.panel = n
  _menu.set_page(_menu.panels[n])
end

-- draw panel indicator
function _menu.draw_panel()
  if _menu.shownav then
    screen.aa(1)
    screen.line_width(1)
    for i = 1,4 do
      screen.level(i == _menu.panel and 8 or 2)
      screen.move((i-1)*33,0)
      screen.line_rel(30,0)
      screen.stroke()
    end
  end
end

-- global menu keys
function _menu.keycode(c,value)
  -- those are globals and can't be overriden by a sub-menu
  if value>0 then
    if c=="F1" then
      _menu.goto_panel(1)
      return
    elseif c=="F2" then
      _menu.goto_panel(2)
      return
    elseif c=="F3" then
      _menu.goto_panel(3)
      return
    elseif c=="F4" then
      _menu.goto_panel(4)
      return
    end
  end

  -- if a sub-menu defines its own handler, it takes precedence...
  if _menu.keyboardcode then
    _menu.keyboardcode(c,value)
    return
  end

  -- ... otherwise we use those default bindings in most places

  -- E2 emu (scolling)
  if value>0 then
    if c=="DOWN" then
      _menu.penc(2,1)
    elseif c=="UP" then
      _menu.penc(2,-1)
    elseif c=="PAGEDOWN" then
      _menu.penc(2,6)
    elseif c=="PAGEUP" then
      _menu.penc(2,-6)
    end
  end

  -- K2/K3 emu
  if value==1 or value==0 then
    if c=="LEFT" then
      _menu.key(2,value)
    elseif c=="RIGHT" then
      _menu.key(3,value)
    end
  end

  -- parameter change with +/-
  if c=="MINUS" then
    _menu.penc(3,value*-1)
  elseif c=="EQUAL" then
    _menu.penc(3,value)
  end
end

function _menu.keychar(c)
  if _menu.keyboardchar then _menu.keyboardchar(c) end
end

function _menu.gamepad_axis(_sensor_axis,_value)

  -- if a sub-menu defines its own handler, it takes precedence...
  if _menu.custom_gamepad_axis then
    _menu.custom_gamepad_axis(_sensor_axis,_value)
    return
  end

  if gamepad.down() then
    _menu.penc(2,1)
  elseif gamepad.up() then
    _menu.penc(2,-1)
  elseif gamepad.left() then
    _menu.key(2,1)
  elseif gamepad.right() then
    _menu.key(3,1)
  end
end

function _menu.gamepad_button(b,value)

  if value == 1 and (b == "L1" or b == "R1") then
    local delta = b == "R1" and 1 or -1
    local c = next_panel(delta)
    if c ~= _menu.panel then
      _menu.shownav = true
      _menu.panel = c
      _menu.set_page(_menu.panels[_menu.panel])
      nav_vanish:start()
    end
  end

  -- if a sub-menu defines its own handler, it takes precedence...
  if _menu.custom_gamepad_button then
    _menu.custom_gamepad_button(b,value)
    return
  end

  if value==1 or value==0 then
    if b == "B" then
      _menu.key(2,value)
    elseif b == "A" then
      _menu.key(3,value)
    end
  end
end

-- interfaces

m["HOME"] = require 'core/menu/home'
m["SELECT"] = require 'core/menu/select'
m["PREVIEW"] = require 'core/menu/preview'
m["PARAMS"] = require 'core/menu/params'
m["SYSTEM"] = require 'core/menu/system'
m["DISPLAY"] = require 'core/menu/display'
m["DEVICES"] = require 'core/menu/devices'
m["WIFI"] = require 'core/menu/wifi'
m["SETTINGS"] = require 'core/menu/settings'
m["RESTART"] = require 'core/menu/restart'
m["RESET"] = require 'core/menu/reset'
m["AUDIO"] = require 'core/menu/audio'
m["UPDATE"] = require 'core/menu/update'
m["SLEEP"] = require 'core/menu/sleep'
m["MIX"] = require 'core/menu/mix'
m["TAPE"] = require 'core/menu/tape'
m["MODS"] = require 'core/menu/mods'
