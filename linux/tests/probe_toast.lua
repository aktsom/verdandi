# the serialosc note in the real window (run_all.sh, toast_scenario; docs/port/KNOWN-ISSUES.md 33): the pill on the box and on the detached screen window, and the guide on the norns screen (SYSTEM > DEVICES > SERIALOSC), with the
# width of every line the page draws measured with the real font. captures: serialosc-note.png (default size, the toast), serialosc-devices.png (the guide), serialosc-screen.png (the screen window)
#sleep 5
norns.script.load("code/probe/window_probe.lua")
#sleep 3
metro[33]:stop() -- the 3 s poll of the notes would take the note away again (no serialosc here)
NOTE = "GRID: serialosc has this grid\nStop it: sudo systemctl stop serialosc.service\n(later: sudo systemctl start serialosc.service)"
_menu.grid_note = NOTE
_menu.show_note()
#sleep 1.5
#sh "$DC" cap '^Verdandi.Linux$' "$NORNS_HOME/serialosc-note.png"
widths = {}
real_text = screen.text
real_text_right = screen.text_right
screen.text = function(s) widths[#widths + 1] = screen.text_extents(s); return real_text(s) end
screen.text_right = function(s) widths[#widths + 1] = screen.text_extents(s); return real_text_right(s) end
_menu.set_mode(true)
_menu.set_page("DEVICES")
#sleep 1
for i = 1, 5 do _menu.enc(2, 1) end
_menu.redraw()
#sleep 0.5
print("PROBE devices list widest", math.max(table.unpack(widths)))
widths = {}
_menu.key(3, 1)
#sleep 1
_menu.redraw()
print("PROBE guide widest", math.max(table.unpack(widths)), #widths)
#sh "$DC" cap '^Verdandi.Linux$' "$NORNS_HOME/serialosc-devices.png"
widths = {}
_menu.key(3, 1)
#sleep 1
_menu.redraw()
print("PROBE question widest", math.max(table.unpack(widths)), #widths)
widths = {}
_menu.key(2, 1)
_menu.redraw()
print("PROBE guide again widest", math.max(table.unpack(widths)))
screen.text = real_text
screen.text_right = real_text_right
_menu.set_mode(false)
#xdo search --name ^Verdandi.Linux$ windowfocus
#xdo key F9
#sleep 2
_menu.show_note()
#sleep 1.5
#sh "$DC" cap '^Verdandi.screen$' "$NORNS_HOME/serialosc-screen.png"
#xdo key F9
#sleep 1
print("PROBE toast done")
#xdo key ctrl+q
#sleep 4
