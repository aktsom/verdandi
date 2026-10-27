-- real norns, headless: the PARAMS menu page and the parameter list of a script with parameters. for each: the oled image (128x64, as the
-- screen backend has it) and the whole X screen with the real window
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
_norns.screen_export_png("@home/oled-params.png")
#xdo mousemove 5 5
#sleep 0.5
#shot @home/xscreen-params.png
_norns.enc(2, -5)
#sleep 0.5
_norns.key(3, 1)
_norns.key(3, 0)
#sleep 1
_norns.enc(2, 2)
#sleep 1.5
_norns.screen_export_png("@home/oled-edit.png")
#sleep 0.5
#shot @home/xscreen-edit.png
#sh xdotool search --name '^Verdandi Linux$' | head -1 | xargs -I{} xdotool getwindowgeometry --shell {} > "@home/window-geometry.txt"
#sleep 1
