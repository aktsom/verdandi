-- the virtual grid window, M43 (docs/port/phase-m43.md; run_all.sh, helper linux/tests/vgrid_pane_check.sh = $VP, VERDANDI_TEST_HOOKS=1): Ctrl stage and fire with the real mouse and keyboard, and the switch
-- between a (test) real grid and the virtual grid. every grid key is printed by the script with its time; "PROBE mark NAME" says where in the log an action was done
norns.script.load("code/probe/grid_time_probe.lua")
#sleep 3
-- a real grid (a second pseudo terminal listed like a real grid): the script is on it
print("PROBE fake " .. tostring(_norns.test_fake_grid(true)))
#sleep 2
draw()
#sleep 1
print("PROBE realleds " .. select(2, _norns.test_fake_grid_leds()))
print("PROBE port1 " .. tostring(grid.vports[1].device and grid.vports[1].device.name))
-- 1. open the virtual grid: it is the active grid at once; the picture is on it, the real grid is dark
_norns.grid_window("grid")
#sleep 3
print("PROBE port1 " .. tostring(grid.vports[1].device and grid.vports[1].device.name) .. " port2 " .. tostring(grid.vports[2].device and grid.vports[2].device.name))
print("PROBE virtleds " .. select(2, _norns.test_vgrid_leds()))
print("PROBE realleds " .. tostring(select(2, _norns.test_fake_grid_leds())))
print("PROBE mark switched-to-virtual")
-- 2. a plain click, then Ctrl stage and fire: four keys staged with Ctrl held, nothing is sent; Ctrl up: four key-downs in the same instant, the key-ups after the hold time
#sh $VP key 16 8 0 1 0
print("PROBE mark plain-click")
#sh $VP move 16 8 0 2 4
#sh $VP ctrl down
#sh $VP key 16 8 0 2 4
#sh $VP key 16 8 0 4 4
#sh $VP key 16 8 0 6 4
#sh $VP key 16 8 0 8 4
#sleep 0.5
print("PROBE mark staged")
#sh $VP ctrl up
#sleep 1.2
print("PROBE mark fired")
-- 3. a staged key taken out again: stage three, click one of them again (it goes out), fire: two key-downs
#sh $VP ctrl down
#sh $VP key 16 8 0 1 6
#sh $VP key 16 8 0 3 6
#sh $VP key 16 8 0 5 6
#sh $VP key 16 8 0 3 6
#sh $VP ctrl up
#sleep 1.2
print("PROBE mark fired-two")
-- 4. Esc clears what was staged and sends nothing
#sh $VP ctrl down
#sh $VP key 16 8 0 1 2
#sh $VP key 16 8 0 2 2
#sh $VP esc
#sh $VP ctrl up
#sleep 1
print("PROBE mark after-esc")
-- 5. focus lost while staging: nothing is sent
#sh $VP focus grid
#sh $VP ctrl down
#sh $VP key 16 8 0 9 2
#sh $VP focus main
#sleep 0.4
#sh $VP ctrl up
#sleep 1
print("PROBE mark after-focus-lost")
-- 6. a Shift-latched key stays down while a Ctrl chord fires: Shift+click the key, then stage and fire two others
#sh $VP focus grid
#sh $VP shift down
#sh $VP key 16 8 0 10 0
#sh $VP shift up
#sleep 0.5
print("PROBE mark latched")
#sh $VP ctrl down
#sh $VP key 16 8 0 11 0
#sh $VP key 16 8 0 12 0
#sh $VP ctrl up
#sleep 1.2
print("PROBE mark fired-with-latch")
#sh $VP esc
#sleep 0.5
print("PROBE mark latch-released")
-- 7. a key is held on the virtual grid when it is switched off (the window closes): the script hears the key-up, the real grid takes over and shows the picture, it is announced again
#sh $VP down 16 8 0 14 6
#sleep 0.4
print("PROBE mark held")
_norns.grid_window("grid")
#sleep 3
print("PROBE port1 " .. tostring(grid.vports[1].device and grid.vports[1].device.name) .. " port2 " .. tostring(grid.vports[2].device and grid.vports[2].device.name))
print("PROBE realleds " .. tostring(select(2, _norns.test_fake_grid_leds())))
print("PROBE mark switched-to-real")
_norns.test_fake_grid_key(0, 0, true)
_norns.test_fake_grid_key(0, 0, false)
#sleep 0.5
print("PROBE mark real-key")
-- 8. five more switches with the script running: the window opened and closed; every time the picture is on the grid that takes over and the ports are right
_norns.grid_window("grid")
#sleep 2.5
print("PROBE round 1 open port1 " .. tostring(grid.vports[1].device and grid.vports[1].device.name) .. " virt " .. tostring(select(1, _norns.test_vgrid_leds())) .. " real " .. tostring(select(1, _norns.test_fake_grid_leds())))
_norns.grid_window("grid")
#sleep 2.5
print("PROBE round 1 closed port1 " .. tostring(grid.vports[1].device and grid.vports[1].device.name) .. " virt " .. tostring(select(1, _norns.test_vgrid_leds())) .. " real " .. tostring(select(1, _norns.test_fake_grid_leds())))
_norns.grid_window("grid")
#sleep 2.5
print("PROBE round 2 open port1 " .. tostring(grid.vports[1].device and grid.vports[1].device.name) .. " virt " .. tostring(select(1, _norns.test_vgrid_leds())) .. " real " .. tostring(select(1, _norns.test_fake_grid_leds())))
_norns.grid_window("grid")
#sleep 2.5
print("PROBE round 2 closed port1 " .. tostring(grid.vports[1].device and grid.vports[1].device.name) .. " virt " .. tostring(select(1, _norns.test_vgrid_leds())) .. " real " .. tostring(select(1, _norns.test_fake_grid_leds())))
_norns.grid_window("grid")
#sleep 2.5
print("PROBE round 3 open port1 " .. tostring(grid.vports[1].device and grid.vports[1].device.name) .. " virt " .. tostring(select(1, _norns.test_vgrid_leds())) .. " real " .. tostring(select(1, _norns.test_fake_grid_leds())))
_norns.grid_window("grid")
#sleep 2.5
print("PROBE round 3 closed port1 " .. tostring(grid.vports[1].device and grid.vports[1].device.name) .. " virt " .. tostring(select(1, _norns.test_vgrid_leds())) .. " real " .. tostring(select(1, _norns.test_fake_grid_leds())))
_norns.grid_window("grid")
#sleep 2.5
print("PROBE round 4 open port1 " .. tostring(grid.vports[1].device and grid.vports[1].device.name) .. " virt " .. tostring(select(1, _norns.test_vgrid_leds())) .. " real " .. tostring(select(1, _norns.test_fake_grid_leds())))
_norns.grid_window("grid")
#sleep 2.5
print("PROBE round 4 closed port1 " .. tostring(grid.vports[1].device and grid.vports[1].device.name) .. " virt " .. tostring(select(1, _norns.test_vgrid_leds())) .. " real " .. tostring(select(1, _norns.test_fake_grid_leds())))
_norns.grid_window("grid")
#sleep 2.5
print("PROBE round 5 open port1 " .. tostring(grid.vports[1].device and grid.vports[1].device.name) .. " virt " .. tostring(select(1, _norns.test_vgrid_leds())) .. " real " .. tostring(select(1, _norns.test_fake_grid_leds())))
_norns.grid_window("grid")
#sleep 2.5
print("PROBE round 5 closed port1 " .. tostring(grid.vports[1].device and grid.vports[1].device.name) .. " virt " .. tostring(select(1, _norns.test_vgrid_leds())) .. " real " .. tostring(select(1, _norns.test_fake_grid_leds())))
print("PROBE mark rounds-done")
#sh $VP count n_end
print("PROBE vgrid chord done")
