-- the virtual grid window under Xvfb (M41, docs/port/phase-m41.md; run_all.sh, helper linux/tests/vgrid_pane_check.sh = $VP): ROTATE, the saved rotation, the size switch while turned, shift multi-press.
-- the script is the window probe's: it prints every grid key as "PROBE gridkey x y z". the default grid is a 128 (16 x 8). markers "PROBE mark NAME" say where in the log an action was done.
norns.script.load("code/probe/window_probe.lua")
#sleep 3
_norns.grid_window("grid")
#sleep 2
#sh $VP count n_open
#sh $VP shape r0
-- 1. a plain click at rotation 0: the key (1,0)
#sh $VP key 16 8 0 1 0
print("PROBE mark clicked-r0")
-- 2. ROTATE: 90, 180, 270, 0, then 90 again, a click at each
#sh $VP button 16 8 0 4
#sh $VP shape r1
#sh $VP key 16 8 1 3 2
#sh $VP button 16 8 1 4
#sh $VP shape r2
#sh $VP key 16 8 2 12 5
#sh $VP button 16 8 2 4
#sh $VP shape r3
#sh $VP key 16 8 3 7 6
#sh $VP button 16 8 3 4
#sh $VP shape r0b
#sh $VP key 16 8 0 0 7
#sh $VP button 16 8 0 4
#sh $VP shape r1b
print("PROBE mark rotated-to-1")
-- 3. the size switch while turned (64: an 8 x 8, 128 again): the rotation stays
#sh $VP button 16 8 1 1
#sleep 1
#sleep 1
#sh $VP shape s64
#sh $VP key 8 8 1 2 3
#sh $VP button 8 8 1 2
#sleep 1
#sleep 1
#sh $VP shape s128
#sh $VP key 16 8 1 5 1
-- 4. shift multi-press at rotation 1: collect four keys (two clicks and a drag), nothing is sent; shift up: four key-downs
#sh $VP focus grid
#sh $VP move 16 8 1 2 2
#sh $VP shift down
#sh $VP key 16 8 1 2 2
#sh $VP key 16 8 1 3 2
#sh $VP down 16 8 1 4 2
#sh $VP move 16 8 1 5 2
#sh $VP up 16 8 1 5 2
print("PROBE mark before-shift-up")
#sleep 0.5
#sh $VP shift up
#sleep 1
print("PROBE mark after-shift-up")
-- the keys stay held: Esc lets them go in one burst
#sh $VP esc
#sleep 1
print("PROBE mark after-esc")
-- 5. a chord that the next plain click lets go
#sh $VP shift down
#sh $VP key 16 8 1 1 1
#sh $VP key 16 8 1 2 1
#sh $VP shift up
#sleep 0.6
print("PROBE mark chord-2")
#sh $VP key 16 8 1 7 7
print("PROBE mark after-plain-click")
-- 6. keys pending, the focus goes to another window, shift is let go there: nothing is sent
#sh $VP focus grid
#sh $VP shift down
#sh $VP key 16 8 1 6 3
#sh $VP focus main
#sleep 0.5
#sh $VP shift up
#sleep 0.8
print("PROBE mark after-focus-lost")
-- 7. plain behaviour is the same: a plain drag plays the keys one after the other
#sh $VP focus grid
#sh $VP down 16 8 1 8 4
#sh $VP move 16 8 1 9 4
#sh $VP up 16 8 1 9 4
#sleep 0.5
print("PROBE mark after-plain-drag")
#sh $VP shape end
print("PROBE vgrid view done")
