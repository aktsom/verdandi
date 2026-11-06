-- every row of our own menu pages fits the 128 x 64 screen at long values, measured with the real font metrics (page_width.lua): CLEAN UP, DEVICES, ...
-- the pages are driven through their own key and encoder handlers into every state that shows a row (all rows, lists, confirmations, messages), with
-- the longest names the pages can be given (a long device name, a long preset name, a long folder, a long version).
-- run from the repo root:  FONT_WIDTHS=<table from font_widths_dump> NORNS_PLATFORM=linux lua5.3 linux/tests/page_width_test.lua
package.path = "lua/?.lua;lua/core/?.lua;lua/lib/?.lua;" .. package.path
local W = dofile("linux/tests/page_width.lua")
W.load(assert(os.getenv("FONT_WIDTHS"), "FONT_WIDTHS"))
local fails = 0
local function check(ok, what) if not ok then fails = fails + 1; print("FAIL " .. what) else print("ok   " .. what) end end
local function put(path, text) local f = assert(io.open(path, "w")); f:write(text); f:close() end
local function sh(cmd) local h = io.popen(cmd .. " 2>&1"); local out = h:read("a"); h:close(); return out end

-- the pages write below /home/we: map it into a scratch folder
local tmp = os.tmpname(); os.remove(tmp); os.execute("mkdir -p " .. tmp)
local real_open, real_remove, real_rename, real_execute = io.open, os.remove, os.rename, os.execute
local function map(p) return (p:gsub("^/home/we", tmp)) end
io.open = function(p, m) return real_open(map(p), m) end
os.remove = function(p) return real_remove(map(p)) end
os.rename = function(a, b) return real_rename(map(a), map(b)) end
os.execute = function(cmd) return real_execute((cmd:gsub("/home/we", tmp))) end
print_real = print

local bad = W.self_check()
check(#bad == 0, "the width table agrees with cairo for whole strings " .. table.concat(bad, "; "))

-- one page: `view(tag)` is called after each redraw; collect what does not fit
local seen = {}
local tape_err
local drawn = 0
local function look(page, tag)
  W.clear()
  local ok, err = pcall(page.redraw)
  if not ok then seen[#seen + 1] = tag .. ": redraw raised: " .. tostring(err); return end
  drawn = drawn + #W.records()
  for _, v in ipairs(W.violations()) do
    if not seen[v] then seen[v] = true; seen[#seen + 1] = tag .. ": " .. v end
  end
end
local function report(name)
  local out = {}
  for _, v in ipairs(seen) do out[#out + 1] = v end
  check(drawn > 20, name .. ": the check saw " .. drawn .. " texts drawn (the page drew something)")
  drawn = 0
  check(#out == 0, name .. " fits the screen at long values" .. (#out > 0 and ("\n      " .. table.concat(out, "\n      ", 1, math.min(#out, 15))) or ""))
  seen = {}
end

W.install()
norns = {none = function() end}
local pushed = {}
_menu = {redraw = function() end, set_page = function(p) pushed[#pushed + 1] = p end}
util = {
  clamp = function(x, lo, hi) return math.max(lo, math.min(hi, x)) end,
  os_capture = function(cmd, raw) local h = io.popen(cmd); local s = h:read("a"); h:close(); if raw then return s end s = s:gsub("^%s+", ""):gsub("%s+$", ""):gsub("[\n\r]+", " "); return s end,
  time = function() return os.time() end,
  scandir = function(dir) local out = {} local p = io.popen("ls -p '" .. map(dir) .. "' 2>/dev/null") for l in p:lines() do out[#out + 1] = l end p:close() return out end,
}
package.loaded.util = util

-- ======================================================= CLEAN UP
do
  local home = os.tmpname(); os.remove(home); os.execute("mkdir -p '" .. home .. "'")
  local long = string.rep("a-very-long-name-", 6)
  os.execute(string.format("mkdir -p '%s/dust/code/%s/Classes' '%s/logs/crash' '%s/cache/x' '%s/.local/share/SuperCollider/Extensions/mi-UGens/Classes' '%s/x/%s'", home, long, home, home, home, home, long))
  put(home .. "/.local/share/SuperCollider/Extensions/mi-UGens/.verdandi-stamp", "pack=mi-UGens\nserial=1\ncommit=10f6824f68ad63475f67dfe3fe5016e2d2634f84\nbuilt=2026-11-06\nverdandi=0.1~git20261106.3393.230f7ba8\n")
  put(home .. "/.local/share/SuperCollider/Extensions/mi-UGens/Classes/MiBeads.sc", "// ours\n")
  put(home .. "/dust/code/" .. long .. "/Classes/MiBeads.sc", "// theirs\n")
  put(home .. "/logs/sclang.log", "ERROR: duplicate Class found: 'MiBeads' \n" .. home .. "/.local/share/SuperCollider/Extensions/mi-UGens/Classes/MiBeads.sc\n" .. home .. "/dust/code/" .. long .. "/Classes/MiBeads.sc\n\n")
  put(home .. "/.plugin-fix", home .. "/x/" .. long .. "\twrong-architecture plug-in (32-bit ARM) on x86_64\n")
  for i = 1, 4 do put(home .. "/logs/" .. string.rep("x", 60) .. i .. ".log", "l") end
  os.execute("mkdir -p '" .. home .. "/disabled'")
  local tidy = os.getenv("NORNS_TIDY") or "linux/tidy.sh"
  for i = 1, 3 do put(home .. "/x/" .. i .. "-" .. long .. ".so", "so"); sh("NORNS_HOME='" .. home .. "' '" .. tidy .. "' disable '" .. home .. "/x/" .. i .. "-" .. long .. ".so' 'wrong-architecture plug-in (32-bit ARM) on x86_64'") end
  local real_getenv = os.getenv
  os.getenv = function(k) if k == "NORNS_HOME" then return home elseif k == "NORNS_TIDY" then return tidy end return real_getenv(k) end
  local page = dofile("lua/core/menu/cleanup.lua")
  os.getenv = real_getenv
  page.init()
  for pos = 1, #page.rows do
    page.pos = pos
    look(page, "CLEAN UP row " .. pos .. " (" .. page.rows[pos].name .. ")")
    -- K3 on the row: a confirmation, a list or a message
    page.key(3, 1); look(page, "CLEAN UP K3 on " .. page.rows[pos].name)
    if page.mode == "list" then
      for i = 1, #page.items do page.ipos = i; look(page, "CLEAN UP list " .. tostring(page.list_kind) .. " item " .. i) end
    end
    page.key(2, 1)
    page.init(); page.pos = pos
  end
  for age = 1, 4 do page.age = age; page.init(); page.pos = #page.rows; look(page, "CLEAN UP age row " .. age) end
  os.execute("rm -rf '" .. home .. "'")
  report("CLEAN UP")
end

-- ======================================================= DEVICES (midi, grid, arc, hid, keyboard layout, serialosc, virmidi)
do
  local LONGNAME = "Behringer UMC1820 USB Audio Class 2 Multichannel Interface Port 1 (long name)"
  package.loaded["core/keyboard"] = {keymap = {us = true, ["a-very-long-keyboard-layout-name-here"] = true}, selected_map = "a-very-long-keyboard-layout-name-here", set_map = function() end}
  midi = {devices = {}, vports = {}, update_devices = function() end}
  grid = {devices = {}, vports = {}, update_devices = function() end}
  arc = {devices = {}, vports = {}, update_devices = function() end}
  hid = {devices = {}, vports = {}, update_devices = function() end}
  for i = 1, 16 do midi.vports[i] = {name = LONGNAME .. " " .. i} end
  for i = 1, 4 do grid.vports[i] = {name = LONGNAME}; arc.vports[i] = {name = LONGNAME}; hid.vports[i] = {name = LONGNAME} end
  for i = 1, 6 do
    midi.devices[i] = {name = LONGNAME .. " " .. i}; grid.devices[i] = {name = LONGNAME .. " " .. i}
    arc.devices[i] = {name = LONGNAME .. " " .. i}; hid.devices[i] = {name = LONGNAME .. " " .. i}
  end
  _norns = {midi_in_status = function() return true, 3, "A long client name:out, Another long client name:out" end}
  _menu.grid_note = "GRID: serialosc has this grid"
  local real_getenv = os.getenv
  os.getenv = function(k) if k == "NORNS_PLATFORM" then return "linux" end return real_getenv(k) end
  package.loaded["core/virmidi"] = {configured = function() return true end, to = function() return "VirMIDI" end, wants_module = function() return true end,
    loaded = function() return false end, load_status = function() return "idle" end, guide_lines = function() return {"SNDVIRMIDI IS NOT LOADED", "A kernel module that makes the virtual MIDI card", "Reaper can read"} end,
    COMMAND = "sudo modprobe snd-virmidi midi_devs=1 (long command to type in a terminal)", reaper_entry = function(n) return "VirMIDI [hw:3,0,0] " .. n end, reaper_hw = function() return "hw:3,0,0 a long hardware name" end,
    note = function() return nil end}
  _norns.alsa_midi_link = function() return 1, "VirMIDI 3-0 long port name" end
  _norns.serialosc_guide = function() return {} end
  local page = dofile("lua/core/menu/devices.lua")
  os.getenv = real_getenv
  page.init()
  page.refresh()
  local function sweep(tag)
    look(page, tag)
  end
  for pos = 1, page.len do
    page.pos = pos; sweep("DEVICES type row " .. pos)
  end
  for sec = 1, 5 do
    page.init(); page.refresh(); page.pos = sec
    pcall(page.key, 3, 1)   -- open the section (a list, the select page, serialosc or virmidi)
    sweep("DEVICES " .. tostring(page.section or page.mode) .. " opened")
    for step = 1, 8 do
      pcall(page.enc, 2, 1); sweep("DEVICES " .. tostring(page.section or page.mode) .. " scrolled " .. step)
    end
    pcall(page.key, 3, 1); sweep("DEVICES " .. tostring(page.section or page.mode) .. " K3")
    pcall(page.key, 3, 1); sweep("DEVICES " .. tostring(page.section or page.mode) .. " K3 again")
  end
  for _, mode in ipairs({"serialosc", "confirm_serialosc", "virmidi", "confirm_virmidi"}) do
    page.init(); page.refresh(); page.mode = mode; sweep("DEVICES " .. mode)
  end
  report("DEVICES")
end

-- ======================================================= THEME (box.lua) and SCREEN (ui.lua)
do
  _norns = {box_look = function() end, ui_look = function() end, key = function() end, enc = function() end, show_control = function() end, toast = function() end}
  _path = {keyboard_layout = "/nonexistent/keyboard.layout"}
  norns.menu = {status = function() return true end, get_key = function() return "k" end, get_enc = function() return "e" end, get_redraw = function() return "r" end,
    get_refresh = function() return "f" end, set = function() end, init = function() end}
  package.loaded.textentry = {enter = function() end}
  package.loaded['core/menu/picker'] = {open = function() end, take_returning = function() return false end}
  package.loaded['core/keyboard'] = {ctrl = function() return false end, shift = function() return false end}
  package.loaded['core/clipboard'] = {copy = function() return true end, paste_colour = function() end}
  local quiet = print
  print = function() end
  local box = require 'core/box_settings'
  box.log = function() end
  local ui = require 'core/ui_settings'
  ui.log = function() end
  local pages = {}
  pages.THEME = dofile("lua/core/menu/box.lua")
  pages.SCREEN = dofile("lua/core/menu/ui.lua")
  box.load(); ui.load()
  for i = 1, 14 do box.save_look(string.format("Look %02d", i)); ui.save_preset(string.format("Shade %02d", i)) end
  box.save_look(string.rep("W", 18)); ui.save_preset(string.rep("W", 18))
  box.save_look(string.rep("M", 18) .. "x"); ui.save_preset(string.rep("M", 18) .. "x")
  box.reload_looks(); ui.reload_presets()
  for name, page in pairs(pages) do
    page.init()
    local n = #page.rows()
    for pos = 1, n do
      page.pos = pos
      look(page, name .. " row " .. pos)
      -- the row's own views: K3 (a list, a confirmation, a picker, a question) and E3 along the value
      page.init(); page.pos = pos
      pcall(page.key, 3, 1); pcall(page.key, 3, 0); look(page, name .. " K3 on row " .. pos)
      for step = 1, 20 do pcall(page.enc, 2, 1); look(page, name .. " list scrolled " .. step .. " (row " .. pos .. ")") end
      pcall(page.key, 3, 1); pcall(page.key, 3, 0); look(page, name .. " K3 again on row " .. pos)
      pcall(page.key, 2, 1); pcall(page.key, 2, 0)
      page.init(); page.pos = pos
      for step = 1, 12 do pcall(page.enc, 3, 1); look(page, name .. " E3 " .. step .. " on row " .. pos) end
    end
    page.init()
    look(page, name .. " first view")
  end
  print = quiet
  report("THEME and SCREEN")
end

-- ======================================================= AUDIO, MODS, SYSTEM, RESET, RESTART
do
  local LONG = "Focusrite Scarlett 18i20 3rd Gen USB Audio Interface Multichannel"
  local tool = tmp .. "/tool.tsv"
  local f = real_open(tool, "w")
  f:write("hw:CARD=A\t" .. LONG .. "\t18\t20\n", "hw:CARD=B\t" .. LONG .. " second\t2\t0\n", "hw:CARD=C\t" .. LONG .. " third\t0\t2\n")
  f:close()
  local env = {NORNS_AUDIO_SERVER_MODE = "jackd", NORNS_AUDIO_TOOL = "tool", NORNS_AUDIO_RATE = "48000"}
  local getenv = os.getenv
  os.getenv = function(k) if env[k] ~= nil then return env[k] end return getenv(k) end
  util.os_capture = function() return real_open(tool):read("a") end
  util.file_exists = function(p) local h = real_open(map(p)); if h then h:close() return true end return false end
  _norns.restart = function() end
  _norns.audio_status = function() return LONG, LONG, "48000" end
  local pg = {}
  pg.AUDIO = dofile("lua/core/menu/audio.lua")
  os.getenv = getenv
  local m = pg.AUDIO
  m.init()
  for pos = 1, 8 do
    m.pos = pos; look(m, "AUDIO row " .. pos)
    pcall(m.key, 3, 1); pcall(m.key, 3, 0); look(m, "AUDIO K3 on row " .. pos)
    for step = 1, 6 do pcall(m.enc, 3, 1); look(m, "AUDIO E3 " .. step .. " on row " .. pos) end
    for step = 1, 6 do pcall(m.enc, 2, 1); look(m, "AUDIO E2 " .. step .. " on row " .. pos) end
    pcall(m.key, 2, 1); m.init()
  end
  report("AUDIO")
end

do
  for _, name in ipairs({"system", "reset", "restart"}) do
    local ok, page = pcall(dofile, "lua/core/menu/" .. name .. ".lua")
    if ok and type(page) == "table" and page.redraw then
      page.init()
      look(page, name .. " first view")
      for pos = 1, 12 do page.pos = pos; look(page, name .. " row " .. pos); pcall(page.key, 3, 1); look(page, name .. " K3 " .. pos); pcall(page.key, 2, 1); page.init() end
    end
  end
  report("SYSTEM, RESET, RESTART")
end

-- ======================================================= TAPE (long file names, every state)
do
  local C = {TAPE_PLAY_STATE_EMPTY = 0, TAPE_PLAY_STATE_READY = 1, TAPE_PLAY_STATE_PLAYING = 2, TAPE_PLAY_STATE_PAUSED = 3,
    TAPE_REC_STATE_EMPTY = 0, TAPE_REC_STATE_READY = 1, TAPE_REC_STATE_RECORDING = 2, TAPE_REC_STATE_PAUSED = 3}
  local state
  audio = {tape = {constants = C, get_state = function() return state end, subscribe = function() end, unsubscribe = function() end,
    get_diskfree = function() return 123456 end}, tape_compute_diskfree = function() return 123456 end, tape_play_stop = function() end}
  package.loaded.fileselect = {enter = function() end, pushd = function() end}
  package.loaded.textentry = {enter = function() end}
  package.loaded.listselect = {enter = function() end}
  local u = package.loaded.util
  u.s_to_hms = function(sec) return string.format("%02d:%02d:%02d", sec // 3600, sec % 3600 // 60, sec % 60) end
  u.make_dir = function() end
  u.file_exists = function() return false end
  _path = {tape = "/home/we/dust/audio/tape/", audio = "/home/we/dust/audio/"}
  _menu.draw_panel = function() end
  package.loaded["core/menu/tape"] = nil
  local ok, page = pcall(dofile, "lua/core/menu/tape.lua")
  if not ok then
    check(false, "the tape page loads in the test: " .. tostring(page))
  else
    local LONG = "/home/we/dust/audio/tape/a very long recording name for a take 2026-11-06 evening session.wav"
    for ps = 0, 3 do
      for rs = 0, 3 do
        for mode = 1, 2 do
          state = {play = {state = ps, pos = 3725.0, len = 36000.0, loop = true, file = LONG}, rec = {state = rs, pos = 3725.0, file = LONG}}
          local okc, err = pcall(page.init)
          if not okc and not tape_err then tape_err = err; print('tape init error: ' .. tostring(err)) end
          page.mode = mode
          look(page, "TAPE play " .. ps .. " rec " .. rs .. " focus " .. mode)
        end
      end
    end
    report("TAPE")
  end
end

-- ======================================================= MODS (long mod names, enabled and loaded in every combination)
do
  local names = {}
  for i = 1, 8 do names[string.rep("a-very-long-mod-name-", 3) .. i] = true end
  names.short = true; names["WWWWWWWWWWWWWWWWWWWWWWWWWWWWW"] = true
  package.loaded["core/mods"] = {scan = function() return names end, is_enabled = function(n) return #n % 2 == 0 end, is_loaded = function(n) return #n % 3 == 0 end,
    set_enabled = function() end}
  tab = tab or {count = function(t) local c = 0 for _ in pairs(t) do c = c + 1 end return c end}
  _menu.m = {["short"] = true, [string.rep("a-very-long-mod-name-", 3) .. "1"] = true}
  local page = dofile("lua/core/menu/mods.lua")
  page.init()
  for pos = 0, page.len - 1 do
    page.pos = pos; page.select_position(pos); look(page, "MODS at " .. pos)
  end
  report("MODS")
end

-- ======================================================= the colour picker (a long heading, every row, E3 along each, the messages)
do
  package.loaded['core/menu/picker'] = nil
  package.loaded['core/colour'] = nil
  local picker = dofile("lua/core/menu/picker.lua")
  local ev
  package.loaded.textentry = {enter = function(cb) ev = cb end}
  for _, label in ipairs({"SCREEN COLOUR", "A VERY LONG HEADING FOR THE COLOUR OF A THEME PART THAT GOES ON AND ON"}) do
    picker.open({label = label, value = "FFAA00", return_page = "UI", preview = function() end, restore = function() end, ok = function() return true end, note = function() end})
    picker.init()
    for row = 1, 4 do
      picker.row = row
      look(picker, "PICKER " .. label:sub(1, 12) .. " row " .. row)
      for step = 1, 40 do pcall(picker.enc, 3, 1); if step % 8 == 0 then look(picker, "PICKER E3 " .. step .. " row " .. row) end end
      pcall(picker.key, 3, 1); pcall(picker.key, 3, 0); look(picker, "PICKER K3 row " .. row)
      pcall(picker.key, 2, 1); pcall(picker.key, 2, 0); look(picker, "PICKER K2 row " .. row)
      picker.open({label = label, value = "FFAA00", return_page = "UI", preview = function() end, restore = function() end, ok = function() return true end, note = function() end})
      picker.init()
    end
  end
  report("PICKER")
end

os.exit(fails == 0 and 0 or 1)
