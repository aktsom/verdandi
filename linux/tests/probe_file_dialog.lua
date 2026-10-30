# "Open the file dialog when a script loads a file" in the real window (run_all.sh, dialog_scenario; a stub zenity counts the dialogs and answers with a wav).
# the menu is opened at (300,300) and sits where the window lets it (see menu-off.png): Import files 160, Import folder 186, Copy samples 212, Open the file dialog 238 (the menu is taller since the box styles added items: it sits higher; the rows after "Show the page buttons" are 87 up from the old numbers)
#sleep 5
norns.script.load("code/probe/window_probe.lua")
fileselect = require "fileselect"
#sleep 3
# 1. off by default: a script's chooser is norns's own browser only
fileselect.enter("/tmp", function(p) print("PROBE fs result", p) end, "audio")
#sleep 2
print("PROBE browser up", fileselect.active)
#sh c=$(grep -c -- --file-selection "$NORNS_HOME/zenity.args" 2>/dev/null); echo "default_dialogs=${c:-0}" >> "$MARKS"
fileselect.path = nil; fileselect.exit()
#xdo mousemove 300 300 click 3
#sleep 0.6
#shot @home/menu-off.png
# 2. tick it in the menu
#xdo mousemove 340 238 click 1
#sleep 1
#sh grep -q '^file_dialog=1' "$NORNS_HOME/ui.conf" && echo "saved_on=yes" >> "$MARKS" || echo "saved_on=no" >> "$MARKS"
#xdo mousemove 300 300 click 3
#sleep 0.6
#shot @home/menu-on.png
#xdo key Escape
#sleep 0.5
fileselect.enter("/tmp", function(p) print("PROBE fs result", p) end, "audio")
#sleep 3
#sh c=$(grep -c -- --file-selection "$NORNS_HOME/zenity.args" 2>/dev/null); echo "ticked_dialogs=${c:-0}" >> "$MARKS"
print("PROBE browser after dialog", fileselect.active)
# 3. untick it: no dialog any more, at once
#xdo mousemove 300 300 click 3
#xdo mousemove 340 238 click 1
#sleep 1
#sh grep -q '^file_dialog=0' "$NORNS_HOME/ui.conf" && echo "saved_off=yes" >> "$MARKS" || echo "saved_off=no" >> "$MARKS"
fileselect.enter("/tmp", function(p) print("PROBE fs result", p) end, "audio")
#sleep 2
#sh c=$(grep -c -- --file-selection "$NORNS_HOME/zenity.args" 2>/dev/null); echo "unticked_dialogs=${c:-0}" >> "$MARKS"
fileselect.path = nil; fileselect.exit()
# 4. tick it again and leave it on for the restart
#xdo mousemove 300 300 click 3
#xdo mousemove 340 238 click 1
#sleep 1
print("PROBE file dialog done")
#xdo key ctrl+q
#sleep 4
