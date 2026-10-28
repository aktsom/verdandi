-- script for linux/tests/probe_ui_look.lua: three rectangles at levels 15, 4 and 1 and a text at level 3, nothing else moves
engine.name = "PolyPerc"
function redraw()
  screen.clear()
  screen.level(15); screen.rect(4, 4, 40, 20); screen.fill()
  screen.level(4); screen.rect(50, 4, 40, 20); screen.fill()
  screen.level(1); screen.rect(96, 4, 28, 20); screen.fill()
  screen.level(3); screen.move(4, 44); screen.text("level three"); screen.update()
end
function init() redraw() print("PROBE ui_look init") end
