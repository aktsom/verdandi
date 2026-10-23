# the window under Xvfb 1280x800 (linux/tests/norns_probe.sh): mouse, keyboard, virtual grid and arc.
# coordinates are of the first screen the norns window shows there.
#sleep 5
norns.script.load("code/probe/window_probe.lua")
#sleep 3
#shot @home/window-device.png
# K2 with the mouse, E2 with the wheel
#xdo mousemove 753 626
#xdo mousedown 1
#sleep 0.3
#xdo mouseup 1
#xdo mousemove 832 505 click 4 click 4 click 4 click 4
#sleep 0.5
# the computer keyboard: 3 = K3, w = E1
#xdo search --name Verdandi windowfocus
#xdo keydown 3
#sleep 0.3
#xdo keyup 3
#xdo key --delay 40 w w w w w w
#sleep 0.5
_norns.grid_window("grid")
_norns.grid_window("arc")
#sleep 2
print("PROBE devices", g.device and g.device.name, a.device and a.device.name)
g:led(1, 1, 15)
g:refresh()
a:segment(1, 0, 3.14, 15)
a:refresh()
#sleep 0.5
#xdo search --name ^grid$ mousemove --window %1 60 60 mousedown 1
#sleep 0.3
#xdo mouseup 1
#xdo search --name ^arc$ mousemove --window %1 102 100 click 4 click 4 mousedown 3
#sleep 0.3
#xdo mouseup 3
#sleep 0.5
#shot @home/window-devices.png
print("PROBE window done")
