-- STAND-IN page drawing for docs/port/midi-map-plan.md (real screen API, throw-away function); loaded by standin_page.lua
_menu.redraw = function()
  screen.clear()
  screen.aa(0)
  screen.font_face(1)
  screen.font_size(8)
  screen.level(15)
  screen.move(0, 8) screen.text("MIDI MAP")
  -- learn banner: inverted, so that it cannot be missed
  screen.rect(70, 1, 58, 9) screen.fill()
  screen.level(0)
  screen.move(99, 8) screen.text_center("LEARN E2")
  local rows = {
    {"E2", "MOVE A KNOB", true},
    {"E3", "CC23 ABS", false, "PUSH2 CH1"},
    {"K1", "-----", false},
    {"K2", "NOTE 36", false, "ANY"},
    {"K3", "CC85 >63", false, "ANY"},
  }
  for i, r in ipairs(rows) do
    local y = 10 + i * 9
    if r[3] then
      screen.level(15) screen.rect(0, y - 7, 128, 9) screen.fill()
      screen.level(0)
    else
      screen.level(i == 2 and 15 or 6)
    end
    screen.move(2, y) screen.text(r[1])
    screen.move(16, y) screen.text(r[2])
    if r[4] and not r[3] then screen.level(3) screen.move(126, y) screen.text_right(r[4]) end
  end
  screen.level(15) screen.move(0, 64) screen.text("K2 CANCEL")
  screen.level(3) screen.move(126, 64) screen.text_right("ESC")
  screen.update()
end
