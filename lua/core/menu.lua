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
  _menu.errordetail = nil -- (lines for the screen, set by the caller that has them: a failed engine)
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
    _menu.errordetail = nil
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

-- BEGIN handler guard
-- Linux desktop: an error in a menu key or encoder handler used to be only a line in the log (a page that "does nothing"). now it is logged with the handler's name, the page is redrawn so that it stays whole, and a short
-- message stands on the device window for a few seconds (the note of show_note). on the device the handlers are called as before
local handler_guard = os.getenv("NORNS_PLATFORM") ~= nil

-- the note on the window for an error in a handler (a few seconds): also for the script's grid key handlers (core/grid.lua)
function _menu.handler_error(what, err)
  if type(err) ~= "string" then err = tostring(err) end
  local first = err:match("^[^\n]*") or err
  local short = first:gsub("^.-([%w_]+%.lua:%d+:)", "%1"):gsub("%s+", " ")
  _menu.error_note = ("ERROR " .. what .. ": " .. short):sub(1, 78)
  _menu.error_note_until = util.time() + 8
  if _menu.show_note then _menu.show_note() end
  if _menu.mode and _menu.redraw then pcall(_menu.redraw) end
end

local function call_handler(what, fn, ...)
  if not handler_guard then return fn(...) end
  local res = table.pack(pcall(fn, ...))
  if res[1] then return table.unpack(res, 2, res.n) end
  local err = res[2]
  if type(err) ~= "string" then err = tostring(err) end
  print("menu " .. what .. " handler error: " .. err)
  _menu.handler_error(what, err)
end
-- END handler guard

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
  else call_handler("enc", _menu.penc, n, delta) end
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
      call_handler("key", _menu.key, n, z) -- always 1,0
      if _menu.mode == true then _menu.redraw() end
    else
      call_handler("key", _menu.key, n, z) -- always 1,1
    end
    -- key 2/3 pass
  else
    call_handler("key", _menu.key, n, z)
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
-- apps are tapped by the window (_norns.app_input), and still play directly: their monitor
-- goes to TAPE only (_norns.monitor_out). the button goes MIC > SYS > OFF.
-- the choice is kept for the next start: ~/.mic-off unless it was "mic", ~/.norns-input for
-- "system" and "app" (with the app)
_menu.input = "mic"
_menu.mic_live = true -- the Mac's own input reaches norns
local MIC_OFF = "/home/we/.mic-off"
local INPUT_KEPT = "/home/we/.norns-input"
local mic_links = {}
local mic_checked = false
local INPUT_SHOWN = {off = 0, mic = 1, system = 2, app = 3, monitor = 2}
local INPUT_LABEL = {off = "off", mic = "mic / interface", system = "all apps (system audio)",
  monitor = "sink monitor (hears norns too)"}
-- Linux: SYS is every application except norns' own (no feedback). the monitor of the output card is an extra that
-- hears norns itself too: only offered with NORNS_SYS_MONITOR=1 (audio.conf sys_monitor=1)
local function monitor_ok() return _norns.mic_input ~= nil and os.getenv("NORNS_SYS_MONITOR") == "1" end
local MONITOR_WARNING = "INPUT: sink monitor hears norns too, feedback possible"

-- the standing note on the device window (Linux): one at a time, the most urgent first: the sink monitor may feed back, the MAIDEN button has no maiden to open (a few seconds), a SuperCollider
-- plug-in of the wrong architecture (SuperCollider will not start), serialosc has the grid, the audio is not connected
function _menu.show_note()
  if not _norns.set_warning then return end
  _norns.set_warning(_menu.error_note or _menu.launch_note or _menu.input_note or _menu.input == "monitor" and MONITOR_WARNING or _menu.maiden_note or _menu.plugin_note or _menu.heal_note or _menu.mi_note or _menu.class_note or _menu.alsa_note or _menu.grid_note or _menu.audio_note or "")
end

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
  if _norns.mic_input then
    -- Linux: the capture ports of the card crone chose, by port flags (port names on PipeWire are the card's
    -- name, not system:capture_N)
    _norns.mic_input(live)
    _menu.mic_live = live
    return
  end
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
  if (mode == "system" or mode == "app" or mode == "monitor") and not _norns.app_input then mode = "off" end
  if mode == "monitor" and not monitor_ok() then mode = "off" end
  if mode == "app" and not bundle then mode = "off" end
  -- Windows: the button remembers what was asked for (a MIC that could not open does not block SYS behind it)
  if _norns.audio_input then _menu.win_cursor = mode end
  set_capture(mode == "mic")
  -- other apps keep playing: the monitor of them goes to TAPE only, not heard a second time
  -- (the sink monitor contains norns' own output: its input monitor must be off too, or it is a loop)
  if _norns.monitor_out then _norns.monitor_out(mode ~= "system" and mode ~= "app" and mode ~= "monitor") end
  if _norns.app_input then
    local label = not quiet and (INPUT_LABEL[mode] or name or bundle) or nil
    if mode == "system" then
      _norns.app_input("system", label)
    elseif mode == "monitor" then
      _norns.app_input("sink-monitor", label)
    elseif mode == "app" then
      _norns.app_input(bundle, label)
    else
      _norns.app_input(nil, label)
    end
  end
  -- Windows (docs/port/phase-m3.md): the program says what the input really is now; MIC with no input device, SYS with no loopback stay OFF, with the reason on the device window
  _menu.input_note = nil
  if _norns.audio_input then
    local actual, why = _norns.audio_input()
    if actual ~= mode and (mode == "mic" or mode == "system") then
      -- the program's own sentences ("MIC needs an INPUT: ...", "SYS only hears ...") are shown as they are
      if why:find("^MIC") or why:find("^SYS") then _menu.input_note = why
      else _menu.input_note = "INPUT: " .. (why ~= "" and why or "not available") .. " (off)" end
      mode = actual
    elseif mode == "system" then
      _menu.input_note = "SYS can feed back; lower softcut or mute if it howls"
    end
  end
  _menu.input = mode
  _menu.show_note()
  if mode == "mic" and not _norns.audio_input then
    os.remove(MIC_OFF)
  elseif not _norns.audio_input then
    local f = io.open(MIC_OFF, "w")
    if f then f:close() end
  end
  if _norns.audio_input then
    -- Windows: the input is OFF at every start (nothing is remembered: a microphone next to the speakers would feed back before anyone could reach the button)
  elseif mode == "system" or mode == "app" or mode == "monitor" then
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
  if _menu.input == "system" or _menu.input == "app" or _menu.input == "monitor" then
    _menu.set_input("off", nil, nil, true)
  end
end

-- the MIC button
local INPUT_NEXT = {mic = "system", system = "off", off = "mic", app = "off", monitor = "off"}
function _menu.next_input()
  if _menu.input == "system" and monitor_ok() then
    _menu.set_input("monitor")
    return
  end
  local mode = INPUT_NEXT[_menu.input] or "mic"
  if _norns.audio_input and _norns.audio_info then
    -- Windows: OFF > MIC > SYS > OFF from what was asked for last, so SYS can be reached when MIC could not open; a press never lands on what is already the state
    local order = {off = "mic", mic = "system", system = "off"}
    local inf = _norns.audio_info()
    local sys_ok = not (inf and inf.sys_available == false)
    local cur = _menu.win_cursor or _menu.input
    for _ = 1, 3 do
      mode = order[cur] or "mic"
      if mode == "system" and not sys_ok then mode = "off" end
      if mode ~= _menu.input then break end
      cur = mode
    end
    _menu.set_input(mode)
    return
  end
  if mode == "system" and not _norns.app_input then mode = "off" end
  -- Windows: without a WASAPI loopback device in this PortAudio there is no SYS; the button goes MIC > OFF (the AUDIO page says why)
  if mode == "system" and _norns.audio_input and _norns.audio_info then
    local inf = _norns.audio_info()
    if inf and inf.sys_available == false then mode = "off" end
  end
  _menu.set_input(mode)
end

-- when norns is up (crone has connected the input again): take it off if it was off
function _menu.check_mic()
  if mic_checked or not _norns.show_control then return end
  mic_checked = true
  if _norns.audio_input then
    -- Windows: always OFF at the start, whatever audio.conf says about the input device (the device is opened, the input is not routed until the owner presses MIC)
    _menu.set_input("off", nil, nil, true)
    return
  end
  local f = io.open(INPUT_KEPT)
  if f then
    local mode, bundle, name = f:read("l"), f:read("l"), f:read("l")
    f:close()
    if mode == "system" or (mode == "monitor" and monitor_ok()) or (mode == "app" and bundle and bundle ~= "") then
      -- said on the device
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

-- double click on the fader: 0 dB
_norns.output_reset = function()
  out_unmuted = nil
  params:set("output_level", 0)
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

-- Linux desktop: a problem with the sound card (no ports, a device name that matches nothing) stays on
-- the device screen, not only in the log (crone starts unconnected then)
-- Linux: the optional MIDI auto-connect (NORNS_MIDI_IN_FROM, from audio.conf midi_in_from=): off unless a prefix is given
if _norns.midi_in_from then
  hook.system_post_startup:register("menu-midi-autolink", function()
    local from = os.getenv("NORNS_MIDI_IN_FROM")
    if from and from ~= "" then _norns.midi_in_from(from) end
    -- and the output: Verdandi:midi_out to the MIDI inputs it names (NORNS_MIDI_OUT_TO, from audio.conf midi_out_to=), off unless given
    local to = os.getenv("NORNS_MIDI_OUT_TO")
    if to and to ~= "" and _norns.midi_out_to then _norns.midi_out_to(to) end
  end)
end

-- Linux: serialosc (serialosc-device) has the grid or arc that norns opened too: a note on the device window while it does; the log line
-- says what to do. looked at when a grid is plugged in (the C side calls grid_conflict_changed) and every 3 seconds (metro 33)
if _norns.grid_conflict_text and _norns.set_warning then
  local function grid_note_update()
    local t = _norns.grid_conflict_text()
    if t ~= _menu.grid_note then
      _menu.grid_note = t
      _menu.show_note()
    end
  end
  -- SuperCollider plug-ins built for another machine (linux/plugin_arch_check wrote the list before sclang started): the note goes when
  -- the files are gone
  local function plugin_note_update()
    local t = _norns.plugin_note_text and _norns.plugin_note_text() or nil
    if t ~= _menu.plugin_note then
      _menu.plugin_note = t
      _menu.show_note()
    end
  end
  -- the Raspberry Pi mi-UGens: (1) the launcher moved a script's download aside before sclang started and left .mi-heal-note: shown once (the file is read
  -- and removed, the note stays for a while); (2) a script downloaded them while norns runs: a note with the hint to restart, until the files are gone
  -- (SYSTEM > CLEAN UP moves them after one confirmation). docs/port/mi-ugens.md
  local function mi_note_update()
    local home = os.getenv("NORNS_HOME") or "/home/we"
    -- the launcher's notes (the mi-UGens heal, the heal of any wrong-architecture plug-in): each file is read once and removed
    for _, name in ipairs({".mi-heal-note", ".plugin-heal-note"}) do
      local f = io.open(home .. "/" .. name)
      if f then
        local text = f:read("l")
        f:close()
        os.remove(home .. "/" .. name)
        if text and text ~= "" then
          _menu.heal_note = text
          _menu.heal_note_until = util.time() + (tonumber(os.getenv("NORNS_HEAL_NOTE_SECONDS")) or 25)
          _menu.show_note()
          print(name == ".mi-heal-note" and ("mi-UGens: " .. text) or ("plugin heal: " .. text))
        end
      end
    end
    if _menu.heal_note and util.time() >= (_menu.heal_note_until or 0) then
      _menu.heal_note = nil
      _menu.show_note()
    end
    local t = _norns.mi_foreign_note_text and _norns.mi_foreign_note_text() or nil
    if t ~= _menu.mi_note then
      _menu.mi_note = t
      _menu.show_note()
      if t then print(t) end
    end
  end
  -- a class SuperCollider could not find or found twice (logs/sclang.log, read from its end and only when it has grown): the line is printed once
  -- and the note stands until the log of a clean start replaces it. lua/core/sc_class_check.lua
  local class_size, class_seen = -1, ""
  local function class_note_update()
    local home = os.getenv("NORNS_HOME") or "/home/we"
    local f = io.open(home .. "/logs/sclang.log", "rb")
    if not f then return end
    local size = f:seek("end")
    f:close()
    if size == class_size then return end
    class_size = size
    local C = require 'core/sc_class_check'
    local found = C.scan(home .. "/logs/sclang.log", {home = home, pack = require('core/mi_ugens').info(home).state, ext = os.getenv("NORNS_PLATFORM") == "windows" and (home .. "/extensions") or nil})
    local t = C.note(found)
    local key = ""
    for _, x in ipairs(found) do key = key .. x.line .. "\n" end
    if key ~= class_seen then
      class_seen = key
      for _, x in ipairs(found) do print(x.line) end
    end
    if t ~= _menu.class_note then
      _menu.class_note = t
      _menu.show_note()
    end
  end
  -- the ALSA raw MIDI route for Reaper (alsa_midi_out_to= is set): snd-virmidi not loaded, no port yet, the Reaper entry to enable for a few seconds after the connection (lua/core/virmidi.lua)
  local alsa_seen, alsa_since = "", nil
  local function alsa_note_update()
    if not _norns.alsa_midi_link then return end
    local V = require 'core/virmidi'
    local t = nil
    if V.configured() then
      local count, names = _norns.alsa_midi_link()
      local now = util.time()
      if names ~= alsa_seen then alsa_seen = names; alsa_since = names ~= "" and now or nil end
      t = V.note({to = V.to(), count = count, names = names, loaded = V.loaded(), since = alsa_since, now = now})
    end
    if t ~= _menu.alsa_note then
      _menu.alsa_note = t
      _menu.show_note()
    end
  end
  _norns.grid_conflict_changed = grid_note_update
  hook.system_post_startup:register("menu-grid-conflict", function()
    grid_note_update()
    plugin_note_update()
    mi_note_update()
    class_note_update()
    alsa_note_update()
    -- a metro, not a clock coroutine: a script change cancels every coroutine. 33 and 34 are reserved with 31-36
    local poll = metro[33]
    poll.time = 3
    poll.count = -1
    poll.event = function()
      grid_note_update()
      plugin_note_update()
      mi_note_update()
      class_note_update()
      alsa_note_update()
      -- the note of the MAIDEN and MANUAL buttons goes after a few seconds
      if _menu.maiden_note and util.time() >= (_menu.maiden_note_until or 0) then
        _menu.maiden_note = nil
        _menu.show_note()
      end
      if _menu.error_note and util.time() >= (_menu.error_note_until or 0) then
        _menu.error_note = nil
        _menu.show_note()
      end
      -- a script ran "sudo systemctl restart norns-*" (a script's installer): linux/shims/systemctl left a request instead of the Raspberry Pi's
      -- services: restart norns the clean way
      local req = io.open("/home/we/.norns-request-restart")
      if req then
        req:close()
        os.remove("/home/we/.norns-request-restart")
        print("norns: a script asked for a restart (systemctl restart norns-*, no systemd on this build): restarting norns")
        _norns.restart()
      end
    end
    poll:start()
  end)
end

if _norns.audio_status and _norns.set_warning then
  hook.system_post_startup:register("menu-audio-warning", function()
    local warning = _norns.audio_status()
    if warning ~= "" then
      print("audio: " .. warning)
      _menu.audio_note = "AUDIO: not connected, see SYSTEM > AUDIO"
      _menu.show_note()
    end
  end)
end

-- Windows: when the sound card could not be opened (busy, gone) norns runs on null audio; say so on the window until the next start, in plain words (the page SYSTEM > AUDIO has the details)
if _norns.audio_info and _norns.set_warning then
  hook.system_post_startup:register("menu-audio-fallback", function()
    local a = _norns.audio_info()
    if a.mode == "fallback" or (a.mode == "device" and a.note ~= "") then
      print("audio: " .. a.note)
      _menu.audio_note = (a.mode == "fallback" and "NO SOUND. " or "AUDIO: ") .. a.note:gsub("^no sound: ", "")
      _menu.show_note()
    end
  end)
end

-- the mouse on the oled (x 0-127, y 0-63; kind "down", "drag", "up", "wheel" with its
-- steps), for the menu page that takes it (MIX)
_norns.screen_mouse = function(x, y, kind, value)
  local page = _menu.mode and m[_menu.page]
  if page and page.mouse then
    page.mouse(tonumber(x), tonumber(y), kind, tonumber(value) or 0)
  end
end

-- 1-4: menu page (clicking the page that is up goes back to the script), 5: the manual of
-- Verdandi (the macOS app), 6: the next audio input (MIC > SYS > OFF)
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
    if _norns.set_warning and (manual == nil or not util.file_exists(manual)) then
      -- Linux: linux/norns.sh points NORNS_MANUAL at linux/manual/manual.html; say so when it is not there
      _menu.maiden_note = "manual not found: linux/manual/manual.html"
      _menu.maiden_note_until = util.time() + 6
      _menu.show_note()
    elseif manual then
      _norns.open_url(manual)
    end
  elseif n == 6 then
    _menu.next_input()
  elseif n == 7 then
    -- Linux: the MAIDEN button found nothing listening on maiden's port (linux/norns.sh starts maiden when it is built)
    _menu.maiden_note = "maiden is not running, see log"
    _menu.maiden_note_until = util.time() + 6
    _menu.show_note()
  elseif n == 9 then
    -- Windows: no maiden in the build (scripts are copied into the dust\code folder, windows\README.md), or the launcher did not start it and says why (its port is held by another program)
    _menu.maiden_note = require('core/maiden_note').text(os.getenv("VERDANDI_MAIDEN_WHY"))
    _menu.maiden_note_until = util.time() + 8
    _menu.show_note()
  elseif n == 8 then
    -- Linux: maiden opened, but matron has no console socket: norns.sh --terminal keeps matron's prompt in the terminal
    _menu.maiden_note = "maiden: no norns console with --terminal"
    _menu.maiden_note_until = util.time() + 8
    _menu.show_note()
  end
end

_menu.set_mode = function(mode)
  -- Linux desktop: a text entry that is open belongs to the page it was opened for; it is closed when the menu changes its mode (lua/lib/textentry.lua)
  do local te = package.loaded['textentry']; if te and te.menu_changed then te.menu_changed("mode") end end
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
  do local te = package.loaded['textentry']; if te and te.menu_changed then te.menu_changed("page") end end -- (see set_mode)
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
  -- (a handler that answers false did not want the key: the default bindings below are used for it; the Linux pages THEME, SCREEN and PICKER do this)
  if _menu.keyboardcode then
    if _menu.keyboardcode(c,value) ~= false then return end
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
-- the look of the screen (brightness, colour, greys): computers only (docs/port/ui-settings-plan.md)
if os.getenv("NORNS_PLATFORM") ~= nil then
  m["UI"] = require 'core/menu/ui' -- shown as SCREEN (docs/port/colour-picker-plan.md: the visible names are SCREEN and THEME, the ids and the files keep their names)
  m["BOX"] = require 'core/menu/box' -- shown as THEME: the look of the box (docs/port/box-style-plan.md)
  m["SCREEN"] = m["UI"]
  m["THEME"] = m["BOX"]
  m["MIDIMAP"] = require 'core/menu/midimap' -- MIDI control of E1-E3 and K1-K3 (docs/port/midi-map-plan.md)
  m["PICKER"] = require 'core/menu/picker' -- the colour picker, opened by K3 on a hex row (docs/port/colour-picker-plan.md)
  require 'core/clipboard' -- the window's answer to Ctrl+V (_norns.clipboard_text)
  m["CLEANUP"] = require 'core/menu/cleanup' -- docs/port/clean-layout.md
  -- a finding of the launcher's duplicate guard that it left alone (two folders of the owner's define the same class): one plain line in the log and a standing note on the window
  do
    local ln = os.getenv("VERDANDI_LAUNCH_NOTE")
    if ln and ln ~= "" then
      _menu.launch_note = ln
      print("### " .. ln)
      if _menu.show_note then pcall(_menu.show_note) end
    end
  end
  require('core/ui_settings').load_and_apply() -- ui.conf, once at start (does nothing without _norns.ui_look)
  require('core/box_settings').load_and_apply() -- box.conf, once at start (does nothing without _norns.box_look)
  -- the MIDI MAP layer (a tap in midi.lua's event function, after the scripts and the params MAP), its settings (midimap.conf) and the window's pick callback
  norns.midimap = require 'core/midimap'
  norns.midimap.load()
  norns.midimap.install()
end
m["UPDATE"] = require 'core/menu/update'
m["SLEEP"] = require 'core/menu/sleep'
m["MIX"] = require 'core/menu/mix'
m["TAPE"] = require 'core/menu/tape'
m["MODS"] = require 'core/menu/mods'

-- Windows build only (docs/port/phase-m3.md, "UI principle"): the list pages of the system menu are drawn brighter (unselected rows were level 4 on black: dim and olive under a theme), the numbers of the
-- audio are written to norns.log every ten seconds, and a MIC that cannot work says what to do. Nothing here runs on Linux or macOS: _norns.audio_devices exists only in norns.exe
if _norns.audio_devices ~= nil then
  local winui = require 'core/menu/winui'
  for _, name in ipairs({"SYSTEM", "DISPLAY", "DEVICES", "WIFI", "SETTINGS", "RESTART", "RESET", "UPDATE", "SLEEP", "MODS", "UI", "BOX", "MIDIMAP", "CLEANUP", "SELECT", "PARAMS"}) do
    local page = m[name]
    if page and page.redraw and not page.winui_wrapped then
      page.redraw = winui.wrap(page.redraw)
      page.winui_wrapped = true
    end
  end
  hook.system_post_startup:register("menu-audio-log", function()
    local audio = m["AUDIO"]
    pcall(audio.forget_exclusive)
    local prev
    clock.run(function()
      while true do
        clock.sleep(10)
        local line, info = audio.log_line(prev)
        if line then print(line) end
        prev = info
      end
    end)
  end)
end
