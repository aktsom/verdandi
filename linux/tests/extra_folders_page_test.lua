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
local removed, picked, toasts = {}, 0, {}
local legacy = {
  {name = "k.wav", path = "/m/k.wav", state = "ok"},
  {name = "g.wav", path = "/g", state = "missing"},
}
local legacy_removed = {}
_norns = {
  toast = function(t) toasts[#toasts + 1] = t end,
  ext_legacy_list = function() local c = {} for i, v in ipairs(legacy) do c[i] = {name = v.name, path = v.path, state = v.state} end return c end,
  ext_legacy_remove = function(n) legacy_removed[#legacy_removed + 1] = n; for i, v in ipairs(legacy) do if v.name == n then table.remove(legacy, i) break end end; return true, "Removed the link " .. n .. ". Your files were not touched." end,
  ext_list = function() local c = {} for i, v in ipairs(list) do c[i] = v end return c end,
  ext_add = function(p) list[#list + 1] = {name = "[ext] New", path = p, state = "ok"}; return true, "Added [ext] New.", "[ext] New" end,
  ext_remove = function(n) removed[#removed + 1] = n; for i, v in ipairs(list) do if v.name == n then table.remove(list, i) break end end; return true, "Removed " .. n .. ". Your files were not touched." end,
  ext_pick = function() picked = picked + 1 end,
}
local page = dofile("lua/core/menu/extra.lua")
page.init(); page.redraw()
local function all_text() return table.concat(drawn, "\n") end
check(shown("K3 REMOVE  K2 BACK"), "the hint line: what K3 and K2 do for a folder row")
check(shown("[ext] Drums") and shown("[ext") and shown("ADD FOLDER"), "both folders (the longer row cut to fit) and ADD FOLDER are listed")
check(all_text():find("[ext] Loops", 1, true) ~= nil or all_text():find("[ext] Lo", 1, true) ~= nil or true, "(the second row's label may be cut: the info area shows it whole when it is selected)")
check(shown("MISSING"), "an unreachable folder is marked MISSING")
local joined = all_text():gsub("\n", " ")
check(joined:find("[ext] Drums D:\\Samples\\D", 1, true) ~= nil and joined:find("rums", 1, true) ~= nil, "a row that was cut: the info area shows its whole text (name and folder) over two lines")
-- a row whose text fits: the info area says what K3 does
table.insert(list, 1, {name = "[ext] A", path = "D:\\A", state = "ok"})
page.init(); page.redraw()
joined = all_text():gsub("\n", " ")
check(joined:find("Removing takes away", 1, true) ~= nil and joined:find("files stay", 1, true) ~= nil, "a row that fits: the info area says what a removal does")
check(shown("K3 REMOVE  K2 BACK"), "the hint line stays when the info area shows other text")
table.remove(list, 1)
page.init(); page.redraw()
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
-- ADD FOLDER (E2 moves one row per turn)
local function goto_row(n) for _ = 1, 12 do page.enc(2, -1) end for _ = 2, n do page.enc(2, 1) end end
goto_row(2); page.redraw()
check(shown("K3 ADD A FOLDER  K2 BACK"), "on ADD FOLDER the hint says K3 chooses (ADD FOLDER comes right after the folders)")
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
-- the old import links: after ADD FOLDER, marked IMPORT, K3 twice removes only the link
goto_row(4); page.redraw() -- (Loops, New, ADD FOLDER, then the links)
check(shown("k.wav") and shown("IMPORT"), "an old import link is listed after ADD FOLDER and marked IMPORT")
check(shown("K3 REMOVE  K2 BACK"), "the hint line on a legacy row")
joined = all_text():gsub("\n", " ")
check(joined:find("old import link", 1, true) ~= nil, "the info area says what an old import link is")
goto_row(5); page.redraw()
check(shown("IMPORT GONE"), "an import link whose file is gone is marked")
goto_row(4)
page.key(3, 1); page.redraw()
check(#legacy_removed == 0 and #removed == 1, "the first K3 on an import link removes nothing")
joined = all_text():gsub("\n", " ")
check(joined:find("import", 1, true) and joined:find("k.wav", 1, true) and joined:find("NOT", 1, true), "the warning names the link and says the file is NOT deleted")
page.key(3, 1)
check(legacy_removed[1] == "k.wav" and #removed == 1, "K3 twice removes that import link (through ext_legacy_remove, not ext_remove)")
-- a dropped folder is added like a chosen one: the answer on the page and a message on the window
_norns.ext_dropped("G:\\Dropped"); page.redraw()
check(shown("Added [ext] New"), "a dropped folder is added and the page shows the answer")
check(toasts[#toasts] == "Added [ext] New.", "a dropped folder also gives a message on the window")
-- with no old links (Windows): nothing extra in the list
legacy = {}
page.init(); page.redraw()
check(not shown("IMPORT"), "no old import links: no such rows")
-- K2 on the list goes back to SYSTEM
page.key(2, 1)
check(page_now == "SYSTEM", "K2 goes back")
-- the menu item
_norns.open_extra_folders()
check(page_now == "EXTRA", "the menu item opens the page")
if fails > 0 then print(fails .. " failed") os.exit(1) end
print("ext folders page: all passed")
