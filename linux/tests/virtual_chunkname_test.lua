-- lua/core/virtual_home.lua: the chunk name (debug.getinfo(n).source) of every script and library file starts with the virtual path
-- "@/home/we/...", as on the device, for dofile, include, loadfile and require. libraries locate themselves with it, as nb does:
--   local mydir = debug.getinfo(1).source:match("@?" .. _path.code .. "(.*/)")
-- run from the repo root with a scratch HOME:
--   d=$(mktemp -d); HOME=$d NB_DIR=<a checkout of github.com/sixolet/nb, optional> lua5.3 linux/tests/virtual_chunkname_test.lua lua/core/virtual_home.lua
local module = arg[1]
local real = os.getenv('HOME')
assert(real and real ~= '/home/we', 'run with a scratch HOME')
os.execute('rm -rf "' .. real .. '/dust" && mkdir -p "' .. real .. '/dust/code/fake/lib" "' .. real .. '/dust/code/nested/lib/deep" "' .. real .. '/dust/data"')

_json = {}
_norns = {}
dofile(module)

local failures = 0
local function check(what, got, want)
  if got ~= want then
    failures = failures + 1
    print('FAIL ' .. what .. ': got ' .. tostring(got) .. ', want ' .. tostring(want))
  end
end
local function write(path, text)
  local f = assert(io.open(path, 'w')) -- virtual path in, real file out
  f:write(text)
  f:close()
end

-- what config.lua, script.lua and startup.lua set up (include is the one of lua/core/startup.lua)
_path = {code = '/home/we/dust/code/', extn = '/home/we/dust/data/'}
norns = {state = {path = '/home/we/dust/code/fake/'}}
function include(file)
  local dirs = {norns.state.path, _path.code, _path.extn}
  for _, dir in ipairs(dirs) do
    local p = dir .. file .. '.lua'
    local f = io.open(p)
    if f then
      f:close()
      return dofile(p)
    end
  end
  error('MISSING INCLUDE: ' .. file, 2)
end
package.path = '/home/we/dust/code/fake/lib/?.lua;/home/we/dust/code/nested/lib/?.lua;' .. package.path
RESULT = {}

-- a script that finds its own folder the way nb does, and includes a library that does the same, which includes another one in a sub folder
local SELF = 'local mydir = debug.getinfo(1).source:match("@?" .. _path.code .. "(.*/)")\n'
write('/home/we/dust/code/fake/fake.lua', SELF .. [[
RESULT.script_dir = mydir
RESULT.script_source = debug.getinfo(1, 'S').source
RESULT.script_short = debug.getinfo(1, 'S').short_src
RESULT.lib_a = include(mydir .. "lib/a")
]])
write('/home/we/dust/code/fake/lib/a.lua', SELF .. [[
RESULT.a_dir = mydir
return include(mydir .. "deep/b")
]])
write('/home/we/dust/code/fake/lib/deep.lua', 'return true\n')
os.execute('mkdir -p "' .. real .. '/dust/code/fake/lib/deep"')
write('/home/we/dust/code/fake/lib/deep/b.lua', SELF .. [[
RESULT.b_dir = mydir
-- a sibling by dofile with the path built from mydir
RESULT.c = dofile(_path.code .. mydir .. "c.lua")
return "b done"
]])
write('/home/we/dust/code/fake/lib/deep/c.lua', SELF .. [[
RESULT.c_dir = mydir
RESULT.c_source = debug.getinfo(1, 'S').source
return "c done"
]])

dofile('/home/we/dust/code/fake/fake.lua')
check('script finds its folder', RESULT.script_dir, 'fake/')
check('script chunk name', RESULT.script_source, '@/home/we/dust/code/fake/fake.lua')
check('script short_src', RESULT.script_short, '/home/we/dust/code/fake/fake.lua')
check('library by include', RESULT.a_dir, 'fake/lib/')
check('nested library by include', RESULT.b_dir, 'fake/lib/deep/')
check('sibling by dofile with a built path', RESULT.c_dir, 'fake/lib/deep/')
check('sibling chunk name', RESULT.c_source, '@/home/we/dust/code/fake/lib/deep/c.lua')
check('values come back through include and dofile', RESULT.lib_a, 'b done')
check('dofile returns what the chunk returns', RESULT.c, 'c done')

-- the same through loadfile, and with the real path given
local f = loadfile('/home/we/dust/code/fake/lib/deep/c.lua')
f()
check('loadfile: chunk name', RESULT.c_source, '@/home/we/dust/code/fake/lib/deep/c.lua')
local g = loadfile(real .. '/dust/code/fake/lib/deep/c.lua')
g()
check('loadfile with the real path: chunk name is virtual too', RESULT.c_source, '@/home/we/dust/code/fake/lib/deep/c.lua')
dofile(real .. '/dust/code/fake/lib/deep/c.lua')
check('dofile with the real path: chunk name is virtual too', RESULT.c_source, '@/home/we/dust/code/fake/lib/deep/c.lua')

-- require: a library of the script's lib/ folder, and one of a nested lib/ (as nb is: require "nb/lib/nb")
write('/home/we/dust/code/fake/lib/req.lua', SELF .. 'RESULT.req_dir = mydir\nRESULT.req_source = debug.getinfo(1, "S").source\nRESULT.req_args = {...}\nreturn {ok = true}\n')
check('require works', require('req').ok, true)
check('require: library finds its folder', RESULT.req_dir, 'fake/lib/')
check('require: chunk name', RESULT.req_source, '@/home/we/dust/code/fake/lib/req.lua')
check('require: the loader data is the virtual file name', RESULT.req_args[2], '/home/we/dust/code/fake/lib/req.lua')

-- loadfile keeps its other behavior
check('loadfile: missing file', select(2, loadfile('/home/we/dust/code/fake/none.lua')), 'cannot open /home/we/dust/code/fake/none.lua')
check('loadfile: missing file, no chunk', (loadfile('/home/we/dust/code/fake/none.lua')), nil)
check('dofile: missing file raises', pcall(dofile, '/home/we/dust/code/fake/none.lua'), false)
write('/home/we/dust/code/fake/shebang.lua', '#!/usr/bin/env lua\nreturn debug.getinfo(1, "l").currentline\n')
check('loadfile: a first line starting with # is skipped, line numbers stay', loadfile('/home/we/dust/code/fake/shebang.lua')(), 2)
write('/home/we/dust/code/fake/bom.lua', '\239\187\191return 7\n')
check('loadfile: a UTF-8 byte order mark is skipped', loadfile('/home/we/dust/code/fake/bom.lua')(), 7)
write('/home/we/dust/code/fake/env.lua', 'return x\n')
check('loadfile: env argument', loadfile('/home/we/dust/code/fake/env.lua', 't', {x = 5})(), 5)
check('loadfile: env argument nil (none given: globals)', (function() x = 6; local r = loadfile('/home/we/dust/code/fake/env.lua')(); x = nil; return r end)(), 6)
check('loadfile: mode "b" refuses text', loadfile('/home/we/dust/code/fake/env.lua', 'b') == nil, true)
local bin = string.dump(load('return 11'))
local fb = assert(io.open('/home/we/dust/code/fake/bin.luac', 'wb'))
fb:write(bin)
fb:close()
check('loadfile: a binary chunk', loadfile('/home/we/dust/code/fake/bin.luac')(), 11)
write('/home/we/dust/code/fake/syntax.lua', 'x = = 1\n')
local _, serr = loadfile('/home/we/dust/code/fake/syntax.lua')
check('syntax error names the virtual file and line', serr, '/home/we/dust/code/fake/syntax.lua:1: unexpected symbol near \'=\'')
write('/home/we/dust/code/fake/boom.lua', 'local a = 1\nerror("boom")\n')
local ok, msg = pcall(dofile, '/home/we/dust/code/fake/boom.lua')
check('runtime error names the virtual file and line', msg, '/home/we/dust/code/fake/boom.lua:2: boom')
check('dofile(nil) is not mapped (stdin): exists', type(dofile), 'function')

-- other scripts' habits: paths built from state, data folders next to the script, debug.getinfo with other fields
write('/home/we/dust/code/fake/habits.lua', [[
local src = debug.getinfo(1, 'S').source
RESULT.habit_dir = src:sub(2):match('(.*/)')          -- the usual "folder of this file"
RESULT.habit_file = io.open(RESULT.habit_dir .. 'lib/deep.lua') ~= nil -- and then reading beside it
RESULT.habit_stack = debug.traceback('x'):match('/home/we/dust/code/fake/habits.lua:%d+')
]])
dofile('/home/we/dust/code/fake/habits.lua')
check('folder of this file from the source is usable', RESULT.habit_dir, '/home/we/dust/code/fake/')
check('a file beside it opens', RESULT.habit_file, true)
check('tracebacks show the virtual path', RESULT.habit_stack ~= nil, true)

-- the real nb library (github.com/sixolet/nb), if a checkout is given: as cheat codes 2 has it, in the script's lib/nb
local nb = os.getenv('NB_DIR')
if nb and nb ~= '' then
  os.execute('mkdir -p "' .. real .. '/dust/code/cheat_codes_2/lib" && cp -R "' .. nb .. '" "' .. real .. '/dust/code/cheat_codes_2/lib/nb" && rm -rf "' .. real .. '/dust/code/cheat_codes_2/lib/nb/.git"')
  norns.state.path = '/home/we/dust/code/cheat_codes_2/'
  package.path = '/home/we/dust/code/cheat_codes_2/lib/?.lua;' .. package.path
  -- what nb needs from norns at load time
  util = util or {acronym = function(s) return s end}
  midi = midi or {vports = {}}
  params = params or {}
  local ok2, res = pcall(require, 'nb/lib/nb')
  check('real nb: require "nb/lib/nb" (the library path of the script)', ok2, true)
  local ok4, res4 = pcall(include, 'cheat_codes_2/lib/nb/lib/nb')
  check('real nb: include by its path from dust/code (as cheat codes 2 does)', ok4 and type(res4) == 'table', true)
  if not ok4 then print(res4) end
  if not ok2 then print(res) end
  check('real nb: it is a table with players', type(res) == 'table' and type(res.players) == 'table', true)
  -- nb's own relative include of its player library worked: nb.none is a player made by it
  check('real nb: relative include of lib/player', type(res) == 'table' and type(res.none) == 'table', true)
else
  print('SKIP real nb library (NB_DIR not set)')
end

os.execute('rm -rf "' .. real .. '/dust"')
if failures == 0 then print('virtual chunk names: all scenarios pass') end
os.exit(failures == 0 and 0 or 1)
