-- LEDs after norns ends (linux/tests/grid_exit_test.sh; docs/port/KNOWN-ISSUES.md 30): a script lights a virtual grid, then norns ends one way ($HOW: quit, close, term, hup, segv); the bytes written to the grid's port are logged
#sleep 2
_norns.grid_window("grid")
#sleep 2
norns.script.load("code/grid_a/grid_a.lua")
#sleep 3
#sh echo MARK exit >> "$WRITE_LOG"
#sh case "$HOW" in quit) xdotool search --name '^Verdandi.Linux$' windowfocus key ctrl+q ;; close) "$DC" close '^Verdandi.Linux$' ;; term) kill -TERM "$(pgrep -x norns | head -1)" ;; hup) kill -HUP "$(pgrep -x norns | head -1)" ;; segv) kill -SEGV "$(pgrep -x norns | head -1)" ;; esac
#sleep 5
#sh echo MARK end >> "$WRITE_LOG"
