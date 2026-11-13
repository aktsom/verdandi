local m = {
  pos = 1,
  list = {"DEVICES > ", "WIFI >", "MODS >", "SETTINGS >", "RESTART", "UPDATE"},
  pages = {"DEVICES", "WIFI", "MODS", "SETTINGS", "RESTART", "UPDATE"}
}

-- on a computer (NORNS_PLATFORM set by the launcher) the OS owns wifi, updates and the
-- password, there is no battery and the display settings drive the oled chip: of
-- SETTINGS only RESET is left, so it moves up here. AUDIO picks the audio device, SCREEN the look of the screen (brightness, colour, contrast; page id UI), THEME the look of the box (style, five colours, saved looks; page id BOX), MIDI MAP the MIDI controls of E1-E3 and K1-K3 (docs/port/midi-map-plan.md; page id MIDIMAP), CLEAN UP what Verdandi keeps in the home (logs, disabled/, cache)
if os.getenv("NORNS_PLATFORM") ~= nil then
  m.list = {"DEVICES > ", "AUDIO >", "MODS >", "SCREEN >", "THEME >", "MIDI MAP >", "CLEAN UP >", "RESET", "RESTART"}
  m.pages = {"DEVICES", "AUDIO", "MODS", "UI", "BOX", "MIDIMAP", "CLEANUP", "RESET", "RESTART"}
end

-- Windows build (norns.exe): EXTRA FOLDERS, folders anywhere on the computer shown in the file browser as [ext] (docs/port/phase-m8.md)
if os.getenv("NORNS_PLATFORM") ~= nil and _norns.ext_list ~= nil then
  table.insert(m.list, 7, "EXTRA FOLDERS >")
  table.insert(m.pages, 7, "EXTRA")
end

m.key = function(n,z)
  if n==2 and z==1 then
    _menu.set_page("HOME")
  elseif n==3 and z==1 then
    _menu.set_page(m.pages[m.pos])
  end
end

m.enc = function(n,delta)
  if n==2 then
    m.pos = util.clamp(m.pos + delta, 1, #m.list)
    _menu.redraw()
  end
end

m.redraw = function()
  screen.clear()
  for i=1,6 do
    if (i > 3 - m.pos) and (i < #m.list - m.pos + 4) then
      screen.move(0,10*i)
      local line = m.list[i+m.pos-3]
      if(i==3) then
        screen.level(15)
      else
        screen.level(4)
      end
      screen.text(line)
    end
  end
  -- the build that runs (Windows: "0.2.0 4c82066"), at the top while the list leaves that line free
  local build = os.getenv("VERDANDI_BUILD")
  if build and build ~= "" and m.pos <= 2 then
    screen.level(2)
    screen.move(127,10)
    screen.text_right(build)
  end
  screen.update()
end

m.init = norns.none
m.deinit = norns.none

return m
