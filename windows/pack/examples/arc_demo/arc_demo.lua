-- arc_demo: four values, one on each ring of an arc (the virtual one or a real one). turn a ring: its value changes and its LEDs follow;
-- press a ring (the right mouse button on the virtual arc): its value jumps back to the middle. E3 sets how many arc ticks make a full turn of a value.
-- written for Verdandi's arc check; nothing in it is special: it uses the same calls as any norns arc script (arc.connect, a.delta, a.key, a:segment, a:refresh).
local a = arc.connect()
local value = {0.5, 0.5, 0.5, 0.5} -- 0 to 1
local last = {0, 0, 0, 0}          -- the last delta of each ring, for the screen
local ticks = 1024                 -- arc ticks for the whole range

local function draw_ring(r)
  local tau = math.pi * 2
  local to = value[r] * tau
  a:segment(r, 0, to > 0.001 and to or 0.001, 12)
end

local function leds()
  a:all(0)
  for r = 1, 4 do draw_ring(r) end
  a:refresh()
end

function init()
  a.delta = function(n, d)
    value[n] = util.clamp(value[n] + d / ticks, 0, 1)
    last[n] = d
    leds()
    redraw()
  end
  a.key = function(n, z)
    if z == 1 then value[n] = 0.5; leds(); redraw() end
  end
  leds()
end

function enc(n, d)
  if n == 3 then ticks = util.clamp(ticks + d * 64, 128, 4096); redraw() end
end

function redraw()
  screen.clear()
  screen.level(15)
  screen.move(0, 8)
  screen.text("arc demo")
  for r = 1, 4 do
    screen.level(10)
    screen.move(0, 8 + r * 10)
    screen.text(string.format("ring %d  %.3f  (%+d)", r, value[r], last[r]))
  end
  screen.level(4)
  screen.move(0, 62)
  screen.text("E3 ticks per range: " .. ticks)
  screen.update()
end
