-- mods on the desktop (docs/port/KNOWN-ISSUES.md item 17): SYSTEM > MODS lists every dust/code/<name>/lib/mod.lua, enabling saves, the startup loads the enabled
-- ones, a mod with an error is reported and does not stop the rest. the glob is the C one in miniature (it sees REAL paths only, as the real one does);
-- the virtual /home/we is the real one of lua/core/virtual_home.lua. run from the repo root with a scratch HOME and NORNS_PLATFORM set:
--   d=$(mktemp -d); HOME=$d NORNS_PLATFORM=linux lua5.3 linux/tests/mods_test.lua
local real = os.getenv('HOME')
assert(real and real ~= '/home/we', 'run with a scratch HOME')
local rawpopen = io.popen
os.execute('rm -rf "' .. real .. '/dust" && mkdir -p "' .. real .. '/dust/data"')
local function put(rel, text)
  local dir = rel:match("^(.*)/[^/]*$")
  os.execute('mkdir -p "' .. real .. '/' .. dir .. '"')
  local f = assert(io.open(real .. '/' .. rel, 'w')); f:write(text); f:close()
end
-- a mod that registers a hook and prints, one with an error, one that is not a mod (no lib/mod.lua), one nb-like
put('dust/code/fakemod/lib/mod.lua', [[
local mod = require 'core/mods'
print("FAKEMOD loaded as " .. tostring(mod.this_name))
mod.hook.register("system_post_startup", "fakemod", function() print("FAKEMOD hook ran") end)
]])
put('dust/code/badmod/lib/mod.lua', 'error("boom in the mod")\n')
put('dust/code/sidvagn-like/lib/mod.lua', 'FAKEMOD_NB = true\n')
put('dust/code/notamod/lib/other.lua', 'x = 1\n')
put('dust/code/script.lua', 'y = 1\n')

-- the C function in miniature: a pattern, real paths in and out, directories with a trailing slash (GLOB_MARK), nil and 1 for no match
_norns = {
  system_glob = function(pattern)
    local h = rawpopen('ls -d ' .. pattern .. ' 2>/dev/null')
    local out = {}
    for line in h:lines() do out[#out + 1] = line end
    h:close()
    if #out == 0 then return nil, 3 end
    return out
  end,
}
_json = {}
dofile('lua/core/virtual_home.lua')
package.path = 'lua/?.lua;lua/lib/?.lua;lua/core/?.lua;/home/we/dust/code/?.lua;' .. package.path
tab = require 'tabutil'
util = require 'util'
_path = {code = '/home/we/dust/code/', data = '/home/we/dust/data/', enabled_mods = '/home/we/dust/data/system.mods'}
_path.enabled_mods = '/home/we/dust/data/system.mods'
paths = _path
norns = {system_glob = _norns.system_glob}
local logs = {}
local realprint = print
print = function(...) local t = {} for i = 1, select('#', ...) do t[#t + 1] = tostring((select(i, ...))) end logs[#logs + 1] = table.concat(t, ' ') end
local function logged(s) for _, l in ipairs(logs) do if l:find(s, 1, true) then return true end end return false end

local fails = 0
local function check(ok, what) if not ok then fails = fails + 1; realprint('FAIL ' .. what) end end

-- 1. the scan finds the three mods and only those
local mods = require 'core/mods'
local found = mods.scan()
check(found ~= nil, 'the scan finds mods (it returned nil: the glob did not see the folders)')
local names = {}
for k in pairs(found or {}) do names[#names + 1] = k end
table.sort(names)
check(table.concat(names, ',') == 'badmod,fakemod,sidvagn-like', 'found: ' .. table.concat(names, ','))
check(found and found.fakemod and found.fakemod[1] == 'fakemod/lib/mod', 'the module path is fakemod/lib/mod')

-- 2. the page lists them, enabling saves
screen = {clear = function() end, level = function() end, move = function() end, text = function() end, text_center = function() end, update = function() end}
local shown = {}
_menu = {m = {}, redraw = function() end, set_page = function() end}
local page = dofile('lua/core/menu/mods.lua')
page.init()
check(page.len == 3 and page.list[1] == 'badmod' and page.list[2] == 'fakemod' and page.list[3] == 'sidvagn-like', 'the page lists three mods: ' .. table.concat(page.list, ','))
page.enc(2, 1) -- fakemod
check(page.selected == 'fakemod', 'selected ' .. tostring(page.selected))
page.enc(3, 1)
local saved = io.open('/home/we/dust/data/system.mods')
local text = saved and saved:read('a') or ''
if saved then saved:close() end
check(text:find('fakemod', 1, true) ~= nil, 'enabling saves the name in system.mods: ' .. text)
page.enc(2, -1); page.enc(3, 1) -- badmod enabled too
page.enc(2, 2); page.enc(3, 1) -- sidvagn-like too

-- 3. a restart: a fresh state loads the enabled mods as lua/core/startup.lua does (the lines are cut out of the file), an error is reported and stops nothing
for _, k in ipairs({'core/mods', 'core/hook'}) do package.loaded[k] = nil end
logs = {}
local src = io.open('lua/core/startup.lua'):read('a')
local block = src:match("(%-%- load matron mods and invoke system hooks.-)\n*$")
assert(block, 'the mods block of startup.lua was not found')
local ok, err = pcall(load(block))
check(ok, 'the startup block must not raise: ' .. tostring(err))
mods = require 'core/mods'
check(mods.is_loaded('fakemod'), 'fakemod is loaded after the restart')
check(mods.is_loaded('sidvagn-like') and FAKEMOD_NB == true, 'the nb-like mod ran its lib/mod.lua')
check(not mods.is_loaded('badmod'), 'badmod is not marked loaded')
check(logged('FAKEMOD loaded as fakemod'), 'the mod ran with this_name set')
check(logged('mod found: fakemod') and logged('mod found: badmod') and logged('mod found: sidvagn-like'), 'one line per mod found')
check(logged('mod failed: badmod') and logged('boom in the mod'), 'the failing mod is reported with its error')
check(logged('mod found: notamod') == false, 'a folder without lib/mod.lua is not a mod')
local hooks = require 'core/hook'
hooks.system_post_startup()
check(logged('FAKEMOD hook ran'), 'the hook the mod registered runs')

-- 4. a mod that was not enabled is not loaded
for _, k in ipairs({'core/mods', 'core/hook'}) do package.loaded[k] = nil end
FAKEMOD_NB = nil
os.remove('/home/we/dust/data/system.mods')
logs = {}
ok = pcall(load(block))
mods = require 'core/mods'
check(ok and not mods.is_loaded('fakemod') and FAKEMOD_NB == nil, 'nothing enabled, nothing loaded')
check(logged('mod found: fakemod'), 'but it is still listed (found) in the log')

if fails > 0 then realprint('mods_test: ' .. fails .. ' failed') os.exit(1) end
realprint('mods_test: all passed')
