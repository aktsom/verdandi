-- SYSTEM > CLEAN UP (lua/core/menu/cleanup.lua, docs/port/clean-layout.md section 3), against the real linux/tidy.sh on a fixture norns home. run from the repo root:
--   NORNS_HOME=<fixture> NORNS_TIDY=linux/tidy.sh lua5.3 linux/tests/cleanup_page_test.lua
-- the rules: every group is one line with a size; nothing is changed without a confirmation (K3 = yes, K2 = no); the age row is the only thing that deletes;
-- restore puts an item back; your scripts, samples, data and settings are never touched; the page is in SYSTEM's list on a computer only
local home = assert(os.getenv("NORNS_HOME"), "NORNS_HOME")
local tidy = assert(os.getenv("NORNS_TIDY"), "NORNS_TIDY")
package.path = "lua/?.lua;lua/lib/?.lua;lua/core/?.lua;" .. package.path

local function sh(cmd) local h = io.popen(cmd .. " 2>&1"); local out = h:read("a"); h:close(); return out end
local function put(path, text) local f = assert(io.open(path, "w")); f:write(text); f:close() end
local function exists(path) local f = io.open(path); if f then f:close() return true end return false end
local function slurp(path) local f = io.open(path); if not f then return nil end local c = f:read("a"); f:close(); return c end

-- the fixture
os.execute(string.format("rm -rf '%s/disabled' '%s/logs' '%s/cache' '%s/.plugin-fix'; mkdir -p '%s/dust/code/a' '%s/logs/crash' '%s/cache/x' '%s/x/folder'", home, home, home, home, home, home, home, home))
put(home .. "/dust/code/a/a.lua", "print(1)\n")
put(home .. "/audio.conf", "rate=48000\n")
put(home .. "/ui.conf", "brightness=1.0\n")
put(home .. "/x/folder/plug.so", "so")
for _, f in ipairs({"norns.1.log", "norns.2.log", "sclang.1.log"}) do put(home .. "/logs/" .. f, string.rep("l", 2000)) end
put(home .. "/logs/norns.log", "current")
put(home .. "/logs/crash/crash-1000-1.txt", "c")
put(home .. "/logs/crash/crash-2000-1.txt", "c")
sh("touch -d '200 days ago' '" .. home .. "/logs/norns.2.log' '" .. home .. "/logs/crash/crash-1000-1.txt' '" .. home .. "/audio.conf'")
put(home .. "/.plugin-fix", home .. "/x/folder\twrong-architecture plug-in (32-bit ARM) on x86_64\n")
local function user_state() return sh("cd '" .. home .. "' && find dust audio.conf ui.conf -type f -exec md5sum {} + | sort") end
local before = user_state()

local fails = 0
local function check(ok, what) if not ok then fails = fails + 1; print("FAIL " .. what) end end

-- the menu environment
local texts = {}
screen = {clear = function() texts = {} end, level = function() end, move = function() end, update = function() end, text = function(s) texts[#texts + 1] = s end,
  text_right = function(s) texts[#texts + 1] = s end, text_extents = function(s) return #s * 5 end}
local pushed, redraws = {}, 0
_menu = {redraw = function() redraws = redraws + 1 end, set_page = function(p) pushed[#pushed + 1] = p end}
norns = {none = function() end}
util = {
  clamp = function(x, lo, hi) return math.max(lo, math.min(hi, x)) end,
  os_capture = function(cmd) local h = io.popen(cmd .. " 2>&1"); local out = h:read("a"); h:close(); return out end,
}
package.loaded.util = util
local function shown(s) for _, t in ipairs(texts) do if t:find(s, 1, true) then return true end end return false end

local page = dofile("lua/core/menu/cleanup.lua")
page.init()
page.redraw()
-- the groups, one line each with a size
check(shown("ARM PLUG-INS"), "a problem line is shown while the plug-in check has a finding")
local names = {}
for _, r in ipairs(page.rows) do names[r.name] = r end
check(names.DISABLED and names.LOGS and names.CRASHES and names.SEEDED and names.CACHE and names.REMOVE, "every group is a line")
for _, n in ipairs({"DISABLED", "LOGS", "CRASHES", "SEEDED", "CACHE", "REMOVE"}) do
  check(names[n] and names[n].right and names[n].right ~= "", n .. " has a size on its line")
end
check(shown("DISABLED") and shown("LOGS") and shown("CRASHES"), "the first groups are on the screen: " .. table.concat(texts, "|"))
check(shown("REMOVE >90 DAYS"), "the age row is pinned at the bottom")
check(names.LOGS.mid:find("runs", 1, true) ~= nil, "logs are shown as runs")

-- walk to a row by name
local function goto_row(name)
  for _ = 1, 20 do page.enc(2, -1) end
  for _ = 1, 20 do
    if page.rows[page.pos].name == name then return true end
    page.enc(2, 1)
  end
  return false
end

-- the problem: K3 asks, K2 says no and nothing moves; K3 then K3 moves it into disabled/
check(goto_row("PROBLEM"), "the PROBLEM row exists")
page.key(3, 1); page.redraw()
check(shown("K3") and shown("K2") and (shown("MOVE") or shown("move")), "K3 on a problem asks first")
check(exists(home .. "/x/folder/plug.so"), "nothing moved before the confirmation")
page.key(2, 1)
check(exists(home .. "/x/folder/plug.so") and #pushed == 0, "K2 says no: nothing moved, the page stays")
page.key(3, 1); page.key(3, 1)
check(not exists(home .. "/x/folder/plug.so"), "the second K3 moves the folder")
check(exists(home .. "/disabled/MANIFEST.tsv") and (slurp(home .. "/disabled/MANIFEST.tsv") or ""):find("x/folder", 1, true) ~= nil, "into disabled/ with a manifest line")
page.redraw()
check(not shown("ARM PLUG-INS"), "the problem is gone from the page afterwards")

-- disabled: listed, restore asks first
page.init()
check(goto_row("DISABLED"), "the DISABLED row")
page.redraw(); check(shown("1 item") or shown("1 items"), "DISABLED shows one item")
page.key(3, 1); page.redraw()
check(shown("folder"), "K3 lists the item: " .. table.concat(texts, "|"))
page.key(3, 1) page.redraw()
check(shown("RESTORE") or shown("restore"), "K3 on an item asks about the restore")
check(not exists(home .. "/x/folder/plug.so"), "not restored before the confirmation")
page.key(2, 1)
check(not exists(home .. "/x/folder/plug.so"), "K2: not restored")
page.key(3, 1); page.key(3, 1)
check(exists(home .. "/x/folder/plug.so"), "restore puts it back")
page.key(2, 1) -- list -> groups

-- the age row: shows what is older, asks, then removes exactly that
page.init()
goto_row("REMOVE")
page.redraw()
check(shown("90"), "the age starts at 90 days: " .. table.concat(texts, "|"))
page.enc(3, 1); page.redraw()
check(shown("180"), "E3 changes the age to 180")
page.enc(3, -1); page.redraw()
check(shown("90"), "and back to 90")
check(shown("2 items") or shown("items"), "the row says how many items are older")
local older = sh("NORNS_HOME='" .. home .. "' '" .. tidy .. "' remove-older 90")
page.key(3, 1); page.redraw()
check(shown("K3") and shown("K2"), "K3 asks once")
check(exists(home .. "/logs/norns.2.log") and exists(home .. "/logs/crash/crash-1000-1.txt"), "nothing removed before the confirmation")
page.key(2, 1)
check(exists(home .. "/logs/norns.2.log"), "K2: nothing removed")
page.key(3, 1); page.key(3, 1)
check(not exists(home .. "/logs/norns.2.log") and not exists(home .. "/logs/crash/crash-1000-1.txt"), "the second K3 removes the old items")
check(exists(home .. "/logs/norns.1.log") and exists(home .. "/logs/norns.log") and exists(home .. "/logs/crash/crash-2000-1.txt"), "the newer ones and the current log stay")
page.redraw(); check(shown("removed") or shown("Removed"), "a plain sentence says what happened")

-- never touched
check(user_state() == before, "dust/, audio.conf and ui.conf: not one byte changed")
check(exists(home .. "/audio.conf") and exists(home .. "/ui.conf"), "the settings are still there (an old audio.conf is yours, not a log)")

-- K2 at the top goes back to SYSTEM
page.init(); page.key(2, 1)
check(pushed[#pushed] == "SYSTEM", "K2 goes back to SYSTEM")

-- SYSTEM's list: the page is there on a computer only
local getenv = os.getenv
local function system_with(platform)
  os.getenv = function(k) if k == "NORNS_PLATFORM" then return platform end return getenv(k) end
  local m = dofile("lua/core/menu/system.lua")
  os.getenv = getenv
  return table.concat(m.pages, ","), table.concat(m.list, "|")
end
local pages, list = system_with("linux")
check(pages == "DEVICES,AUDIO,UI,BOX,CLEANUP,MODS,RESET,RESTART", "SYSTEM on a computer: " .. pages)
check(list:find("CLEAN UP >", 1, true) ~= nil, "the list shows 'CLEAN UP >'")
pages = system_with(nil)
check(pages == "DEVICES,WIFI,MODS,SETTINGS,RESTART,UPDATE", "SYSTEM on a device is as before: " .. pages)
local menu_src = io.open("lua/core/menu.lua"):read("a")
check(menu_src:find('m%["CLEANUP"%]') ~= nil, 'menu.lua registers m["CLEANUP"]')

if fails > 0 then print("cleanup_page_test: " .. fails .. " failed") os.exit(1) end
print("cleanup_page_test: all passed")
