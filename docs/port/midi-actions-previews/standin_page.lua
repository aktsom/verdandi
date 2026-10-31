# STAND-IN pictures of docs/port/midi-actions-plan.md: run with linux/tests/norns_probe.sh (not part of the product or of run_all.sh)
#sleep 5
_menu.set_mode(true)
_menu.set_page("SYSTEM")
#sleep 1
dofile(os.getenv("NORNS_HOME") .. "/norns/docs/port/midi-actions-previews/draw_list.lua")
_menu.redraw = function() end
#sleep 1.5
#shot @home/actions-list.png
dofile(os.getenv("NORNS_HOME") .. "/norns/docs/port/midi-actions-previews/draw_walk.lua")
#sleep 1.5
#shot @home/actions-walk.png
#xdo key ctrl+q
#sleep 3
