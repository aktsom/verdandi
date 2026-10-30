# the pixel looks in the real window (run_all.sh, retro_scenario; docs/port/retro-look-plan.md). the home starts with box.conf: pixel style, the DARK look, pixel_look=retro. the THEME page is open on its
# PIXEL LOOK row; each look is picked with E3 (live in the window, saved), a picture is taken of each, then RETRO in the COLOUR look, a live colour change in the picker with RETRO, and 16-BIT after a restart
#sleep 5
norns.script.load("code/probe/window_probe.lua")
#sleep 3
_menu.set_mode(true)
_menu.set_page("BOX")
#sleep 1
page = require "core/menu/box"
box = require "core/box_settings"
pk = require "core/menu/picker"
col = require "core/colour"
page.pos = 2
_menu.redraw()
print("PROBE start look", box.state.pixel_look)
#sleep 2
#shot @home/rt-retro.png
page.enc(3, -1)
#sleep 2
print("PROBE look after E3 left", box.state.pixel_look)
#shot @home/rt-pixel.png
page.enc(3, 2)
#sleep 2
print("PROBE look after E3 right x2", box.state.pixel_look)
#shot @home/rt-8bit.png
page.enc(3, 1)
#sleep 2
print("PROBE look after E3 right", box.state.pixel_look)
#shot @home/rt-16bit.png
#sh grep -q '^pixel_look=16-bit' "$NORNS_HOME/box.conf" && echo "saved_16bit=yes" >> "$MARKS" || echo "saved_16bit=no" >> "$MARKS"
page.enc(3, -2)
#sleep 1
box.select_look("COLOUR")
page.init()
page.pos = 2
_menu.redraw()
#sleep 2
print("PROBE colour look", box.state.pixel_look, box.state.preset)
#shot @home/rt-retro-colour.png
page.pos = 5
page.key(3, 1)
for i = 1, 6 do pk.enc(3, 1) end
#sleep 2
print("PROBE picker live", col.value_hex(pk.val), box.state.pixel_look)
#shot @home/rt-picker-live.png
pk.key(2, 1)
#sleep 1
page.pos = 2
page.enc(3, 1)
#sleep 1
print("PROBE before restart", box.state.pixel_look)
#xdo key ctrl+q
#sleep 3
print("PROBE retro done")
