-- script for linux/tests/probe_rapid_load.lua: uses the grid, the arc and a MIDI device, says when it has started
engine.name = "PolyPerc"
g = grid.connect()
a = arc.connect()
m = midi.connect(1)
function g.key(x, y, z) end
function a.delta(n, d) end
function init()
  print("PROBE init a")
  g:all(0); g:led(1, 1, 15); g:refresh()
end
function redraw() screen.clear(); screen.level(15); screen.move(4, 20); screen.text("rapid a"); screen.update() end
