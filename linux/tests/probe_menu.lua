# the in-window menu and file dialogs under Xvfb 1280x800 (run_all.sh sets NORNS_PICKER=zenity and a stub
# zenity on PATH that answers with a wav file). item positions: menu opened at (300,300), 26 px rows; the menu is taller since the box styles and sits against the top of the window: Import files 160, Screenshot 360, Record GIF 386
#sleep 5
norns.script.load("code/probe/window_probe.lua")
#sleep 3
_norns.file_chosen = function(p) print("PROBE chosen", p) end
# right button: the menu
#xdo mousemove 300 300 click 3
#sleep 0.4
#shot @home/menu-open.png
# Screenshot
#xdo mousemove 340 360 click 1
#sleep 1
# Record GIF, then stop it
#xdo mousemove 300 300 click 3
#xdo mousemove 340 386 click 1
#sleep 1.5
#xdo mousemove 300 300 click 3
#xdo mousemove 340 386 click 1
#sleep 2
# Import files... (the stub answers with a wav)
#xdo mousemove 300 300 click 3
#xdo mousemove 340 160 click 1
#sleep 2
# a script's file dialog (lua fileselect)
_norns.choose_file("/tmp")
#sleep 2
# the keyboard: F10 opens, Escape closes
#xdo search --name Verdandi windowfocus
#xdo key F10
#sleep 0.4
#shot @home/menu-keys.png
#xdo key Escape
#sleep 0.4
print("PROBE menu done")
# Ctrl+Q ends norns by itself
#xdo key ctrl+q
#sleep 4
#sh if pgrep -x norns > /dev/null; then echo "norns still running" >> "$MARKS"; else echo "norns gone" >> "$MARKS"; fi
