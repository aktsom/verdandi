-- test script (like awake): lights LEDs and keeps the grid handle
g = grid.connect()
function init()
  g:all(0)
  g:led(1, 1, 15)
  g:led(16, 8, 7)
  g:refresh()
end
function redraw() screen.clear(); screen.update() end
