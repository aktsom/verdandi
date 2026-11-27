-- M38 (docs/port/phase-m38.md): an ext folder is shown as "[ext] <name>" but sits in the file browser where a normal folder called <name> would sit.
-- the listing is what util.scandir gives fileselect (the script browsers, the tape page, the params file picker). the platform sorts the text "[ext] <name>", so the ext folders all landed in the "e" group.
--   lua5.3 linux/tests/ext_sort_test.lua   (from the repository root)
package.path = "lua/lib/?.lua;" .. package.path
local failed = 0
local function check(name, got, want)
  if got == want then print("ok  ", name) else failed = failed + 1; print("FAIL", name); print("  got:  " .. got); print("  want: " .. want) end
end
local function j(t) return table.concat(t, " ") end

-- the platform's listing, as the real thing makes it: Windows = folders first, byte order of the names; Linux = `ls -pL --group-directories-first` (here: C locale, which is byte order too)
local function platform_listing(names)
  local dirs, files = {}, {}
  for _, n in ipairs(names) do if n:sub(-1) == "/" then dirs[#dirs + 1] = n else files[#files + 1] = n end end
  table.sort(dirs, function(a, b) return a:sub(1, -2) < b:sub(1, -2) end)
  table.sort(files)
  local out = {}
  for _, d in ipairs(dirs) do out[#out + 1] = d end
  for _, f in ipairs(files) do out[#out + 1] = f end
  return out
end

local function load_util(windows, names)
  package.loaded["util"] = nil
  util = nil
  _norns = {}
  if windows then
    _norns.listdir = function() return platform_listing(names) end
  else
    _norns.execute = function(cmd)
      if cmd:match("^ls ") then return table.concat(platform_listing(names), "\n") .. "\n" end
      local h = io.popen("LC_ALL=C " .. cmd)
      local o = h:read("a"); h:close(); return o
    end
  end
  dofile("lua/lib/util.lua")
  return util
end

local base = {"a/", "b2/", "c/", "e1/", "e2/", "zed/", "[ext] bass/", "[ext] eeee/", "[ext] zzz/", "kick.wav", "snare.wav"}
for _, windows in ipairs({true, false}) do
  local tag = windows and "Windows" or "Linux"
  local u = load_util(windows, base)
  check(tag .. ": ext folders sit by their real name, the normal ones keep their order, files last",
        j(u.scandir("/x/")), "a/ b2/ [ext] bass/ c/ e1/ e2/ [ext] eeee/ zed/ [ext] zzz/ kick.wav snare.wav")
  check(tag .. ": the shown text keeps the mark", tostring(u.scandir("/x/")[3]), "[ext] bass/")
end

-- digits first, and the same rules as the others (here the platform's byte order: "10" before "1x" before "2")
local u = load_util(true, {"10/", "1x/", "2/", "b/", "[ext] 05/", "[ext] 15/", "[ext] 3/", "[ext] B/"})
check("digits: an ext folder called 05 comes before 10, 15 between 10 and 1x, 3 after 2", j(u.scandir("/x/")), "[ext] 05/ 10/ [ext] 15/ 1x/ 2/ [ext] 3/ [ext] B/ b/")

-- mixed case: Windows sorts bytes (B before a), so "[ext] B" goes before "a" there
u = load_util(true, {"a/", "c/", "[ext] B/", "[ext] bass/"})
check("mixed case (byte order of Windows): B before a, bass between a and c", j(u.scandir("/x/")), "[ext] B/ a/ [ext] bass/ c/")

-- the rule of a locale that ignores case is the rule of `sort` in the same environment: here a stand-in that folds the case
u = load_util(false, {"a/", "B/", "c/", "[ext] bass/", "[ext] Z/"})
_norns.execute = function(cmd)
  if cmd:match("^ls ") then return "a/\nB/\nc/\n[ext] bass/\n[ext] Z/\n" end
  local h = io.popen("LC_ALL=C sort -f " .. cmd:match('^sort (.*)$')); local o = h:read("a"); h:close(); return o
end
check("Linux, a locale that folds the case: a, B, bass (the ext one after B), c, Z", j(u.scandir("/x/")), "a/ B/ [ext] bass/ c/ [ext] Z/")

-- the same name: the normal folder first, the ext folder right after it; two ext folders with one name keep the order of the listing
u = load_util(true, {"bass/", "x/", "[ext] bass/", "[ext] bass/"})
check("same name: the normal folder, then the ext entries, in a fixed order", j(u.scandir("/x/")), "bass/ [ext] bass/ [ext] bass/ x/")
u = load_util(true, {"a/", "bass/", "c/", "[ext] bass/"})
check("same name in the middle", j(u.scandir("/x/")), "a/ bass/ [ext] bass/ c/")

-- no ext entry: the listing is not touched; an "[ext] " FILE is not an ext folder; a name that only starts like it is not either
u = load_util(true, {"a/", "c/", "[ext] file.wav", "[extra]/", "z.wav"})
check("no ext folder: unchanged", j(u.scandir("/x/")), "[extra]/ a/ c/ [ext] file.wav z.wav")

-- the ext folder alone, and the folder with only ext folders
u = load_util(true, {"[ext] b/", "[ext] a/"})
check("only ext folders: by name", j(u.scandir("/x/")), "[ext] a/ [ext] b/")

-- the SYSTEM > EXT FOLDERS page is not touched by this change: ADD FOLDER first, then A-Z (its own order, lua/core/menu/extra.lua)
local f = io.open("lua/core/menu/extra.lua"); local src = f:read("a"); f:close()
check("the EXT FOLDERS page keeps its own sort", tostring(src:find("table.sort(m.items, by_name)", 1, true) ~= nil), "true")
-- the file browser lists through util.scandir (so the change reaches every browser)
f = io.open("lua/lib/fileselect.lua"); src = f:read("a"); f:close()
check("fileselect lists through util.scandir", tostring(src:find("util.scandir(dir)", 1, true) ~= nil), "true")

if failed > 0 then print(failed .. " failed"); os.exit(1) end
print("ext_sort_test: all passed")
