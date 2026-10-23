-- script for linux/tests/probe_window.lua: draws, and reports every key, encoder, grid and arc event
engine.name = "PolyPerc"
g = grid.connect()
a = arc.connect()
function g.key(x, y, z) print("PROBE gridkey", x, y, z) end
function a.delta(n, d) print("PROBE arcdelta", n, d) end
function a.key(n, z) print("PROBE arckey", n, z) end
-- every Verdandi MIDI device is listened to: "Verdandi JACK in" (vport 1, always there on Linux: a DAW or a keyboard
-- through JACK MIDI) and "Verdandi keys" (the keys window, the next vport). vport 2 is connected whether or not the
-- keys window is open yet, so that it keeps working when the window is opened later
local function listen(n)
  local port = midi.connect(n)
  port.event = function(data)
    local d = midi.to_msg(data)
    print("PROBE midi", d.type, d.note, d.vel, d.ch, port.name)
  end
  return port
end
m = listen(2)
midi_ports = {}
for i = 1, 16 do
  local name = midi.vports[i].name
  if i ~= 2 and name ~= nil and name:find("^Verdandi") then midi_ports[i] = listen(i) end
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
