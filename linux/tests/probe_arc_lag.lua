# the lag of the arc window after fast mapped turns (Windows 0.10.5, docs/port/phase-m14.md): the window logs "arc display: N turns, M draws, ... the last draw ended X ms after the last turn was sent"
# once a burst is over. run_all.sh runs this twice: VERDANDI_ARC_THROTTLE=0 (the old way, one full draw per turn) and the default (throttled). _norns.arc_turn is what a mapped encoder calls.
#sleep 5
norns.script.load("code/probe/window_probe.lua")
#sleep 3
_norns.grid_window("arc")
#sleep 2
print("PROBE lag start")
# 1: 1500 turns in a tight loop (the worst case: the queue fills faster than any window can be drawn)
for i = 1, 1500 do _norns.arc_turn(1 + i % 4, (i % 7 == 0) and -1 or 2) end print("PROBE lag burst sent")
#sleep 30
print("PROBE lag done")
