# the same home, started again with file_dialog=1 in ui.conf (run_all.sh, dialog_scenario): the menu shows the tick without a click, and the dialog opens
#sleep 5
norns.script.load("code/probe/window_probe.lua")
fileselect = require "fileselect"
#sleep 3
#xdo mousemove 300 300 click 3
#sleep 0.6
#shot @home/menu-restart.png
#xdo key Escape
#sleep 0.5
fileselect.enter("/tmp", function(p) print("PROBE fs result", p) end, "audio")
#sleep 3
#sh c=$(grep -c -- --file-selection "$NORNS_HOME/zenity.args" 2>/dev/null); echo "restart_dialogs=${c:-0}" >> "$MARKS"
print("PROBE file dialog restart done")
#xdo key ctrl+q
#sleep 4
