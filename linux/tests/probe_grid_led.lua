-- the LED data that reaches a grid's serial port (linux/tests/grid_led_test.sh); the virtual grid is a pty that libmonome writes to like a real grid
#sleep 2
_norns.grid_window("grid")
#sleep 2
print("PROBE vport", grid.vports[1].name, grid.vports[1].device ~= nil, grid.vports[1].rows, grid.vports[1].cols)
#sh echo MARK script_a >> "$WRITE_LOG"
norns.script.load("code/grid_a/grid_a.lua")
#sleep 3
#sh echo MARK script_change >> "$WRITE_LOG"
norns.script.load("code/grid_b/grid_b.lua")
#sleep 3
#sh echo MARK repl_led >> "$WRITE_LOG"
g = grid.connect(); g:all(0); g:led(1, 1, 15); g:refresh()
#sleep 1
#sh echo MARK repl_all >> "$WRITE_LOG"
g:all(0); g:refresh()
#sleep 1
#sh echo MARK end >> "$WRITE_LOG"
