# the PARAMS page in the real window (make_ui_pictures.sh)
#sleep 2
norns.script.load("code/uipreview/uipreview.lua")
#sleep 4
_menu.set_mode(true)
_menu.set_page("PARAMS")
#sleep 1
_norns.enc(2, -5)
#sleep 1
_norns.enc(2, 1)
#sleep 1.5
#xdo mousemove 5 5
#sleep 0.5
#shot @home/window.png
#xdo search --name Verdandi windowfocus
#xdo key ctrl+q
#sleep 4
