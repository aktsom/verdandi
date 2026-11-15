-- the native folder check of util.file_exists gets the REAL path (Windows 0.10.6, docs/port/phase-m15.md): scripts and the core see /home/we/dust/..., the Windows build keeps its files under another folder,
-- and lua/core/virtual_home.lua translates the path where a _norns function takes one (PATH_FUNCTIONS). the first CI run of the fix found the check false for an existing folder because path_is_dir was not in that list.
-- run from the repo root: lua5.3 linux/tests/file_exists_virtual_home_test.lua
package.path = "lua/?.lua;lua/lib/?.lua;lua/core/?.lua;" .. package.path
local fails = 0
local function check(ok, what) if not ok then fails = fails + 1; print("FAIL " .. what) end end
local real_getenv = os.getenv
os.getenv = function(k) if k == "HOME" then return "C:/Users/someone/Verdandi" end return real_getenv(k) end
local got
_norns = {path_is_dir = function(p) got = p; return true end, listdir = function(p) got = p; return {} end}
dofile("lua/core/virtual_home.lua")
check(_norns.path_is_dir("/home/we/dust/code/cheat_codes_2/lib/nb/lib/") == true, "the call goes through")
check(got == "C:/Users/someone/Verdandi/dust/code/cheat_codes_2/lib/nb/lib/", "path_is_dir gets the real path, not /home/we (got " .. tostring(got) .. ")")
_norns.listdir("/home/we/dust/code/")
check(got == "C:/Users/someone/Verdandi/dust/code/", "listdir still does")
os.getenv = real_getenv
if fails > 0 then print("file_exists_virtual_home_test: " .. fails .. " FAILED") os.exit(1) end
print("file_exists_virtual_home_test: ok")
