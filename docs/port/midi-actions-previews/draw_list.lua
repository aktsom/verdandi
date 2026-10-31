-- STAND-IN for docs/port/midi-actions-plan.md: the ACTIONS list does not exist yet. Real screen API, real font and window; a throw-away function.
local rows = {
  {"MIX", "NOTE 36"}, {"TAPE", "NOTE 37"}, {"HOME", "NOTE 38"}, {"PARAMS", "NOTE 39"}, {"INPUT", "-----"},
}
screen.clear() screen.aa(0) screen.font_face(1) screen.font_size(8)
screen.level(15) screen.move(0, 8) screen.text("ACTIONS")
screen.level(4) screen.move(126, 8) screen.text_right("- PAGES -")
for i, r in ipairs(rows) do
  local y = 10 + i * 9
  if i == 2 then screen.level(15) screen.rect(0, y - 7, 128, 9) screen.fill() screen.level(0) else screen.level(i == 5 and 4 or 8) end
  screen.move(2, y) screen.text(r[1])
  screen.move(124, y) screen.text_right(r[2])
end
screen.level(15) screen.rect(126, 12, 2, 12) screen.fill()
screen.level(3) screen.move(0, 64) screen.text("K3 LEARN  E3< CLEAR  E3> MORE")
screen.update()
