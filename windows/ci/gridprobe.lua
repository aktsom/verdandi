-- gridprobe.lua: a script for the CI check of the quit (windows/ci/maiden_probe.py, VERDANDI_PROBE=quitgrid). it lights every LED of two grids and the arc thirty times a second, like a script that keeps drawing
local gs = {grid.connect(1), grid.connect(2)}
local a = arc.connect()
local m
GP = {frames = 0, ready = false}

function init()
  m = metro.init(function()
    for _, g in ipairs(gs) do g:all(15); g:refresh() end
    a:all(15); a:refresh()
    GP.frames = GP.frames + 1
  end, 1 / 30, -1)
  m:start()
  GP.ready = true
end

function cleanup() if m then m:stop() end end

function redraw()
  screen.clear()
  screen.move(0, 10)
  screen.text("grid probe")
  screen.update()
end
