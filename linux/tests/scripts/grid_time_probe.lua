-- script for linux/tests/probe_vgrid_chord.lua (M43): reports every grid key with the time it arrived in the script (seconds, util.time), every grid.add with the size the script reads, and keeps a picture
-- of LEDs on port 1 that redraw() draws again on request (a script draws its LEDs from its own state)
engine.name = nil
g = grid.connect(1)
function g.key(x, y, z) print(string.format("PROBE gridkey %d %d %d %.4f", x, y, z, util.time())) end
function g.remove() print("PROBE gridremove port1") end
grid.add = function(dev)
  print("PROBE gridadd " .. dev.name .. " " .. tostring(g.cols) .. "x" .. tostring(g.rows) .. " port1=" .. tostring(g.device and g.device.name))
end
function draw()
  g:all(0)
  g:led(3, 3, 15)
  g:led(16, 8, 9)
  g:refresh()
end
function init() draw() end
