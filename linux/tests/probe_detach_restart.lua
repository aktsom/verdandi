# the same home started again with screen-window.conf saying detached=1 and a place and size (run_all.sh, detach_scenario): the screen window is there at once,
# the box shows the placeholder, and the window is where it was. then it is brought back and the state is saved as docked
#sleep 5
norns.script.load("code/probe/window_probe.lua")
#sleep 3
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" count restart_windows '^Verdandi.screen$'
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" geom restart_geom '^Verdandi.screen$'
#xdo search --name ^Verdandi.screen$ windowmove 1200 780
#sleep 0.6
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" cap '^Verdandi.Linux$' "$NORNS_HOME/restart-box.png"
#xdo search --name ^Verdandi.screen$ windowmove 100 100
#sleep 0.4
#xdo search --name ^Verdandi.screen$ windowfocus
#xdo key F9
#sleep 1.5
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" count restart_docked '^Verdandi.screen$'
#xdo search --name ^Verdandi.Linux$ windowfocus
#xdo key ctrl+q
#sleep 4
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" conf restart_conf
