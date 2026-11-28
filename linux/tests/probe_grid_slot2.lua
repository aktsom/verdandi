-- the virtual grid window, M45 (docs/port/phase-m45.md; run_all.sh, VERDANDI_TEST_HOOKS=1): the owner's case in the real program. a (test) real grid is in slot 2, slot 1 is "none", and
-- something draws a picture on that real grid (the way a mod does). the virtual grid window is opened and closed five times: the slots stay as the owner set them, and the picture on the real
-- grid is not touched by the switch (nothing is copied to it or from it: it is not in slot 1)
print("PROBE fake " .. tostring(_norns.test_fake_grid(true)))
#sleep 2
local R
for _, d in pairs(grid.devices) do R = d end
grid.vports[1].name = "none"
grid.vports[2].name = R.name
grid.vports[3].name = "none"
grid.vports[4].name = "none"
grid.update_devices()
R:all(0)
R:led(1, 1, 15)
R:led(3, 2, 9)
R:led(16, 8, 5)
R:refresh()
#sleep 1
print("PROBE slots start " .. grid.vports[1].name:sub(1, 7) .. "|" .. grid.vports[2].name:sub(1, 7) .. "|" .. grid.vports[3].name .. "|" .. grid.vports[4].name .. " real on port " .. tostring(R.port))
print("PROBE realleds start " .. select(2, _norns.test_fake_grid_leds()))
_norns.grid_window("grid")
#sleep 2.5
print("PROBE round 1 open slots " .. grid.vports[1].name:sub(1, 7) .. "|" .. grid.vports[2].name:sub(1, 7) .. "|" .. grid.vports[3].name .. "|" .. grid.vports[4].name .. " real on port " .. tostring(R.port) .. " virt " .. tostring(select(1, _norns.test_vgrid_leds())))
print("PROBE round 1 open realleds " .. select(2, _norns.test_fake_grid_leds()))
_norns.grid_window("grid")
#sleep 2.5
print("PROBE round 1 closed slots " .. grid.vports[1].name:sub(1, 7) .. "|" .. grid.vports[2].name:sub(1, 7) .. "|" .. grid.vports[3].name .. "|" .. grid.vports[4].name .. " real on port " .. tostring(R.port) .. " virt " .. tostring(select(1, _norns.test_vgrid_leds())))
print("PROBE round 1 closed realleds " .. select(2, _norns.test_fake_grid_leds()))
_norns.grid_window("grid")
#sleep 2.5
print("PROBE round 2 open slots " .. grid.vports[1].name:sub(1, 7) .. "|" .. grid.vports[2].name:sub(1, 7) .. "|" .. grid.vports[3].name .. "|" .. grid.vports[4].name .. " real on port " .. tostring(R.port) .. " virt " .. tostring(select(1, _norns.test_vgrid_leds())))
print("PROBE round 2 open realleds " .. select(2, _norns.test_fake_grid_leds()))
_norns.grid_window("grid")
#sleep 2.5
print("PROBE round 2 closed slots " .. grid.vports[1].name:sub(1, 7) .. "|" .. grid.vports[2].name:sub(1, 7) .. "|" .. grid.vports[3].name .. "|" .. grid.vports[4].name .. " real on port " .. tostring(R.port) .. " virt " .. tostring(select(1, _norns.test_vgrid_leds())))
print("PROBE round 2 closed realleds " .. select(2, _norns.test_fake_grid_leds()))
_norns.grid_window("grid")
#sleep 2.5
print("PROBE round 3 open slots " .. grid.vports[1].name:sub(1, 7) .. "|" .. grid.vports[2].name:sub(1, 7) .. "|" .. grid.vports[3].name .. "|" .. grid.vports[4].name .. " real on port " .. tostring(R.port) .. " virt " .. tostring(select(1, _norns.test_vgrid_leds())))
print("PROBE round 3 open realleds " .. select(2, _norns.test_fake_grid_leds()))
_norns.grid_window("grid")
#sleep 2.5
print("PROBE round 3 closed slots " .. grid.vports[1].name:sub(1, 7) .. "|" .. grid.vports[2].name:sub(1, 7) .. "|" .. grid.vports[3].name .. "|" .. grid.vports[4].name .. " real on port " .. tostring(R.port) .. " virt " .. tostring(select(1, _norns.test_vgrid_leds())))
print("PROBE round 3 closed realleds " .. select(2, _norns.test_fake_grid_leds()))
_norns.grid_window("grid")
#sleep 2.5
print("PROBE round 4 open slots " .. grid.vports[1].name:sub(1, 7) .. "|" .. grid.vports[2].name:sub(1, 7) .. "|" .. grid.vports[3].name .. "|" .. grid.vports[4].name .. " real on port " .. tostring(R.port) .. " virt " .. tostring(select(1, _norns.test_vgrid_leds())))
print("PROBE round 4 open realleds " .. select(2, _norns.test_fake_grid_leds()))
_norns.grid_window("grid")
#sleep 2.5
print("PROBE round 4 closed slots " .. grid.vports[1].name:sub(1, 7) .. "|" .. grid.vports[2].name:sub(1, 7) .. "|" .. grid.vports[3].name .. "|" .. grid.vports[4].name .. " real on port " .. tostring(R.port) .. " virt " .. tostring(select(1, _norns.test_vgrid_leds())))
print("PROBE round 4 closed realleds " .. select(2, _norns.test_fake_grid_leds()))
_norns.grid_window("grid")
#sleep 2.5
print("PROBE round 5 open slots " .. grid.vports[1].name:sub(1, 7) .. "|" .. grid.vports[2].name:sub(1, 7) .. "|" .. grid.vports[3].name .. "|" .. grid.vports[4].name .. " real on port " .. tostring(R.port) .. " virt " .. tostring(select(1, _norns.test_vgrid_leds())))
print("PROBE round 5 open realleds " .. select(2, _norns.test_fake_grid_leds()))
_norns.grid_window("grid")
#sleep 2.5
print("PROBE round 5 closed slots " .. grid.vports[1].name:sub(1, 7) .. "|" .. grid.vports[2].name:sub(1, 7) .. "|" .. grid.vports[3].name .. "|" .. grid.vports[4].name .. " real on port " .. tostring(R.port) .. " virt " .. tostring(select(1, _norns.test_vgrid_leds())))
print("PROBE round 5 closed realleds " .. select(2, _norns.test_fake_grid_leds()))
print("PROBE grid slot2 done")
