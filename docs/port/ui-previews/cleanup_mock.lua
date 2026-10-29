-- a stand-in for the proposed SYSTEM > CLEAN UP page (docs/port/clean-layout.md section 3): the layout only, with example numbers; nothing here reads the disk
engine.name = "PolyPerc"
local rows = {
  {"DISABLED", "3 items", "14M"},
  {"LOGS", "5 runs", "2M"},
  {"CRASHES", "2", "0.1M"},
  {"SEEDED", "1 pack", "3.5M"},
  {"CACHE", "", "12M"},
}
function redraw()
  screen.clear()
  for i, r in ipairs(rows) do
    screen.level(i == 1 and 15 or 4)
    screen.move(0, 10 * i)
    screen.text(r[1])
    screen.move(98, 10 * i)
    screen.text_right(r[2])
    screen.move(127, 10 * i)
    screen.text_right(r[3])
  end
  screen.level(15)
  screen.move(0, 62)
  screen.text("REMOVE >90 DAYS")
  screen.move(127, 62)
  screen.text_right("5 items 9M")
  screen.update()
end
function init() redraw() end
