-- the visible names SCREEN (the page UI) and THEME (the page BOX) (docs/port/colour-picker-plan.md): the SYSTEM list, the manual and RUN-ON-LAPTOP.md say them, the page ids, the aliases and the saved files
-- keep working as they are, the device's SYSTEM page is as before. run from the repo root:  lua5.3 linux/tests/rename_test.lua
package.path = "lua/?.lua;lua/core/?.lua;lua/lib/?.lua;" .. package.path
local fails = 0
local function check(ok, what) if not ok then fails = fails + 1; print("FAIL " .. what) end end
local function slurp(p) local h = assert(io.open(p)); local c = h:read("a"); h:close(); return c end

norns = {none = function() end}
local getenv = os.getenv
local function system_with(platform)
  os.getenv = function(k) if k == "NORNS_PLATFORM" then return platform end return getenv(k) end
  local m = dofile("lua/core/menu/system.lua")
  os.getenv = getenv
  return m
end
local c = system_with("linux")
check(table.concat(c.list, "|"):find("SCREEN >", 1, true) and table.concat(c.list, "|"):find("THEME >", 1, true), "the computer's SYSTEM list says SCREEN and THEME")
check(not table.concat(c.list, "|"):find("UI >", 1, true) and not table.concat(c.list, "|"):find("BOX >", 1, true), "and no longer UI or BOX")
check(table.concat(c.pages, ",") == "DEVICES,AUDIO,MODS,UI,BOX,MIDIMAP,CLEANUP,RESET,RESTART", "the page ids are the old ones")
local d = system_with(nil)
check(table.concat(d.pages, ",") == "DEVICES,WIFI,MODS,SETTINGS,RESTART,UPDATE", "the device's SYSTEM page is as before")
-- the order: SCREEN then THEME, in the list and the ids
check(c.list[4] == "SCREEN >" and c.list[5] == "THEME >" and c.pages[4] == "UI" and c.pages[5] == "BOX", "THEME is below SCREEN and they match their pages")
check(c.list[3] == "MODS >" and c.pages[3] == "MODS", "MODS is directly below AUDIO")
check(table.concat(c.list, "|") == "DEVICES > |AUDIO >|MODS >|SCREEN >|THEME >|MIDI MAP >|CLEAN UP >|RESET|RESTART", "the list: " .. table.concat(c.list, "|"))

local menu = slurp("lua/core/menu.lua")
check(menu:find('m["SCREEN"] = m["UI"]', 1, true) and menu:find('m["THEME"] = m["BOX"]', 1, true), "the ids SCREEN and THEME open the same pages")
check(menu:find('NORNS_PLATFORM', 1, true) ~= nil, "(they are registered with the computer pages only)")

-- the files keep their names
local ui = require 'core/ui_settings'
check(ui.PATH:match("ui%.conf$") ~= nil, "ui.conf is still the file of SCREEN")
package.loaded["core/keyboard"] = nil
_path = {keyboard_layout = "/nonexistent"}
local box = require "core/box_settings"
check(box.PATH:match("box%.conf$") ~= nil and box.DIR:match("box%-presets/$") ~= nil, "box.conf and box-presets/ are still the files of THEME")

-- the manual and RUN-ON-LAPTOP.md use the new names
local manual = slurp("linux/manual/manual.html")
check(manual:find("SYSTEM &gt; SCREEN", 1, true) and manual:find("SYSTEM &gt; THEME", 1, true), "the manual says SYSTEM > SCREEN and SYSTEM > THEME")
check(not manual:find("SYSTEM &gt; UI", 1, true) and not manual:find("SYSTEM &gt; BOX", 1, true), "and not SYSTEM > UI or SYSTEM > BOX")
local run = slurp("docs/port/RUN-ON-LAPTOP.md")
check(run:find("SYSTEM > SCREEN", 1, true) and run:find("SYSTEM > THEME", 1, true), "RUN-ON-LAPTOP.md says SYSTEM > SCREEN and SYSTEM > THEME")
check(not run:find("%*%*SYSTEM > UI%*%*") and not run:find("%*%*SYSTEM > BOX%*%*"), "and not SYSTEM > UI or BOX as page names")
-- the pages' own messages and comments
check(slurp("lua/core/menu/box.lua"):find("THEME", 1, true) ~= nil and slurp("lua/core/menu/ui.lua"):find("SCREEN", 1, true) ~= nil, "the pages call themselves THEME and SCREEN")
if fails == 0 then print("rename_test: all passed") end
os.exit(fails == 0 and 0 or 1)
