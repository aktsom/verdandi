# mods in the real norns (docs/port/KNOWN-ISSUES.md item 17): dust/code/fakemod and badmod with lib/mod.lua, both enabled in dust/data/system.mods
#sleep 5
probe_mods = require 'core/mods'
print("PROBE mods loaded fakemod", probe_mods.is_loaded("fakemod"), "badmod", probe_mods.is_loaded("badmod"))
_menu.set_mode(true)
_menu.set_page("MODS")
print("PROBE mods page", table.concat(_menu.m["MODS"].list, ","))
#sleep 1
print("PROBE mods done")
