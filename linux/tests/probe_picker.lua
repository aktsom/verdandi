# the colour picker in the real window (run_all.sh, picker_scenario; docs/port/colour-picker-plan.md). the home starts with box.conf: pixel, the DARK look. K3 on the KEYS row opens the picker; the hue and
# the saturation are changed with E3 (the box is drawn with the new colour while the picker is open and no file is written); K2 gives the old colour back; the second time K3 keeps it (one write)
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
page.pos = 4
_menu.redraw()
#sleep 1
#shot @home/pk-before.png
#sh cp "$NORNS_HOME/box.conf" "$NORNS_HOME/box.before"
page.key(3, 1)
#sleep 1
print("PROBE picker open", tostring(pk.active), _menu.page)
#shot @home/pk-open.png
#sh cmp -s "$NORNS_HOME/box.conf" "$NORNS_HOME/box.before" && echo "conf_same_open=yes" >> "$MARKS" || echo "conf_same_open=no" >> "$MARKS"
for i = 1, 6 do pk.enc(3, 1) end
pk.enc(2, 1)
for i = 1, 8 do pk.enc(3, 1) end
#sleep 2
print("PROBE picker live", col.value_hex(pk.val))
#shot @home/pk-live.png
#sh cmp -s "$NORNS_HOME/box.conf" "$NORNS_HOME/box.before" && echo "conf_same_live=yes" >> "$MARKS" || echo "conf_same_live=no" >> "$MARKS"
pk.key(2, 1)
#sleep 2
print("PROBE picker cancelled", tostring(pk.active), _menu.page, box.state.colours.keys)
#shot @home/pk-cancel.png
#sh cmp -s "$NORNS_HOME/box.conf" "$NORNS_HOME/box.before" && echo "conf_same_cancel=yes" >> "$MARKS" || echo "conf_same_cancel=no" >> "$MARKS"
page.key(3, 1)
for i = 1, 4 do pk.enc(3, 1) end
print("PROBE picker keep", col.value_hex(pk.val))
pk.key(3, 1)
#sleep 2
print("PROBE picker kept", _menu.page, box.state.colours.keys)
#shot @home/pk-kept.png
#xdo key ctrl+q
#sleep 3
print("PROBE picker done")
