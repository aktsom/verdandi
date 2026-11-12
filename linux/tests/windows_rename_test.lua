-- Windows: os.rename does not replace an existing file (the C runtime's rename fails with "File exists"; Linux replaces). Every setting that is saved through a temporary file (ui.conf, box.conf, midimap.conf, the state
-- files) was therefore written the first time and never again: after SYSTEM > RESTART the old theme and colours came back. lua/core/virtual_home.lua makes os.rename replace on Windows. run with HOME set to an empty folder:
--   mkdir -p /tmp/h && env HOME=/tmp/h lua5.3 linux/tests/windows_rename_test.lua
local home = os.getenv("HOME")
assert(home and home ~= "/home/we", "run with HOME set to an empty folder")
local fails = 0
local function check(c, w) if not c then fails = fails + 1; print("FAIL " .. w) end end

-- this machine is "Windows": the path separator, and a rename that refuses to replace
package.config = "\\\n;\n?\n!\n-\n"
local posix_rename = os.rename
os.rename = function(a, b)
  local f = io.open(b, "rb")
  if f then f:close(); return nil, b .. ": File exists", 17 end
  return posix_rename(a, b)
end
_norns = {}
dofile("lua/core/virtual_home.lua")

local function save(path, text)
  local tmp = path .. ".tmp"
  local f = assert(io.open(tmp, "w")); f:write(text); f:close()
  return os.rename(tmp, path)
end
local function read(path) local f = io.open(path); if not f then return nil end local t = f:read("a"); f:close(); return t end

os.execute("mkdir -p '" .. home .. "'")
check(save("/home/we/ui.conf", "brightness=1\n"), "the first save")
check(read("/home/we/ui.conf") == "brightness=1\n", "the first value")
check(save("/home/we/ui.conf", "brightness=2\n"), "a second save replaces the file")
check(read("/home/we/ui.conf") == "brightness=2\n", "and the new value is the file's: " .. tostring(read("/home/we/ui.conf")))
check(read("/home/we/ui.conf.tmp") == nil, "no temporary file is left")
check(save("/home/we/ui.conf", "brightness=3\n") and read("/home/we/ui.conf") == "brightness=3\n", "and again")
-- a rename of a file that is not there still fails, with the system's words
local ok, err = os.rename("/home/we/nothing", "/home/we/other")
check(ok == nil and err ~= nil, "a missing source is an error")

-- the real settings modules, twice
package.path = "lua/?.lua;lua/lib/?.lua;lua/core/?.lua;" .. package.path
util = {clamp = function(x, a, b) return math.max(a, math.min(b, x)) end, scandir = function() return {} end, file_exists = function(p) return read(p) ~= nil end}
package.loaded.util = util
_norns = {}
local U = dofile("lua/core/ui_settings.lua")
U.load()
U.state.brightness = 0.4
check(U.save(), "ui_settings: first save")
U.state.brightness = 0.9
check(U.save(), "ui_settings: second save")
local U2 = dofile("lua/core/ui_settings.lua")
U2.load()
check(math.abs((U2.state.brightness or 0) - 0.9) < 1e-6, "ui_settings: a new start reads the LAST value: " .. tostring(U2.state.brightness))

print(fails == 0 and "windows rename: all scenarios pass" or (fails .. " failures"))
os.exit(fails == 0)
