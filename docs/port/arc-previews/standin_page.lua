-- STAND-IN for docs/port/arc-plan.md: run with linux/tests/norns_probe.sh (not part of the product or of run_all.sh)
#sleep 5
_menu.set_mode(true)
_menu.set_page("SYSTEM")
#sleep 1
dofile(os.getenv("NORNS_HOME") .. "/norns/docs/port/arc-previews/standin_draw.lua")
#sleep 2
#shot @home/watch.png
#xdo key ctrl+q
#sleep 3
