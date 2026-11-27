-- the virtual grid window at the next start (M41, run_all.sh): the saved rotation is put back (or, with a bad file, 0), and a click at the turned place reaches the script at the right key.
-- ROTATE is not pressed here. the device is the default 128 (16 x 8); VP_ROT says the rotation the window is expected to open with (the click is placed by it)
norns.script.load("code/probe/window_probe.lua")
#sleep 3
_norns.grid_window("grid")
#sleep 3
#sh $VP shape b0
#sh $VP key 16 8 $VP_ROT 1 0
#sh $VP shape b1
print("PROBE vgrid view2 done")
