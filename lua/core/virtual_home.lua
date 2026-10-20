-- virtual /home/we
--
-- on the device HOME is /home/we, and scripts (and some of the core) hard-code that path:
-- they open '/home/we/dust/...', strip '/home/we/dust/audio/' off file browser results, or
-- pass such paths on to softcut and supercollider. on other systems (the macOS port) HOME
-- is somewhere else. so that every script runs unchanged, lua keeps seeing /home/we
-- (os.getenv('HOME'), _path, file lists), and paths are translated where they leave lua:
-- files, shell commands, require, and the C functions in _norns (softcut, tape, screen,
-- engine commands, system_cmd). output coming back (popen reads, C callbacks) is
-- translated the other way.
--
-- loaded first by config.lua; does nothing when HOME already is /home/we.

local VIRTUAL = '/home/we'
local real = os.getenv('HOME')
if real == nil or real == VIRTUAL then
  return
end

-- escape for use as a lua pattern
local real_pattern = real:gsub('[%^%$%(%)%%%.%[%]%*%+%-%?]', '%%%0')
local real_repl = real:gsub('%%', '%%%%')

-- '/home/we' as a whole path component, anywhere in s (paths are often inside shell
-- commands or engine arguments)
local function to_real(s)
  if type(s) ~= 'string' or not s:find(VIRTUAL, 1, true) then
    return s
  end
  return (s:gsub('()' .. VIRTUAL .. '()', function(a, b)
    local before = a > 1 and s:sub(a - 1, a - 1) or ''
    local after = s:sub(b, b)
    if before:match('[%w_%.%-]') or after:match('[%w_%.%-]') then
      return nil -- part of a longer name, leave it
    end
    return real
  end))
end

local function to_virtual(s)
  if type(s) ~= 'string' or not s:find(real, 1, true) then
    return s
  end
  return (s:gsub(real_pattern, VIRTUAL))
end

local function map(f, ...)
  local n = select('#', ...)
  local t = {...}
  for i = 1, n do t[i] = f(t[i]) end
  return table.unpack(t, 1, n)
end

--- environment
local getenv = os.getenv
os.getenv = function(name)
  if name == 'HOME' then return VIRTUAL end
  return getenv(name)
end

--- files
local open, lines, input, output = io.open, io.lines, io.input, io.output
io.open = function(path, ...) return open(to_real(path), ...) end
io.lines = function(path, ...)
  if path == nil then return lines() end
  return lines(to_real(path), ...)
end
io.input = function(f) return input(to_real(f)) end
io.output = function(f) return output(to_real(f)) end

local remove, rename = os.remove, os.rename
os.remove = function(path) return remove(to_real(path)) end
os.rename = function(a, b) return rename(to_real(a), to_real(b)) end

local _loadfile, _dofile = loadfile, dofile
loadfile = function(path, ...) return _loadfile(to_real(path), ...) end
dofile = function(path) return _dofile(to_real(path)) end

--- shell
local execute, popen = os.execute, io.popen
os.execute = function(cmd) return execute(to_real(cmd)) end

-- a popen handle whose reads come back with virtual paths
local popen_proxy = {}
popen_proxy.__index = popen_proxy
function popen_proxy:read(...) return map(to_virtual, self.f:read(...)) end
function popen_proxy:lines(...)
  local it = self.f:lines(...)
  return function() return map(to_virtual, it()) end
end
function popen_proxy:write(...) self.f:write(map(to_real, ...)); return self end
function popen_proxy:close() return self.f:close() end
function popen_proxy:flush() return self.f:flush() end
function popen_proxy:setvbuf(...) return self.f:setvbuf(...) end
function popen_proxy:seek(...) return self.f:seek(...) end

io.popen = function(cmd, mode)
  local f, err, code = popen(to_real(cmd), mode)
  if f == nil then return f, err, code end
  return setmetatable({f = f}, popen_proxy)
end

--- require: package.path / cpath hold virtual paths (config.lua, scripts adding their lib/)
local function search(path_list, loader)
  return function(name)
    local file, err = package.searchpath(name, to_real(path_list()))
    if file == nil then return '\n\t' .. err end
    local f, lerr = loader(file, name)
    if f == nil then error(lerr, 0) end
    return f, file
  end
end
package.searchers[2] = search(function() return package.path end, function(file) return _loadfile(file) end)
package.searchers[3] = search(function() return package.cpath end, function(file, name)
  return package.loadlib(file, 'luaopen_' .. name:gsub('%.', '_'))
end)

-- lua-cjson is built into matron (global _json); scripts that bring a linux cjson.so
-- get the built-in one
package.preload['cjson'] = function() return _json end

--- C functions that take file paths or commands: string arguments go out real, callbacks
-- get virtual strings back. (an explicit list: wrapping everything would cost time on the
-- hot screen calls, and would rewrite text that is only displayed)
local PATH_FUNCTIONS = {
  'execute', 'system_cmd', 'send_command', 'osc_send', 'sound_file_inspect',
  'cut_buffer_read_mono', 'cut_buffer_read_stereo', 'cut_buffer_write_mono', 'cut_buffer_write_stereo',
  'tape_record_open', 'tape_play_open',
  'screen_display_png', 'screen_load_png', 'screen_export_png', 'screen_export_screenshot',
  'choose_file',
}

local function wrap_arg(a)
  if type(a) == 'function' then
    return function(...) return a(map(to_virtual, ...)) end
  end
  return to_real(a)
end

for _, name in ipairs(PATH_FUNCTIONS) do
  local f = _norns[name]
  if type(f) == 'function' then
    _norns[name] = function(...) return map(to_virtual, f(map(wrap_arg, ...))) end
  end
end

-- events from C that carry a file path, handled by lua functions defined later
local PATH_EVENTS = {tape_play_file = true, tape_rec_file = true, file_chosen = true, file_dropped = true}
setmetatable(_norns, {__newindex = function(t, k, v)
  if PATH_EVENTS[k] and type(v) == 'function' then
    local handler = v
    v = function(...) return handler(map(to_virtual, ...)) end
  end
  rawset(t, k, v)
end})

print('virtual /home/we -> ' .. real)
