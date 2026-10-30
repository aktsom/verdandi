# after a restart: the pixel look is remembered (box.conf), the window draws it, the colours are the saved ones
#sleep 5
norns.script.load("code/probe/window_probe.lua")
#sleep 3
box = require "core/box_settings"
print("PROBE restart look", box.state.pixel_look, box.state.preset)
#shot @home/rt-restart.png
#xdo key ctrl+q
#sleep 3
print("PROBE retro restart done")
