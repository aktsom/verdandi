# a second start of the launcher while norns runs, under Xvfb with no window manager (run_all.sh, second_start_scenario). another window (magenta, the whole display) is put
# in front of the box; the second start must bring the box to the front (and the screen window too when the screen is detached), start no second norns, show no dialog.
# the box is at 144,69 (992 x 662); the screen window is moved to 0,0 (695 x 367), so that (50,30) is the screen window only and (800,400) the box only.
#sleep 5
norns.script.load("code/probe/window_probe.lua")
#sleep 3
#sh bash "$NORNS_HOME/norns/linux/tests/second_start_check.sh" id main_id '^Verdandi.Linux$'
# A. docked, another window in front
#sh bash "$NORNS_HOME/norns/linux/tests/second_start_check.sh" cover-start
#sleep 1.5
#sh bash "$NORNS_HOME/norns/linux/tests/second_start_check.sh" cover-focus
#sleep 0.4
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" cap root "$NORNS_HOME/before-docked.png"
#sh bash "$NORNS_HOME/norns/linux/tests/second_start_check.sh" focus focus_before_docked
#sh bash "$NORNS_HOME/norns/linux/tests/second_start_check.sh" second docked
#sleep 1.5
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" cap root "$NORNS_HOME/after-docked.png"
#sh bash "$NORNS_HOME/norns/linux/tests/second_start_check.sh" focus focus_after_docked
#sh bash "$NORNS_HOME/norns/linux/tests/second_start_check.sh" files files_after_docked
#sh bash "$NORNS_HOME/norns/linux/tests/second_start_check.sh" cover-stop
#sleep 0.5
# B. the screen detached: both windows are raised
#xdo search --name ^Verdandi.Linux$ windowfocus
#xdo key F9
#sleep 2
#xdo search --name ^Verdandi.screen$ windowmove 0 0
#sleep 0.8
#sh bash "$NORNS_HOME/norns/linux/tests/second_start_check.sh" cover-start
#sleep 1.5
#sh bash "$NORNS_HOME/norns/linux/tests/second_start_check.sh" cover-focus
#sleep 0.4
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" cap root "$NORNS_HOME/before-detached.png"
#sh bash "$NORNS_HOME/norns/linux/tests/second_start_check.sh" second detached
#sleep 1.5
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" cap root "$NORNS_HOME/after-detached.png"
#sh bash "$NORNS_HOME/norns/linux/tests/second_start_check.sh" focus focus_after_detached
#sh bash "$NORNS_HOME/norns/linux/tests/second_start_check.sh" cover-stop
print("PROBE second start done")
# the end is a crash: norns is killed, nothing is cleaned up
#sh pkill -9 -x norns
#sleep 2
