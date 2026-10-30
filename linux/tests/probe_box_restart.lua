# the same home started again (run_all.sh, box_scenario): the look, the style and the hidden row are remembered
#sleep 5
norns.script.load("code/probe/window_probe.lua")
#sleep 3
#shot @home/restart.png
box = require 'core/box_settings'
print("PROBE restart", box.state.style, box.state.colours.box, box.state.preset, tostring(box.state.show_buttons))
print("PROBE box restart done")
#xdo key ctrl+q
#sleep 4
