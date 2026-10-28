# the screen's look in the real window (docs/port/ui-settings-plan.md): ui.conf in the norns home (yellow, brightness 0.4, greys 0.5) is applied at start;
# the window, the screenshot of the right-click menu and the first frame of a gif must show the same colours (run_all.sh compares them)
#sleep 5
norns.script.load("code/probe/ui_look_probe.lua")
#sleep 3
#shot @home/ui-window.png
# Screenshot (menu opened at 300,300, 26 px rows, as in probe_menu.lua)
#xdo mousemove 300 300 click 3
#xdo mousemove 340 467 click 1
#sleep 1
# Record GIF, then stop it
#xdo mousemove 300 300 click 3
#xdo mousemove 340 493 click 1
#sleep 1.5
#xdo mousemove 300 300 click 3
#xdo mousemove 340 493 click 1
#sleep 2
print("PROBE ui_look done")
#xdo search --name Verdandi windowfocus
#xdo key ctrl+q
#sleep 4
