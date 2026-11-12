-- Windows mod scan: C glob() on Windows expands a wildcard in the last path component only, so "*/lib/mod.lua" found nothing and
-- SYSTEM > MODS stayed empty. With _norns.listdir present, Mods.scan walks the code folder (accents and blanks in names allowed).
-- Checks: mods are found, enabled, and still found + enabled after a restart (fresh Mods, enabled list read from disk); Linux (no listdir) still uses glob.
-- run from the repo root:   lua5.3 linux/tests/mods_scan_windows_test.lua
local _print = print
package.path = "lua/?.lua;lua/core/?.lua;lua/lib/?.lua;" .. package.path
local tmp = os.tmpname(); os.remove(tmp)
tmp = "/tmp/mst" .. tmp:match("(%w+)$")
local code = tmp .. "/dust/code/"
os.execute("mkdir -p '" .. code .. "'")
local fails = 0
local function check(ok, what) if not ok then fails = fails + 1; _print("FAIL", what) end end

local function mkmod(name, withmod)
  os.execute("mkdir -p '" .. code .. name .. "/lib'")
  if withmod then
    local f = io.open(code .. name .. "/lib/mod.lua", "w")
    f:write("MODS_LOADED = (MODS_LOADED or {}); table.insert(MODS_LOADED, '" .. name .. "')\n"); f:close()
  end
end
mkmod("sidvagn", true); mkmod("nb", true); mkmod("Mödul été", true); mkmod("no mod here", false)
os.execute("mkdir -p '" .. code .. "plain script'")

-- the Windows glob: wildcard only in the last component, so a "*" folder part matches nothing
local glob_calls = 0
norns = { system_glob = function(pattern) glob_calls = glob_calls + 1; return nil, 3 end }
paths = { code = code, enabled_mods = tmp .. "/enabled_mods.data" }
package.path = code .. "?.lua;" .. package.path

local function listdir(dir) -- same shape as _norns.listdir: folders first with "/", plain names after
  local t = {}
  local p = io.popen("ls -p '" .. dir .. "'")
  for l in p:lines() do t[#t + 1] = l end
  p:close()
  return t
end
_norns = { listdir = listdir }

local function fresh()
  package.loaded["core.mods"] = nil; package.loaded["mods"] = nil
  return dofile("lua/core/mods.lua")
end

local Mods = fresh()
local scan = Mods.scan()
check(scan and scan["sidvagn"] and scan["nb"], "sidvagn and nb found")
check(scan and scan["Mödul été"], "accented + spaced folder found")
check(scan and not scan["no mod here"] and not scan["plain script"], "folders without lib/mod.lua are not mods")
check(glob_calls == 0, "the glob is not used when a folder listing exists")
check(scan["sidvagn"][1] == "sidvagn/lib/mod" and scan["sidvagn"][2] == code .. "sidvagn/lib/mod.lua", "entry shape {relative, path}")

-- enable, save, restart
Mods.load_enabled()
Mods.set_enabled("sidvagn", true, true)
Mods.set_enabled("Mödul été", true, true)
check(Mods.is_enabled("sidvagn"), "enabled")
local M2 = fresh() -- restart
M2.load_enabled()
check(M2.is_enabled("sidvagn") and M2.is_enabled("Mödul été") and not M2.is_enabled("nb"), "enabled list survives a restart")
local s2 = M2.scan()
check(s2["sidvagn"] and s2["Mödul été"], "found again after restart")
NORNS_PLATFORM_SET = nil
M2.load(s2, true)
local loaded = {}
for _, n in ipairs(MODS_LOADED or {}) do loaded[n] = true end
check(loaded["sidvagn"] and loaded["Mödul été"] and not loaded["nb"], "only the enabled mods load")

-- Linux: no listdir -> glob as before
_norns = {}
norns.system_glob = function(pattern)
  glob_calls = glob_calls + 1
  return { code .. "sidvagn/lib/mod.lua", code .. "nb/lib/mod.lua" }
end
local M3 = fresh()
local s3 = M3.scan()
check(glob_calls == 1 and s3["sidvagn"] and s3["nb"] and s3["sidvagn"][1] == "sidvagn/lib/mod", "without a folder listing the glob is used, unchanged")

os.execute("rm -rf '" .. tmp .. "'")
if fails > 0 then _print(fails .. " FAILED"); os.exit(1) end
_print("mods_scan_windows_test: ok")
