-- M42 (docs/port/phase-m42.md; replaces the M38 test): the ext folders of a folder listing go together at the top of the list, A to Z among themselves by their real name (the rules of the SYSTEM > EXT
-- FOLDERS page: case ignored, digits first, numbers in number order), the "[ext] " mark stays in the shown text; every other entry follows in the order the platform gave it.
-- the listing is what util.scandir gives fileselect (the script browsers, the tape page, anything that calls fileselect) and the params file picker.
--   lua5.3 linux/tests/ext_sort_test.lua   (from the repository root)
package.path = "lua/lib/?.lua;" .. package.path
local failed = 0
local function check(name, got, want)
  if got == want then print("ok  ", name) else failed = failed + 1; print("FAIL", name); print("  got:  " .. got); print("  want: " .. want) end
end
local function j(t) return table.concat(t, " ") end

-- the platform's listing as the real thing makes it: folders first (a "/" after the name), then files. Windows sorts the bytes of the names, so "[ext] x" (0x5B) comes before the lower case folders and
-- after the capitals; Linux's ls sorts by the locale (here the C locale: the same bytes)
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
      return ""
    end
  end
  dofile("lua/lib/util.lua")
  return util
end

for _, windows in ipairs({true, false}) do
  local tag = windows and "Windows" or "Linux"
  -- the owner's folders (0.10.22 on Windows): the ext folders together at the top, the others after them as the platform lists them. cymatics is NOT sorted in between "cc2_live-audio" and "dronecaster"
  local u = load_util(windows, {"cc2_live-audio/", "dronecaster/", "[ext] 01 dropbox samples/", "[ext] boss rc 500 looper/", "[ext] cymatics/", "kick.wav"})
  check(tag .. ": the ext folders are together at the top, A to Z, then the normal folders and the files", j(u.scandir("/x/")),
        "[ext] 01 dropbox samples/ [ext] boss rc 500 looper/ [ext] cymatics/ cc2_live-audio/ dronecaster/ kick.wav")

  u = load_util(windows, {"a/", "b2/", "c/", "e1/", "e2/", "zed/", "[ext] zzz/", "[ext] bass/", "[ext] eeee/", "kick.wav", "snare.wav"})
  check(tag .. ": a folder called bass is not placed among the a, b2, c ... folders", j(u.scandir("/x/")),
        "[ext] bass/ [ext] eeee/ [ext] zzz/ a/ b2/ c/ e1/ e2/ zed/ kick.wav snare.wav")
  check(tag .. ": the shown text keeps the mark", tostring(u.scandir("/x/")[1]), "[ext] bass/")
end

-- A to Z by the rules of the EXT FOLDERS page: digits first and in number order, case ignored
local u = load_util(true, {"x/", "[ext] 10 loops/", "[ext] 2 loops/", "[ext] 02 drums/", "[ext] Zebra/", "[ext] apple/", "[ext] Bass/", "[ext] bass drum/", "[ext] 1a/"})
check("A to Z inside the group: digits first, numbers as numbers (1a, 2, 02, 10), case ignored (apple, Bass, bass drum, Zebra)", j(u.scandir("/x/")),
      "[ext] 1a/ [ext] 2 loops/ [ext] 02 drums/ [ext] 10 loops/ [ext] apple/ [ext] Bass/ [ext] bass drum/ [ext] Zebra/ x/")

-- names with spaces and accents
u = load_util(true, {"my samples/", "[ext] Drum Machines/", "[ext] drum kit/", "[ext] \xc3\x89t\xc3\xa9/", "[ext] a b c/"})
check("names with spaces and accents are one name each", j(u.scandir("/x/")), "[ext] a b c/ [ext] drum kit/ [ext] Drum Machines/ [ext] \xc3\x89t\xc3\xa9/ my samples/")

-- a normal folder with the same name as an ext folder: both are listed, the ext entry in the group at the top, the normal folder where the platform put it
u = load_util(true, {"a/", "bass/", "z/", "[ext] bass/", "[ext] aaa/"})
check("same name: the ext entry is in the group at the top, the normal folder stays where it was", j(u.scandir("/x/")), "[ext] aaa/ [ext] bass/ a/ bass/ z/")
u = load_util(false, {"Bass/", "bass/", "[ext] bass/"})
check("same name, other case: two normal folders and one ext folder", j(u.scandir("/x/")), "[ext] bass/ Bass/ bass/")

-- the normal entries keep the platform's order (capitals first on Windows, as before M38: nothing is re-sorted)
u = load_util(true, {"Zebra/", "apple/", "10/", "2/", "[ext] m/", "b.wav", "A.wav"})
check("the normal entries keep the order the platform gave", j(u.scandir("/x/")), "[ext] m/ 10/ 2/ Zebra/ apple/ A.wav b.wav")

-- no ext folder: the listing is not touched (the same table); a file called "[ext] ..." and a name that only starts like it are not ext folders
u = load_util(true, {"a/", "c/", "[ext] file.wav", "[extra]/", "z.wav"})
local plain = platform_listing({"a/", "c/", "[ext] file.wav", "[extra]/", "z.wav"})
check("no ext folder: unchanged", j(u.scandir("/x/")), j(plain))
local same = {"a/", "b/"}
check("no ext folder: the very same table comes back", tostring(u.ext_place(same) == same), "true")

-- only ext folders; one ext folder
u = load_util(true, {"[ext] b/", "[ext] a/"})
check("only ext folders: A to Z", j(u.scandir("/x/")), "[ext] a/ [ext] b/")
u = load_util(false, {"[ext] samples/"})
check("one ext folder", j(u.scandir("/x/")), "[ext] samples/")

-- an empty listing, and a folder that cannot be listed
u = load_util(true, {})
check("an empty listing", j(u.scandir("/x/")), "")

-- util.natural_less is the order of the EXT FOLDERS page: the same answer as core/menu/extra.lua's natural_less on a corpus
package.loaded["core/menu/winui"] = {}
package.loaded["core/menu/extra"] = nil
_norns = {ext_list = function() return {} end}
local ok, extra = pcall(dofile, "lua/core/menu/extra.lua")
if ok and type(extra) == "table" and extra.natural_less then
  local corpus = {"1a", "2", "02", "10", "apple", "Bass", "bass", "bass drum", "Zebra", "01 dropbox samples", "boss rc 500 looper", "cymatics", "Drop M\xc3\xbasica", "a1", "a01", "a10", "a2", "", " x", "B", "b"}
  local bad = 0
  for _, a in ipairs(corpus) do for _, b in ipairs(corpus) do
    if util.natural_less(a, b) ~= extra.natural_less(a, b) then bad = bad + 1 end
  end end
  check("util.natural_less gives the order of the EXT FOLDERS page on " .. #corpus * #corpus .. " pairs", tostring(bad), "0")
else
  failed = failed + 1; print("FAIL", "core/menu/extra.lua could not be loaded: " .. tostring(extra))
end
local f = io.open("lua/core/menu/extra.lua"); local src = f:read("a"); f:close()
check("the EXT FOLDERS page keeps its own sort", tostring(src:find("table.sort(m.items, by_name)", 1, true) ~= nil), "true")
f = io.open("lua/lib/fileselect.lua"); src = f:read("a"); f:close()
check("fileselect lists through util.scandir", tostring(src:find("util.scandir(dir)", 1, true) ~= nil), "true")
f = io.open("lua/core/params/file.lua"); src = f:read("a"); f:close()
check("the params file picker lists through util.scandir", tostring(src:find("util.scandir(self.dir)", 1, true) ~= nil), "true")

if failed > 0 then print(failed .. " failed"); os.exit(1) end
print("ext_sort_test: all passed")
