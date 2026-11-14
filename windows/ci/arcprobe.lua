-- arcprobe.lua: a small script for the CI check of the virtual arc (windows/ci/maiden_probe.py, VERDANDI_PROBE=arc). it draws on the four rings of the arc and counts what the arc sends it,
-- the way a script from a normal install does (arc.connect(), a.delta, a.key, a:led, a:segment, a:refresh). ARCP is read from the console afterwards.
local a = arc.connect()
ARCP = {sum = {0, 0, 0, 0}, msgs = {0, 0, 0, 0}, keys = {}, name = "none"}

function init()
  ARCP.name = a.name or "none"
  a.delta = function(n, d)
    ARCP.sum[n] = ARCP.sum[n] + d
    ARCP.msgs[n] = ARCP.msgs[n] + 1
  end
  a.key = function(n, z) ARCP.keys[#ARCP.keys + 1] = n .. ":" .. z end
  a:all(0)
  for r = 1, 4 do a:segment(r, 0, r * math.pi / 2, 15) end -- ring r is lit r quarters of a turn from the top, clockwise
  a:led(1, 1, 15)
  a:refresh()
  ARCP.ready = true
end

function redraw()
  screen.clear()
  screen.move(0, 10)
  screen.text("arc probe")
  screen.update()
end
