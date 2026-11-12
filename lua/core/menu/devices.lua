local keyboard = require 'core/keyboard'
local tabutil = require 'tabutil'

local m = {
  pos = 1,
  last_pos = 1,
  list = {"midi", "grid", "arc", "hid", "keyboard layout"},
}

m.len = #m.list

-- Linux desktop: while serialosc has the grid (the note of lua/core/menu.lua) there is one more entry, with the guide in short lines and the stop without a terminal (docs/port/KNOWN-ISSUES.md 31)
local desktop = os.getenv("NORNS_PLATFORM") ~= nil
local vm_poll_start, vm_poll_stop -- the VIRMIDI page's poll (defined below)
local BASE_LIST = {"midi", "grid", "arc", "hid", "keyboard layout"}

-- Linux desktop: a name that is wider than its room is cut with ".." (a USB device can have a very long name); the device build draws it as before
local function clip(s, room)
  s = tostring(s)
  if not desktop or screen.text_extents(s) <= room then return s end
  local n = #s
  while n > 1 and screen.text_extents(s:sub(1, n) .. "..") > room do n = n - 1 end
  return s:sub(1, n) .. ".."
end

-- Windows build (docs/port/phase-m4.md): one more entry, the MIDI routes page (ports held by other programs, virtual cables, the OSC input, the route tests: lua/core/menu/midiwin.lua)
local function is_windows() return _norns ~= nil and _norns.midi_status ~= nil end
-- Windows: the number of ports with a problem (a port another program holds, a monome that did not answer) on the grid page
local function grid_problem_count()
  if not (_norns and _norns.grid_status) then return 0 end
  local n = 0
  for _ in tostring(_norns.grid_status()):gmatch("\nnote=") do n = n + 1 end
  if tostring(_norns.grid_status()):sub(1, 5) == "note=" then n = n + 1 end
  return n
end
local function midi_held_count()
  local n = 0
  for _ in tostring(_norns.midi_status()):gmatch("\nnote=") do n = n + 1 end
  return n
end
local function list_label(name)
  if is_windows() and name == "midi routes" then
    local n = midi_held_count()
    if n > 0 then return "midi: " .. n .. " held" end
  end
  if is_windows() and name == "grid ports" then
    local n = grid_problem_count()
    if n > 0 then return "grid: " .. n .. " problem" .. (n > 1 and "s" or "") end
  end
  return name
end

local function sync_list()
  if is_windows() then
    if #m.list ~= #BASE_LIST + 2 then
      m.list = {table.unpack(BASE_LIST)}
      m.list[#m.list + 1] = "grid ports"
      m.list[#m.list + 1] = "midi routes"
      if m.mode == "type" then m.len = #m.list end
    end
    return
  end
  if not desktop then return end
  local want = {table.unpack(BASE_LIST)}
  if _menu.grid_note then want[#want + 1] = "serialosc" end
  -- the ALSA raw MIDI route for Reaper (alsa_midi_out_to= is set): the guide, the load without a terminal, the Reaper entry (lua/core/virmidi.lua)
  if require('core/virmidi').configured() then want[#want + 1] = "virmidi" end
  if #want ~= #m.list then
    m.list = want
    if m.mode == "type" then
      m.len = #m.list
      if m.pos > m.len then m.pos = m.len end
    end
  end
  -- the setting went: leave the VIRMIDI pages
  if (m.mode == "virmidi" or m.mode == "confirm_virmidi") and not require('core/virmidi').configured() then
    if vm_poll_stop then vm_poll_stop() end
    m.mode = "type"
    m.len = #m.list
    m.pos = math.min(m.pos, m.len)
    if m.pos < 1 then m.pos = 1 end
  end
  -- serialosc is gone: leave its pages
  if not _menu.grid_note and (m.mode == "serialosc" or m.mode == "confirm_serialosc") then
    m.mode = "type"
    m.len = #m.list
    m.pos = math.min(m.pos, m.len)
    if m.pos < 1 then m.pos = 1 end
  end
end

-- words to lines no wider than `width` pixels, measured with the screen's own font (screen.text_extents); a word wider than the line is cut between characters
local function fits(t, width) return screen.text_extents(t) <= width end
local function wrap(text, width)
  width = width or 124
  local out = {}
  for para in (text .. "\n"):gmatch("(.-)\n") do
    local line = ""
    for word in para:gmatch("%S+") do
      local try = #line == 0 and word or (line .. " " .. word)
      if fits(try, width) then
        line = try
      else
        if #line > 0 then out[#out + 1] = line; line = "" end
        while not fits(word, width) and #word > 1 do
          local n = #word - 1
          while n > 1 and not fits(word:sub(1, n), width) do n = n - 1 end
          out[#out + 1] = word:sub(1, n)
          word = word:sub(n + 1)
        end
        line = word
      end
    end
    if #line > 0 then out[#out + 1] = line end
  end
  return out
end

function m.refresh()
  m.options = {
    midi = {"none"},
    grid = {"none"},
    arc = {"none"},
    hid = {"none"},
  }
  m.options["keyboard layout"] = {}

  -- create midi list
  for _, device in pairs(midi.devices) do
    table.insert(m.options.midi, device.name)
  end
  -- Linux desktop: a name is listed once (the same grid twice came from a device event that was treated as a new device: docs/port/KNOWN-ISSUES.md 31)
  local desktop = os.getenv("NORNS_PLATFORM") ~= nil
  local function add_unique(list, name)
    if desktop then
      for _, n in ipairs(list) do if n == name then return end end
    end
    table.insert(list, name)
  end
  for _, device in pairs(grid.devices) do
    add_unique(m.options.grid, device.name)
  end
  for _, device in pairs(arc.devices) do
    add_unique(m.options.arc, device.name)
  end
  for _, device in pairs(hid.devices) do
    table.insert(m.options.hid, device.name)
  end
  for layout, _ in pairs(keyboard.keymap) do
    table.insert(m.options["keyboard layout"], layout)
  end
  table.sort(m.options["keyboard layout"])
end

local function set_len_for_list()
  if m.section == "midi" then
    m.len = 16
  else
    m.len = 4
  end
end

local function check_and_rename(dev_type,pos,name)
  for i = 1,#dev_type.vports do
    if i ~= pos and dev_type.vports[i].name == name then
      dev_type.vports[i].name = "none"
    end
  end
end

m.key = function(n,z)
  if m.mode == "wingrid" then
    local page = require 'core/menu/gridwin'
    if page.key(n, z) == "back" then
      page.deinit()
      m.mode = "type"
      m.len = #m.list
      m.pos = #m.list - 1
    end
    _menu.redraw()
    return
  end
  if m.mode == "winmidi" then
    local page = require 'core/menu/midiwin'
    if page.key(n, z) == "back" then
      page.deinit()
      m.mode = "type"
      m.len = #m.list
      m.pos = #m.list
    end
    _menu.redraw()
    return
  end
  sync_list()
  if m.mode == "virmidi" then
    if z ~= 1 then return end
    local V = require 'core/virmidi'
    if n == 2 then
      if m.result then m.result = nil
      else m.mode = "type"; m.len = #m.list; m.pos = #m.list; vm_poll_stop() end
    elseif n == 3 then
      if V.wants_module(V.to()) and not V.loaded() then
        if V.load_status() ~= "running" then m.mode = "confirm_virmidi" end
      else
        m.result = m.result == nil and wrap(table.concat(V.permanent_lines(), "\n")) or nil
      end
    end
    _menu.redraw()
    return
  elseif m.mode == "confirm_virmidi" then
    if z ~= 1 then return end
    if n == 2 then
      m.mode = "virmidi"
    elseif n == 3 then
      require('core/virmidi').start_load()
      m.mode = "virmidi"
      vm_poll_start()
    end
    _menu.redraw()
    return
  end
  if m.mode == "serialosc" then
    if z ~= 1 then return end
    if n == 2 then m.mode = "type"; m.len = #m.list; m.pos = #m.list; m.result = nil
    elseif n == 3 then m.mode = "confirm_serialosc" end
    _menu.redraw()
    return
  elseif m.mode == "confirm_serialosc" then
    if z ~= 1 then return end
    if n == 2 then
      m.mode = "serialosc"
    elseif n == 3 then
      local S = require 'core/serialosc_stop'
      if S.stop() then m.result = wrap("STOPPED. UNPLUG AND REPLUG THE GRID.")
      else m.result = wrap("FAILED: NEEDS A PASSWORD. TYPE IN A TERMINAL:\n" .. S.COMMAND) end
      m.mode = "serialosc"
    end
    _menu.redraw()
    return
  end
  if m.mode == "type" then
    if n==2 and z==1 then
      _menu.set_page("SYSTEM")
    elseif n==3 and z==1 then
      m.section = m.list[m.pos]
      if is_windows() and m.section == "midi routes" then
        m.mode = "winmidi"
        require('core/menu/midiwin').init()
        _menu.redraw()
        return
      elseif is_windows() and m.section == "grid ports" then
        m.mode = "wingrid"
        require('core/menu/gridwin').init()
        _menu.redraw()
        return
      elseif m.section == "virmidi" then
        m.mode = "virmidi"
        m.result = nil
        if require('core/virmidi').load_status() == "running" then vm_poll_start() end -- a load that was started before: keep watching it
        _menu.redraw()
        return
      elseif m.section == "serialosc" then
        m.mode = "serialosc"
        m.result = nil
        _menu.redraw()
        return
      elseif m.section == "keyboard layout" then
        m.refresh()
        m.mode = "select"
        m.len = #m.options[m.section]
        m.pos = tabutil.key(m.options["keyboard layout"], keyboard.selected_map)
      else
        m.mode = "list"
        set_len_for_list()
        m.pos = 1
      end
      _menu.redraw()
    end
  elseif m.mode == "list" then
    if n==2 and z==1 then
      m.mode = "type"
      m.len = #m.list
      m.pos = 1
      _menu.redraw()
    elseif n==3 and z==1 then
      m.last_pos = m.pos
      m.refresh()
      m.mode = "select"
      m.setpos = m.pos
      m.len = #m.options[m.section]
      m.pos = 1
      _menu.redraw()
    end
  elseif m.mode == "select" then
    if n==2 and z==1 then
      if m.section == "keyboard layout" then
        m.mode = "type"
        m.len = #m.list
        m.pos = 1
      else
        m.mode = "list"
        set_len_for_list()
        m.pos = m.last_pos
      end
      _menu.redraw()
    elseif n==3 and z==1 then
      local s = m.options[m.section][m.pos]
      local target_mode = "list"
      if m.section == "midi" then
        midi.vports[m.setpos].name = s
        check_and_rename(midi,m.setpos,s)
        midi.update_devices()
      elseif m.section == "grid" then
        grid.vports[m.setpos].name = s
        check_and_rename(grid,m.setpos,s)
        grid.update_devices()
      elseif m.section == "arc" then
        arc.vports[m.setpos].name = s
        check_and_rename(arc,m.setpos,s)
        arc.update_devices()
      elseif m.section == "hid" then
        hid.vports[m.setpos].name = s
        check_and_rename(hid,m.setpos,s)
        hid.update_devices()
      elseif m.section == "keyboard layout" then
        keyboard.set_map(s, true)
        target_mode = "type"
      end
      if target_mode == "type" then
        m.mode = "type"
        m.len = #m.list
        m.pos = 1
      else
        m.mode = "list"
        set_len_for_list()
        m.pos = m.last_pos
      end
      _menu.redraw()
    end
  end
end

m.enc = function(n,delta)
  if m.mode == "wingrid" then
    require('core/menu/gridwin').enc(n, delta)
    return
  end
  if m.mode == "winmidi" then
    require('core/menu/midiwin').enc(n, delta)
    return
  end
  sync_list()
  if m.mode == "serialosc" or m.mode == "confirm_serialosc" or m.mode == "virmidi" or m.mode == "confirm_virmidi" then return end
  if n==2 then
    prev_pos = m.pos
    m.pos = util.clamp(m.pos + delta, 1, m.len)
    if prev_pos ~= m.pos then
      _menu.redraw()
    end
  end
end

local function redraw_select(do_show_all_if_fit, do_uppercase)
  screen.clear()

  if do_show_all_if_fit==nil then do_show_all_if_fit = true end
  if do_uppercase==nil then do_uppercase = false end
  local len = tabutil.count(m.options[m.section])

  if do_show_all_if_fit and len <= 6 then --  -> no scroll
    for i=1,len do
      local line = m.options[m.section][i]
      if do_uppercase then line = string.upper(line) end
      screen.level(i==m.pos and 15 or 4)
      screen.move(20,10*i)
      screen.text(clip(line, 107))
    end
  else --  -> scroll & selected item is always at pos 3
    for i=1,6 do
      if (i > 2 - m.pos + 1) and (i < m.len - m.pos + 3 + 1) then
        local line = m.options[m.section][i+m.pos-2 - 1]
        if do_uppercase then line = string.upper(line) end
        screen.level(i==3 and 15 or 4)
        screen.move(20,10*i)
        screen.text(clip(line, 107))
      end
    end
  end

  screen.update()
end

local function redraw_serialosc()
  screen.clear()
  screen.aa(0)
  screen.level(15)
  screen.move(0, 8)
  screen.text("SERIALOSC")
  local S = require 'core/serialosc_stop'
  if m.mode == "confirm_serialosc" then
    local l = {"STOP SERIALOSC?", "OTHER PROGRAMS LOSE", "THEIR GRIDS UNTIL IT", "STARTS AGAIN."}
    for i, t in ipairs(l) do screen.level(i == 1 and 15 or 6); screen.move(0, 8 + 10 * i); screen.text(t) end
    screen.level(4); screen.move(0, 62); screen.text("K3 YES  K2 NO")
  else
    local y = 18
    screen.level(6)
    for _, t in ipairs(m.result or wrap(_menu.grid_note or "")) do
      if y <= 52 then screen.move(0, y); screen.text(t); y = y + 8 end
    end
    screen.level(4); screen.move(0, 62); screen.text("K3 STOP IT  K2 BACK")
  end
  screen.update()
end

-- the page does not wait for a key press: while a load runs (the password dialog is a person, pkexec's answer comes later) a poll of one second looks at the module and the answer of the command,
-- and redraws when something changed (loaded, failed, why); it stops when the load is not running any more and when the page is left
local vm_signature = nil
local function vm_signature_now()
  local V = require 'core/virmidi'
  local count = 0
  if _norns and _norns.alsa_midi_link then count = _norns.alsa_midi_link() end
  local hw = V.hw_entries and V.hw_entries() or {}
  return table.concat({tostring(V.loaded()), tostring(V.load_status()), tostring(V.load_detail and V.load_detail() or ""), tostring(count), table.concat(hw, ",")}, "|")
end
vm_poll_stop = function()
  if _menu.timer and _menu.timer.stop then _menu.timer:stop() end
end
local function vm_poll_tick()
  local sig = vm_signature_now()
  if sig ~= vm_signature then
    vm_signature = sig
    _menu.redraw()
  end
  local V = require 'core/virmidi'
  if V.load_status() ~= "running" then vm_poll_stop() end
end
vm_poll_start = function()
  if not desktop or not _menu.timer then return end
  vm_signature = vm_signature_now()
  _menu.timer.time = 1
  _menu.timer.count = -1
  _menu.timer.event = vm_poll_tick
  _menu.timer:start()
end

-- SYSTEM > DEVICES > VIRMIDI: Reaper reads raw MIDI only; the kernel's virtual MIDI card (snd-virmidi) is the bridge. what is the state, the question before loading it (no terminal: the desktop's password dialog), the Reaper
-- entry to enable, and how to keep it after a reboot
local function redraw_virmidi()
  local V = require 'core/virmidi'
  screen.clear()
  screen.aa(0)
  screen.level(15)
  screen.move(0, 8)
  screen.text("VIRMIDI")
  local function put(text, level, y0)
    local y = y0 or 18
    screen.level(level or 6)
    for _, t in ipairs(wrap(text)) do
      if y <= 52 then screen.move(0, y); screen.text(t); y = y + 8 end
    end
    return y
  end
  if m.mode == "confirm_virmidi" then
    put("LOAD SND-VIRMIDI?\nIT NEEDS ADMIN RIGHTS: A PASSWORD DIALOG MAY OPEN.", 8)
    screen.level(4); screen.move(0, 62); screen.text("K3 YES  K2 NO")
    screen.update()
    return
  end
  local to = V.to()
  local count, names = 0, ""
  if _norns.alsa_midi_link then count, names = _norns.alsa_midi_link() end
  local keys = "K2 BACK"
  if m.result then
    put(table.concat(m.result, "\n"))
    keys = "K2 BACK"
  elseif V.wants_module(to) and not V.loaded() then
    local st = V.load_status()
    if st == "running" then
      put("WAITING FOR THE PASSWORD DIALOG...")
      keys = "K2 BACK"
    elseif st == "failed" then
      -- what happened in plain words (the dialog was closed, nobody to ask, no answer in time ...) and the command to type instead
      put(table.concat(V.failure_lines(V.load_detail()), "\n"), 8)
      keys = "K3 TRY AGAIN  K2 BACK"
    else
      put(table.concat(V.guide_lines(), "\n"))
      keys = "K3 LOAD IT  K2 BACK"
    end
  else
    local y = 18
    if V.wants_module(to) then y = put("LOADED.", 8, y) end
    if count > 0 then
      local first = names:match("^[^,]+") or names
      y = put("CONNECTED: " .. names, 6, y)
      y = put("REAPER: ENABLE " .. V.reaper_entry(first), 15, y)
      local hw = V.reaper_hw(first)
      if hw then y = put("(" .. hw .. ")", 6, y) end
    else
      y = put("WAITING FOR A PORT NAMED " .. to, 6, y)
      -- loaded, and not connected yet: the entry for Reaper follows the card and its device index (hw:VirMIDI,<device>)
      local hw = V.hw_entries and V.hw_entries() or {}
      if V.wants_module(to) and #hw > 0 then y = put("REAPER: ENABLE " .. hw[1], 15, y) end
    end
    keys = "K3 KEEP AFTER REBOOT  K2 BACK"
  end
  screen.level(4); screen.move(0, 62); screen.text(clip(keys:sub(1, 25), 127))
  screen.update()
end

m.redraw = function()
  sync_list()
  if m.mode == "wingrid" then
    require('core/menu/gridwin').redraw()
    return
  end
  if m.mode == "winmidi" then
    require('core/menu/midiwin').redraw()
    return
  end
  if m.mode == "virmidi" or m.mode == "confirm_virmidi" then
    redraw_virmidi()
    return
  end
  if m.mode == "serialosc" or m.mode == "confirm_serialosc" then
    redraw_serialosc()
    return
  end
  if m.mode == "select" then
    local do_show_all_if_fit = false
    local do_uppercase = (m.section == "keyboard layout")
    redraw_select(do_show_all_if_fit, do_uppercase)
    return
  end

  local y_offset = 0
  if not (m.mode == "type")
    and not (m.section == "midi" and m.mode == "list")
    and (4<m.pos) then
    y_offset = 10*(4-m.pos)
  elseif m.mode ~= "type" then
    y_offset = 20
  end
  screen.clear()
  if m.mode == "list" then
    screen.move(0,10)
    screen.level(4)
    screen.text(string.upper(m.section))
    -- Linux: the optional MIDI auto-connect (audio.conf midi_in_from=), under the title of the MIDI list
    if m.section == "midi" and _norns.midi_in_status then
      local on, count, names = _norns.midi_in_status()
      if on then
        screen.move(0,20)
        screen.level(3)
        screen.text(clip("AUTO-LINK: " .. (count > 0 and (count .. " linked") or "none yet"), 127))
      end
    end
  end
  for i=1,m.len do
    screen.move(0,10*i+y_offset)
    if(i==m.pos) then
      screen.level(15)
    else
      screen.level(4)
    end
    if m.mode == "type" then
      screen.text(string.upper(list_label(m.list[i])) .. " >")
      if m.list[i] == "keyboard layout" then
        screen.move(127,10*i+y_offset)
        local used = screen.text_extents(string.upper(m.list[i]) .. " >") + 4
        screen.text_right(clip(string.upper(keyboard.selected_map), 127 - used))
      end
    elseif m.mode == "list" then
      if m.section == "midi" then
        for j = 1,4 do
          screen.move(0,10*j+20)
          if m.pos+(j-1) <= m.len then
            local line = m.pos+(j-1)..". "..midi.vports[m.pos+(j-1)].name
            if j == 1 then
              screen.level(15)
            else
              screen.level(3)
            end
            screen.text(clip(line, 127))
          end
        end
      elseif m.section == "grid" then
        screen.text(i..".")
        screen.move(8,10*i+y_offset)
        screen.text(clip(grid.vports[i].name, 119))
      elseif m.section == "arc" then
        screen.text(i..".")
        screen.move(8,10*i+y_offset)
        screen.text(clip(arc.vports[i].name, 119))
      elseif m.section == "hid" then
        screen.text(i..".")
        screen.move(8,10*i+y_offset)
        screen.text(clip(hid.vports[i].name, 119))
      end
    end
  end
  screen.update()
end

m.init = function()
  m.pos = 1
  m.mode = "type"
  m.result = nil
  sync_list()
  m.len = #m.list
end

m.deinit = function()
  if vm_poll_stop then vm_poll_stop() end
  if m.mode == "winmidi" then require('core/menu/midiwin').deinit() end
  if m.mode == "wingrid" then require('core/menu/gridwin').deinit() end
end

return m
