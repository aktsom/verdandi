-- scenarios for lua/core/virtual_home.lua. run from the repo root with a scratch HOME:
--   d=$(mktemp -d); HOME=$d <lua 5.3> macos/tests/virtual_home_test.lua lua/core/virtual_home.lua

local module = arg[1]
local real = os.getenv('HOME')
assert(real and real ~= '/home/we', 'run with a scratch HOME')
os.execute('mkdir -p "' .. real .. '/dust/code/demo/lib" "' .. real .. '/dust/audio"')

-- stub C side: record what reaches it
local seen = {}
_json = {encode = function() return '{}' end}
_norns = {
  sound_file_inspect = function(path) seen.inspect = path; return 2, 48000, path end,
  system_cmd = function(cmd, cb) seen.cmd = cmd; cb(real .. '/dust/code/demo/x.lua\n') end,
  screen_text = function(s) seen.text = s end,
}
local screen_text = _norns.screen_text

dofile(module)

local failures = 0
local function check(what, got, want)
  if got ~= want then
    failures = failures + 1
    print('FAIL ' .. what .. ': got ' .. tostring(got) .. ', want ' .. tostring(want))
  end
end

check('HOME is virtual', os.getenv('HOME'), '/home/we')
check('other env vars pass', os.getenv('PATH') ~= nil, true)

-- files through the virtual path land in the real home
local f = assert(io.open('/home/we/dust/code/demo/demo.lua', 'w'))
f:write('return 42\n'); f:close()
check('io.open wrote the real file', io.open(real .. '/dust/code/demo/demo.lua') ~= nil, true)
check('dofile', dofile('/home/we/dust/code/demo/demo.lua'), 42)
check('loadfile', loadfile('/home/we/dust/code/demo/demo.lua')(), 42)
local n = 0
for _ in io.lines('/home/we/dust/code/demo/demo.lua') do n = n + 1 end
check('io.lines', n, 1)
check('os.rename', os.rename('/home/we/dust/code/demo/demo.lua', '/home/we/dust/code/demo/main.lua'), true)

-- shell commands go out real, output comes back virtual
local p = io.popen('ls -d /home/we/dust/code/demo')
check('popen output is virtual', p:read('*l'), '/home/we/dust/code/demo')
p:close()
local lines = {}
for l in io.popen('cd /home/we/dust/code && find "$PWD" -name main.lua'):lines() do lines[#lines + 1] = l end
check('popen lines are virtual', lines[1], '/home/we/dust/code/demo/main.lua')
check('os.execute', os.execute('test -f /home/we/dust/code/demo/main.lua'), true)

-- only whole path components are rewritten (checked one way: a round trip through the
-- shell would undo a wrong rewrite)
_norns.sound_file_inspect('/home/weird/a.wav /x/home/we-not "/home/we" /home/we')
check('component boundaries', seen.inspect, '/home/weird/a.wav /x/home/we-not "' .. real .. '" ' .. real)

-- require from a virtual package.path / script lib dir
local lib = assert(io.open('/home/we/dust/code/demo/lib/helper.lua', 'w'))
lib:write('return {ok = true}\n'); lib:close()
package.path = '/home/we/dust/code/demo/lib/?.lua;' .. package.path
check('require from virtual path', require('helper').ok, true)
check('require cjson -> built-in', require('cjson'), _json)

-- C functions: listed ones translate both ways, others are untouched
local channels, rate, path = _norns.sound_file_inspect('/home/we/dust/audio/a.wav')
check('C arg real', seen.inspect, real .. '/dust/audio/a.wav')
check('C result virtual', path, '/home/we/dust/audio/a.wav')
local captured
_norns.system_cmd('ls /home/we/dust', function(out) captured = out end)
check('system_cmd command real', seen.cmd, 'ls ' .. real .. '/dust')
check('system_cmd callback virtual', captured, '/home/we/dust/code/demo/x.lua\n')
check('screen_text not wrapped', _norns.screen_text, screen_text)

-- C events with paths, handlers defined after the module loaded
local got_file
_norns.tape_play_file = function(file) got_file = file end
_norns.tape_play_file(real .. '/dust/audio/tape/0001.wav')
check('path event virtual', got_file, '/home/we/dust/audio/tape/0001.wav')
_norns.some_other_event = function(x) got_file = x end
_norns.some_other_event(real)
check('other events untouched', got_file, real)

os.execute('rm -rf "' .. real .. '/dust"')
if failures == 0 then print('virtual /home/we: all scenarios pass') end
os.exit(failures == 0 and 0 or 1)
