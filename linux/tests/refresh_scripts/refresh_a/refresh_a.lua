-- test script: refresh() counts its calls and draws a frame when it is called (like eterna)
norns.REFRESH_COUNT = 0
local draw_frame = true
function refresh()
  norns.REFRESH_COUNT = norns.REFRESH_COUNT + 1
  if draw_frame then
    screen.clear()
    screen.move(10, 30)
    screen.text("refresh " .. norns.REFRESH_COUNT)
    screen.update()
  end
end
function redraw() draw_frame = true; refresh() end
function init() end
