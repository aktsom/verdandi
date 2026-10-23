-- script for linux/tests/probe_window.lua: draws, and reports every key, encoder, grid and arc event
engine.name = "PolyPerc"
g = grid.connect()
a = arc.connect()
function g.key(x, y, z) print("PROBE gridkey", x, y, z) end
function a.delta(n, d) print("PROBE arcdelta", n, d) end
function a.key(n, z) print("PROBE arckey", n, z) end
m = midi.connect()
m.event = function(data)
  local d = midi.to_msg(data)
  print("PROBE midi", d.type, d.note, d.vel, d.ch)
end
function key(n, z) print("PROBE key", n, z) end
function enc(n, d) print("PROBE enc", n, d) end
function redraw()
  screen.clear()
  screen.level(15)
  screen.rect(4, 4, 40, 20)
  screen.fill()
  screen.update()
end
function init()
  redraw()
  print("PROBE window init")
end
