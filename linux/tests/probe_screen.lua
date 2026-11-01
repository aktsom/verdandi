# the SCREEN page in the real window (run_all.sh): one capture of the page with a saved preset of his own in use. docs/port/KNOWN-ISSUES.md / STATUS.md
#sleep 5
norns.script.load("code/probe/window_probe.lua")
#sleep 3
ui = require 'core/ui_settings'
ui.select_preset("YELLOW")
ui.set_custom("FF8800")
ui.save_preset("Amber")
_menu.set_mode(true)
_menu.set_page("UI")
#sleep 1
_menu.redraw()
#sleep 0.5
print("PROBE screen rows", table.concat(require("core/menu/ui").rows(), ","))
#sh "$DC" cap '^Verdandi.Linux$' "$NORNS_HOME/screen-page.png"
print("PROBE screen done")
