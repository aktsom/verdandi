-- STAND-IN for docs/port/midi-map-plan.md: the MIDI MAP page does not exist yet. This draws what the plan proposes with the real screen API
-- (real font, real levels, the real window and box) from a throw-away redraw function. Run: linux/tests/norns_probe.sh <this file>
#sleep 5
_menu.set_mode(true)
_menu.set_page("SYSTEM")
#sleep 1
dofile(os.getenv("NORNS_HOME") .. "/norns/docs/port/midi-map-previews/standin_draw.lua")
_menu.redraw()
_norns.show_control(2, 2, 1)
#sleep 2
#shot @home/standin.png
#xdo key ctrl+q
#sleep 3
