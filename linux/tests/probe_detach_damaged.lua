# screen-window.conf with damaged values (run_all.sh, detach_scenario): defaults for those values, a line in the log for each, the rest of the file is used
#sleep 5
norns.script.load("code/probe/window_probe.lua")
#sleep 3
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" count damaged_windows '^Verdandi.screen$'
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" geom damaged_geom '^Verdandi.screen$'
#xdo search --name ^Verdandi.screen$ windowfocus
#xdo key ctrl+q
#sleep 4
