# the detachable screen window under Xvfb 1280x800 with no window manager (run_all.sh, detach_scenario; docs/port/detach-plan.md). ui.conf is yellow, so the colours of
# both windows are tinted. there is no window manager: nothing moves a window except this script, so every window is put where it is wanted.
# the box is at 144,69 (992 x 662 points); a stub zenity records the dialogs. checks are made by run_all.sh from the pictures and marks written here.
#sleep 5
norns.script.load("code/probe/window_probe.lua")
#sleep 3
#xdo search --name ^Verdandi.Linux$ windowfocus
#sh D="$NORNS_HOME/norns/linux/tests/detach_check.sh"; bash "$D" count windows_start '^Verdandi.screen$'
# the screenshot of the docked screen (Ctrl+Shift+S in the box): the exact picture, 4 times as large
#xdo key ctrl+shift+s
#sleep 1.5
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" newshot "$NORNS_HOME/shot-docked.png"
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" cap '^Verdandi.Linux$' "$NORNS_HOME/box-docked.png"
# a GIF of the docked screen: Record GIF in the right-click menu (the 8th row), 1.5 seconds, stop
#xdo mousemove 300 300 click 3
#sleep 0.6
#xdo mousemove 340 473 click 1
#sleep 1.8
#xdo mousemove 300 300 click 3
#sleep 0.6
#xdo mousemove 340 473 click 1
#sleep 1.5
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" newgif "$NORNS_HOME/gif-docked.gif"
# 1. F9 in the box: the screen is detached
#xdo key F9
#sleep 2
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" count windows_detached '^Verdandi.screen$'
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" geom screen_default '^Verdandi.screen$'
#xdo search --name ^Verdandi.screen$ windowmove 0 0
#sleep 0.8
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" cap '^Verdandi.screen$' "$NORNS_HOME/screen-default.png"
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" cap '^Verdandi.Linux$' "$NORNS_HOME/box-detached.png"
# 2. the keyboard in the screen window: 2 is K2 as in the box (a mouse click and wheel over the picture are not keys or encoders)
#xdo search --name ^Verdandi.screen$ windowraise windowfocus
#sleep 0.4
#xdo keydown 2
#sleep 0.3
#xdo keyup 2
#sleep 0.3
#xdo search --name ^Verdandi.screen$ mousemove --window %1 300 160 click 1 click 4 click 4 click 5
#sleep 0.5
# F6: the virtual grid opens from the screen window and a cell press reaches the script; the screen is detached the whole time
#xdo key F6
#sleep 2
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" count grid_open '^grid$'
#xdo search --name ^grid$ mousemove --window %1 60 60 mousedown 1
#sleep 0.3
#xdo mouseup 1
#sleep 0.5
# the screen window hidden (unmapped): the grid and the virtual keys keep working
#xdo search --name ^Verdandi.screen$ windowunmap
#sleep 0.5
#xdo search --name ^grid$ mousemove --window %1 60 60 mousedown 1
#sleep 0.3
#xdo mouseup 1
_norns.grid_window("keys")
#sleep 1.5
#xdo search --name ^keys$ windowfocus
#xdo keydown d
#sleep 0.3
#xdo keyup d
#sleep 0.5
_norns.grid_window("keys")
#sleep 0.5
#xdo search --name ^Verdandi.screen$ windowmap
#sleep 1
#xdo search --name ^Verdandi.screen$ windowfocus
#xdo key F6
#sleep 1
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" count grid_closed '^grid$'
# the same GIF while the screen is detached (the menu is the box's)
#xdo search --name ^Verdandi.Linux$ windowraise windowfocus
#xdo mousemove 300 300 click 3
#sleep 0.6
#xdo mousemove 340 473 click 1
#sleep 1.8
#xdo mousemove 300 300 click 3
#sleep 0.6
#xdo mousemove 340 473 click 1
#sleep 1.5
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" newgif "$NORNS_HOME/gif-detached.gif"
#sleep 4
# 3. the picture at several sizes, before anything changes what the script shows: an in-between size (700 x 400), a whole scale (8x: 1112 x 587 with its margin), and a big window
#    (9x: 1251 x 660, about what fullscreen draws; with no window manager here SDL's own fullscreen cannot change the size of the X window, that is checked by the saved state below)
#xdo search --name ^Verdandi.screen$ windowsize 700 400
#sleep 1.2
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" cap '^Verdandi.screen$' "$NORNS_HOME/screen-700.png"
#xdo search --name ^Verdandi.screen$ windowsize 1112 587
#sleep 1.2
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" cap '^Verdandi.screen$' "$NORNS_HOME/screen-1024.png"
#xdo search --name ^Verdandi.screen$ windowsize 1251 660
#sleep 1.5
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" cap '^Verdandi.screen$' "$NORNS_HOME/screen-big.png"
#xdo search --name ^Verdandi.screen$ windowsize 695 367
#sleep 1
# 4. shortcuts from the screen window: Ctrl+Shift+S (the same picture as docked), then Ctrl+O (the import dialog: it changes what the script shows afterwards)
#xdo search --name ^Verdandi.screen$ windowfocus
#xdo key ctrl+shift+s
#sleep 1.5
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" newshot "$NORNS_HOME/shot-detached.png"
#xdo key ctrl+o
#sleep 2
# 5. F11 is fullscreen and back, Shift+F11 the frame (the state file says so; with no window manager the X window itself does not change)
#xdo key F11
#sleep 1.5
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" conf conf_fs_on
#xdo key F11
#sleep 1.5
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" conf conf_fs_off
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" geom screen_back '^Verdandi.screen$'
#xdo key shift+F11
#sleep 0.8
# 6. F10 in the screen window opens the box's menu in the box
#xdo key F10
#sleep 1
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" cap '^Verdandi.Linux$' "$NORNS_HOME/box-menu.png"
#xdo key Escape
#sleep 0.6
# 7. the placeholder in the box brings the screen back
#xdo search --name ^Verdandi.screen$ windowmove 0 0
#sleep 0.5
#xdo mousemove 474 532 click 1
#sleep 1.5
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" count windows_after_placeholder '^Verdandi.screen$'
# 8. F9 from the box detaches again; then the screen window's close button re-docks
#xdo search --name ^Verdandi.Linux$ windowfocus
#xdo key F9
#sleep 1.5
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" count windows_after_f9 '^Verdandi.screen$'
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" close '^Verdandi.screen$'
#sleep 1.5
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" count windows_after_close '^Verdandi.screen$'
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" alive alive_after_close
# 8b. the menu item "Screen in its own window" (the 12th row of the right-click menu) detaches, F9 from the box brings it back
#xdo search --name ^Verdandi.Linux$ windowfocus
#xdo mousemove 300 300 click 3
#sleep 0.6
#xdo mousemove 340 586 click 1
#sleep 1.5
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" count windows_after_menu '^Verdandi.screen$'
#xdo search --name ^Verdandi.Linux$ windowfocus
#xdo key F9
#sleep 1.5
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" count windows_after_menu_off '^Verdandi.screen$'
# 9. detached again with F9 (from the box), the state is saved, then the box's close button quits norns although the screen window is open
#xdo search --name ^Verdandi.Linux$ windowfocus
#xdo key F9
#sleep 2
#xdo search --name ^Verdandi.screen$ windowsize 1024 512
#xdo search --name ^Verdandi.screen$ windowmove 100 100
#sleep 1.5
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" geom screen_before_quit '^Verdandi.screen$'
print("PROBE detach done")
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" close '^Verdandi.Linux$'
#sleep 4
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" alive alive_after_box_close
#sh bash "$NORNS_HOME/norns/linux/tests/detach_check.sh" conf conf_after_quit
