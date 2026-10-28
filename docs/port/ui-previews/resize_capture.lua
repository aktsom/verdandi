-- real norns, headless, on a big X screen: the window resized to several sizes (docs/port/ui-previews/make_previews.sh, "resizing")
#sleep 2
norns.script.load("code/uipreview/uipreview.lua")
#sleep 4
_menu.set_mode(true)
_menu.set_page("PARAMS")
#sleep 1
_norns.enc(2, -5)
#sleep 0.5
_norns.key(3, 1)
_norns.key(3, 0)
#sleep 1
_norns.enc(2, 2)
#sleep 1.5
#xdo mousemove 5 5
#xdo search --name ^Verdandi.Linux$ windowmove %1 0 0
#sleep 0.5
#xdo search --name ^Verdandi.Linux$ windowsize %1 595 397
#sleep 1.5
#shot @home/xs-60.png
#xdo search --name ^Verdandi.Linux$ windowsize %1 744 497
#sleep 1.5
#shot @home/xs-75.png
#xdo search --name ^Verdandi.Linux$ windowsize %1 794 530
#sleep 1.5
#shot @home/xs-80.png
#xdo search --name ^Verdandi.Linux$ windowsize %1 992 662
#sleep 1.5
#shot @home/xs-100.png
#xdo search --name ^Verdandi.Linux$ windowsize %1 1240 828
#sleep 1.5
#shot @home/xs-125.png
#xdo search --name ^Verdandi.Linux$ windowsize %1 1290 861
#sleep 1.5
#shot @home/xs-130.png
#xdo search --name ^Verdandi.Linux$ windowsize %1 1488 993
#sleep 1.5
#shot @home/xs-150.png
#xdo search --name ^Verdandi.Linux$ windowsize %1 1587 1059
#sleep 1.5
#shot @home/xs-160.png
#sh xdotool search --name '^Verdandi.Linux$' | head -1 | xargs -I{} xdotool getwindowgeometry --shell {} > "@home/geo-last.txt"
#sleep 1
