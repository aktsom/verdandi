-- SYSTEM > EXT FOLDERS (lua/core/menu/extra.lua) with a fake _norns.ext_*: rows, marks for a missing folder, ADD FOLDER opens the picker, the answer is added, K3 on a folder only asks, K3 again removes, K2 cancels
-- (nothing is removed without the second K3), the warning says the files are NOT deleted. run from the repo root: lua5.3 linux/tests/extra_folders_page_test.lua
package.path = "lua/?.lua;lua/lib/?.lua;lua/core/?.lua;" .. package.path
local fails = 0
local function check(c, what) if not c then fails = fails + 1; print("FAIL " .. what) end end
local drawn = {}
screen = setmetatable({}, {__index = function() return function() end end})
screen.text_extents = function(s) return #s * 5 end
screen.clear = function() drawn = {} end
screen.text = function(s) drawn[#drawn + 1] = s end
screen.text_right = function(s) drawn[#drawn + 1] = s end
local function shown(s) for _, t in ipairs(drawn) do if t:find(s, 1, true) then return true end end return false end
util = {clamp = function(x, a, b) return math.max(a, math.min(b, x)) end}
local redraws, page_now = 0, "EXTRA"
_menu = {page = "EXTRA", mode = true, timer = {start = function() end, stop = function() end}, redraw = function() redraws = redraws + 1 end,
  set_page = function(p) page_now = p end, set_mode = function() end}
local list = {
  {name = "[ext] Drums", path = "D:\\Samples\\Drums", state = "ok"},
  {name = "[ext] Loops", path = "E:\\Loops", state = "missing"},
}
local removed, picked = {}, 0
_norns = {
  ext_list = function() local c = {} for i, v in ipairs(list) do c[i] = v end return c end,
  ext_add = function(p) list[#list + 1] = {name = "[ext] New", path = p, state = "ok"}; return true, "Added [ext] New.", "[ext] New" end,
  ext_remove = function(n) removed[#removed + 1] = n; for i, v in ipairs(list) do if v.name == n then table.remove(list, i) break end end; return true, "Removed " .. n .. ". Your files were not touched." end,
  ext_pick = function() picked = picked + 1 end,
}
local page = dofile("lua/core/menu/extra.lua")
page.init(); page.redraw()
check(shown("EXT FOLDERS") and shown("[ext] Drums") and shown("[ext] Loops") and shown("ADD FOLDER"), "the title, both folders and ADD FOLDER are listed")
check(shown("MISSING"), "an unreachable folder is marked MISSING")
check(shown("K3: remove the shortcut"), "the hint on a folder says what K3 does")
-- K3 on a folder only asks
page.key(3, 1); page.redraw()
check(#removed == 0, "the first K3 removes nothing")
check(shown("NOT deleted") or shown("NOT"), "the warning says the files are NOT deleted")
check(shown("K3 again: remove"), "the warning says K3 again confirms and K2 cancels")
page.key(2, 1)
check(#removed == 0 and page_now == "EXTRA", "K2 cancels: nothing removed, still on the page")
page.redraw(); check(shown("cancelled"), "...and says so")
-- confirm with the second K3
page.key(3, 1); page.key(3, 1)
check(#removed == 1 and removed[1] == "[ext] Drums", "K3 twice removes that shortcut")
local seen = false
for _ = 1, 40 do _menu.timer.event(); page.redraw(); if shown("touched") then seen = true end end
check(seen, "the answer says the files were not touched (a long sentence turns its lines)")
-- encoder moves a selection, not while asking
page.enc(2, 1)
page.key(3, 1); page.enc(2, 1); page.key(2, 1)
check(#removed == 1, "E2 while asking does nothing and K2 cancels")
-- ADD FOLDER
page.enc(2, 5); page.redraw()
check(shown("K3: choose a folder"), "on ADD FOLDER the hint says K3 chooses")
page.key(3, 1); page.key(3, 1)
check(picked == 1, "K3 on ADD FOLDER opens the picker once (a second press while it is open does not open another)")
_norns.ext_folder_chosen("F:\\New\\Folder"); page.redraw()
check(shown("Added [ext] New"), "the chosen folder is added and the answer shown")
check(shown("[ext] New"), "the new folder is in the list")
_norns.ext_folder_chosen(""); page.redraw()
check(shown("cancelled"), "a cancelled picker says so")
-- a failure is not a cancel: the step and the code are shown
_norns.ext_folder_chosen("", "the folder window could not open (Show, error 0x80070057)")
local seen_fail, seen_cancel = false, false
for _ = 1, 40 do _menu.timer.event(); page.redraw(); if shown("0x80070057") then seen_fail = true end; if shown("cancelled") then seen_cancel = true end end
check(seen_fail, "a failure shows its error code on the screen")
check(not seen_cancel, "a failure never says cancelled")
-- K2 on the list goes back to SYSTEM
page.key(2, 1)
check(page_now == "SYSTEM", "K2 goes back")
-- the menu item
_norns.open_extra_folders()
check(page_now == "EXTRA", "the menu item opens the page")
if fails > 0 then print(fails .. " failed") os.exit(1) end
print("ext folders page: all passed")
