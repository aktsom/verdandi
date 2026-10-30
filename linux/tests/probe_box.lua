# the box styles in the real window (run_all.sh, box_scenario; docs/port/box-style-plan.md). the home starts with box.conf: pixel, the DARK look, the row shown.
# the window is 992 x 662 (the design size), centred on the 1280 x 800 screen of Xvfb: a layout point (u, v) is the screen pixel (160 + u, 85 + v). the menu is opened with F10 and the keyboard: Down x4 = "Show the page buttons"
#sleep 5
norns.script.load("code/probe/window_probe.lua")
#sleep 3
# 1. the pixel style as configured
#shot @home/pix-shown.png
# 2. hide the row with the menu item; the setting is saved
#xdo key F10
#sleep 0.5
#xdo key Down Down Down Down Return
#sleep 1
#shot @home/pix-hidden.png
#sh grep -q '^show_buttons=0' "$NORNS_HOME/box.conf" && echo "saved_hidden=yes" >> "$MARKS" || echo "saved_hidden=no" >> "$MARKS"
# 3. a click where MIX was does nothing (a page button would open the MIX page: menu mode); F1 (a page key) still does
#xdo mousemove 231 141 click 1
#sleep 0.5
print("PROBE click on the hidden MIX, menu mode", tostring(_menu.mode))
#xdo key F1
#sleep 0.8
print("PROBE F1 with the row hidden, menu mode", tostring(_menu.mode))
#xdo key F5
#sleep 0.5
print("PROBE F5 back, menu mode", tostring(_menu.mode))
# 4. Ctrl+M mutes with the row hidden: the chip shows, the output level is off; Ctrl+M again unmutes
print("PROBE output level before", tostring(params:get("output_level")))
#xdo key ctrl+m
#sleep 1
print("PROBE output level muted", tostring(params:get("output_level")))
#shot @home/pix-muted.png
#xdo key ctrl+m
#sleep 1
print("PROBE output level unmuted", tostring(params:get("output_level")))
#shot @home/pix-unmuted.png
# 5. the menu item mutes too (the third group: Open maiden, Open the manual, Mute): by its row in the menu
#xdo key F10
#sleep 0.5
#shot @home/menu-box.png
#xdo key Escape
#sleep 0.5
# 6. the colours work for the aluminium style: STYLE aluminium, a blue box (the row stays hidden: the restart shows it)
box = require 'core/box_settings'
box.set_style("aluminium")
box.set_part("box", "3b6ea8")
#sleep 1
#shot @home/alu-blue.png
print("PROBE box.conf", box.state.style, box.state.colours.box, box.state.preset, box.label())
print("PROBE box done")
#xdo key ctrl+q
#sleep 4
