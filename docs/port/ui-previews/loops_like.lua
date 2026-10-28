-- a stand-in for the loops page of Cheat Codes 2 (overview, "frame 1" of lib/main_menu.lua: screen_levels = 3, 1, 2, 15): the same levels in the same
-- roles: the title and the labels at level 3, the waveform at level 1, the start and end markers at level 3, the one bright line at 15
engine.name = "PolyPerc"
local wave = {}
for i = 1, 105 do
  local env = math.min(1, i / 6) * math.exp(-i / 60)
  wave[i] = math.floor((0.35 + 0.65 * math.abs(math.sin(i * 0.9) * math.cos(i * 0.23))) * env * 17 + 0.5)
end
function redraw()
  screen.clear()
  screen.level(3); screen.move(0, 10); screen.text("loops")
  screen.level(3); screen.move(0, 40); screen.text("L1")
  screen.level(1)
  for i, h in ipairs(wave) do
    screen.move(15 + i, 35 - h)
    screen.line_rel(0, 2 * h)
  end
  screen.stroke()
  screen.level(3)
  screen.move(30, 15); screen.line_rel(0, 40)
  screen.move(100, 15); screen.line_rel(0, 40)
  screen.stroke()
  screen.level(3); screen.move(0, 62); screen.text("pad 1")
  screen.level(15); screen.move(128, 62); screen.text_right("K3: rec")
  screen.level(3); screen.move(128, 10); screen.text_right("bank a")
  screen.update()
end
function init() redraw() end
