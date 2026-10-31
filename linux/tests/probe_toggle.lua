# the virtual grid (F6), keys (F7) and arc (F8) windows under Xvfb 1280x800 with no window manager (run_all.sh, window_toggle_scenario): the norns window is set to 800 x 516 at 100,70 and must keep that size and
# position while the three windows open and close, again and again, also with the detached screen window open; every window toggles with its own key from the norns window and from its own window.
# the marks are made by detach_check.sh: geometry (<w>x<h>+<x>+<y>) of the norns window after each step, and the number of windows of each name.
#sleep 5
norns.script.load("code/probe/window_probe.lua")
#sleep 3
#xdo search --name ^Verdandi.Linux$ windowsize 800 516 windowmove 100 70
#sleep 1
#xdo search --name ^Verdandi.Linux$ windowfocus
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" geom base ^Verdandi.Linux$
#xdo search --name ^Verdandi.Linux$ windowfocus
#xdo key F6
#sleep 1.5
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" count grid_open1 ^grid$
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" geom grid_open1_main ^Verdandi.Linux$
#xdo search --name ^grid$ windowfocus
#xdo key F6
#sleep 1.5
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" count grid_closed1 ^grid$
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" geom grid_closed1_main ^Verdandi.Linux$
#xdo search --name ^Verdandi.Linux$ windowfocus
#xdo key F6
#sleep 1.5
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" count grid_open2 ^grid$
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" geom grid_open2_main ^Verdandi.Linux$
#xdo search --name ^Verdandi.Linux$ windowfocus
#xdo key F6
#sleep 1.5
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" count grid_closed2 ^grid$
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" geom grid_closed2_main ^Verdandi.Linux$
#xdo search --name ^Verdandi.Linux$ windowfocus
#xdo key F8
#sleep 1.5
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" count arc_open1 ^arc$
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" geom arc_open1_main ^Verdandi.Linux$
#xdo search --name ^arc$ windowfocus
#xdo key F8
#sleep 1.5
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" count arc_closed1 ^arc$
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" geom arc_closed1_main ^Verdandi.Linux$
#xdo search --name ^Verdandi.Linux$ windowfocus
#xdo key F8
#sleep 1.5
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" count arc_open2 ^arc$
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" geom arc_open2_main ^Verdandi.Linux$
#xdo search --name ^Verdandi.Linux$ windowfocus
#xdo key F8
#sleep 1.5
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" count arc_closed2 ^arc$
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" geom arc_closed2_main ^Verdandi.Linux$
#xdo search --name ^Verdandi.Linux$ windowfocus
#xdo key F7
#sleep 1.5
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" count keys_open1 ^keys$
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" geom keys_open1_main ^Verdandi.Linux$
#xdo search --name ^keys$ windowfocus
#xdo key F7
#sleep 1.5
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" count keys_closed1 ^keys$
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" geom keys_closed1_main ^Verdandi.Linux$
#xdo search --name ^Verdandi.Linux$ windowfocus
#xdo key F7
#sleep 1.5
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" count keys_open2 ^keys$
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" geom keys_open2_main ^Verdandi.Linux$
#xdo search --name ^Verdandi.Linux$ windowfocus
#xdo key F7
#sleep 1.5
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" count keys_closed2 ^keys$
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" geom keys_closed2_main ^Verdandi.Linux$
#xdo search --name ^Verdandi.Linux$ windowfocus
#xdo key F6
#sleep 1.2
#xdo key F7
#sleep 1.2
#xdo key F8
#sleep 1.2
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" count all_open_grid ^grid$
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" count all_open_arc ^arc$
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" count all_open_keys ^keys$
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" geom all_open_main ^Verdandi.Linux$
#xdo search --name ^keys$ windowfocus
#xdo key F7
#sleep 1.2
#xdo search --name ^grid$ windowfocus
#xdo key F6
#sleep 1.2
#xdo search --name ^arc$ windowfocus
#xdo key F8
#sleep 1.2
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" count all_closed_grid ^grid$
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" count all_closed_arc ^arc$
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" count all_closed_keys ^keys$
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" geom all_closed_main ^Verdandi.Linux$
#xdo search --name ^Verdandi.Linux$ windowfocus
#xdo key F9
#sleep 2
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" count detached ^Verdandi.screen$
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" geom detached_main ^Verdandi.Linux$
#xdo search --name ^Verdandi.Linux$ windowfocus
#xdo key F6
#sleep 1.5
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" count d_grid_open1 ^grid$
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" geom d_grid_open1_main ^Verdandi.Linux$
#xdo search --name ^grid$ windowfocus
#xdo key F6
#sleep 1.5
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" count d_grid_closed1 ^grid$
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" geom d_grid_closed1_main ^Verdandi.Linux$
#xdo search --name ^Verdandi.Linux$ windowfocus
#xdo key F6
#sleep 1.5
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" count d_grid_open2 ^grid$
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" geom d_grid_open2_main ^Verdandi.Linux$
#xdo search --name ^Verdandi.Linux$ windowfocus
#xdo key F6
#sleep 1.5
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" count d_grid_closed2 ^grid$
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" geom d_grid_closed2_main ^Verdandi.Linux$
#xdo search --name ^Verdandi.Linux$ windowfocus
#xdo key F8
#sleep 1.5
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" count d_arc_open1 ^arc$
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" geom d_arc_open1_main ^Verdandi.Linux$
#xdo search --name ^arc$ windowfocus
#xdo key F8
#sleep 1.5
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" count d_arc_closed1 ^arc$
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" geom d_arc_closed1_main ^Verdandi.Linux$
#xdo search --name ^Verdandi.Linux$ windowfocus
#xdo key F8
#sleep 1.5
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" count d_arc_open2 ^arc$
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" geom d_arc_open2_main ^Verdandi.Linux$
#xdo search --name ^Verdandi.Linux$ windowfocus
#xdo key F8
#sleep 1.5
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" count d_arc_closed2 ^arc$
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" geom d_arc_closed2_main ^Verdandi.Linux$
#xdo search --name ^Verdandi.Linux$ windowfocus
#xdo key F7
#sleep 1.5
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" count d_keys_open1 ^keys$
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" geom d_keys_open1_main ^Verdandi.Linux$
#xdo search --name ^keys$ windowfocus
#xdo key F7
#sleep 1.5
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" count d_keys_closed1 ^keys$
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" geom d_keys_closed1_main ^Verdandi.Linux$
#xdo search --name ^Verdandi.Linux$ windowfocus
#xdo key F7
#sleep 1.5
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" count d_keys_open2 ^keys$
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" geom d_keys_open2_main ^Verdandi.Linux$
#xdo search --name ^Verdandi.Linux$ windowfocus
#xdo key F7
#sleep 1.5
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" count d_keys_closed2 ^keys$
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" geom d_keys_closed2_main ^Verdandi.Linux$
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" count d_screen_still ^Verdandi.screen$
print("PROBE toggle done")
#sleep 1
#xdo key ctrl+q
#sleep 3
