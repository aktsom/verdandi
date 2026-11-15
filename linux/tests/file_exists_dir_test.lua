-- util.file_exists for a folder (Windows 0.10.6, docs/port/phase-m15.md). on a norns (Linux) io.open("folder", "r") works, so util.file_exists is true for a folder, and scripts use it that way: cheat codes 2 tests
-- util.file_exists(_path.code.."cheat_codes_2/lib/nb/lib/") and others test util.file_exists(_path.code.."nb"). on Windows fopen refuses a folder, so it was always false there. the Windows build has the native
-- _norns.path_is_dir (GetFileAttributesW); this test gives io.open the Windows behaviour (a folder cannot be opened) and the native check a stand-in that asks the system, and checks that
--   - a folder, with and without a trailing slash, is found; a file is found; a name that does not exist is not; a file with a slash after it is not a folder
--   - without the native check (a norns, Linux) nothing changed: io.open decides
--   - the old function (io.open only) answers false for the existing folder on Windows: that is the failure the owner saw
-- run from the repo root: lua5.3 linux/tests/file_exists_dir_test.lua
package.path = "lua/?.lua;lua/lib/?.lua;" .. package.path
local fails = 0
local function check(ok, what) if not ok then fails = fails + 1; print("FAIL " .. what) end end

local tmp = os.tmpname()
os.remove(tmp)
os.execute("mkdir -p '" .. tmp .. "/code/cc/lib/nb/lib' && echo x > '" .. tmp .. "/code/cc/file.lua'")

local real_open = io.open
local function is_dir(p) return os.execute("test -d '" .. p:gsub("'", "'\\''") .. "'") == true end
-- the Windows fopen: a folder cannot be opened
io.open = function(p, m)
  if is_dir(p) then return nil, p .. ": Permission denied", 13 end
  return real_open(p, m)
end
_norns = {}
local util = dofile("lua/lib/util.lua")
local dir, file = tmp .. "/code/cc/lib/nb/lib", tmp .. "/code/cc/file.lua"

-- the old function, as it was
local function old_file_exists(name) local f = io.open(name, "r") if f ~= nil then io.close(f) return true else return false end end

-- Linux, a norns: no native check, io.open decides (a real folder opens there; with this stand-in it does not, which is the Windows case without the fix)
check(old_file_exists(dir) == false, "the old check says a folder that exists does not (the owner's failure: cheat codes 2 'MISSING INCLUDE')")
check(util.file_exists(dir) == false, "without the native check util.file_exists is unchanged (io.open only)")
check(util.file_exists(file) == true, "a file is found")

-- Windows with the fix: the native check is there
_norns.path_is_dir = function(p) return is_dir(p) end
check(util.file_exists(dir) == true, "a folder is found (cheat codes 2: lib/nb/lib)")
check(util.file_exists(dir .. "/") == true, "a folder with a trailing slash is found (the exact name cheat codes 2 tests)")
check(util.file_exists(tmp .. "/code/cc") == true, "a folder without a trailing slash is found (util.file_exists(_path.code..'nb'))")
check(util.file_exists(file) == true, "a file is still found")
check(util.file_exists(tmp .. "/code/nope") == false, "a name that does not exist is not found")
check(util.file_exists(tmp .. "/code/nope/") == false, "a missing folder with a trailing slash is not found")
check(util.file_exists(file .. "/") == false, "a file with a slash after it is not a folder")
check(util.file_exists(tmp .. "/code/cc/lib/nb/lib/nb.lua") == false, "a file that is not there is not found")

io.open = real_open
os.execute("rm -rf '" .. tmp .. "'")
if fails > 0 then print("file_exists_dir_test: " .. fails .. " FAILED") os.exit(1) end
print("file_exists_dir_test: ok")
