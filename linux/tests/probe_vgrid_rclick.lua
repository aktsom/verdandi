-- the virtual grid window, M46 (docs/port/phase-m46.md; run_all.sh, helper linux/tests/vgrid_pane_check.sh = $VP, VERDANDI_TEST_HOOKS=1): the RIGHT mouse button latches a key down. every grid key the script gets
-- is printed with "PROBE gridkey x y z time". device key (x,y) = 0-based, the script's coordinates are 1-based
norns.script.load("code/probe/grid_time_probe.lua")
#sleep 3
_norns.grid_window("grid")
#sleep 3
print("PROBE mark start")
-- 1. one right click: the key goes down and STAYS down after the button is released
#sh $VP rclick 16 8 0 4 3
#sleep 0.5
print("PROBE mark rclick-1")
-- 2. a second right click on the same key lets it go (one key-up)
#sh $VP rclick 16 8 0 4 3
#sleep 0.5
print("PROBE mark rclick-2")
-- 3. two keys latched with the right button (a chord by hand), a plain left click elsewhere does not touch them, a left click ON a latched key lets it go
#sh $VP rclick 16 8 0 6 3
#sh $VP rclick 16 8 0 8 3
#sleep 0.3
print("PROBE mark two-latched")
#sh $VP key 16 8 0 12 6 0
#sleep 0.3
print("PROBE mark plain-left-elsewhere")
#sh $VP key 16 8 0 6 3 0
#sleep 0.3
print("PROBE mark left-on-latched")
#sh $VP rclick 16 8 0 8 3
#sleep 0.3
print("PROBE mark right-unlatch-last")
-- 4. a key held by the Shift latch (M41) and a right click on it: it lets go once, and the plain left click that would have let it go afterwards sends no second key-up
#sh $VP shift down
#sh $VP key 16 8 0 10 2 shift
#sh $VP shift up
#sleep 0.5
print("PROBE mark shift-latched")
#sh $VP rclick 16 8 0 10 2
#sleep 0.4
print("PROBE mark right-on-shift-latched")
#sh $VP key 16 8 0 14 7 0
#sleep 0.4
print("PROBE mark plain-left-after")
-- 5. Ctrl held: the right button still latches (the chord staging is the left button's)
#sh $VP ctrl down
#sh $VP rclick 16 8 0 3 5
#sh $VP ctrl up
#sleep 0.4
print("PROBE mark right-with-ctrl")
#sh $VP rclick 16 8 0 3 5
#sleep 0.4
print("PROBE mark right-with-ctrl-off")
print("PROBE vgrid rclick done")
