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
if package.config:sub(1, 1) == '\\' then
  -- Windows: the C runtime's rename fails when the new name exists (POSIX replaces it). every setting that is saved through a temporary file (ui.conf, box.conf, midimap.conf, the state files) was written the first
  -- time and never again: after a restart the old theme and colours came back. so: when the rename fails and the target is there, the target goes first. (a crash between the two leaves the temporary file, which holds
  -- the new content; the old file is gone: the defaults are read, never half a file)
  os.rename = function(a, b)
    local ra, rb = to_real(a), to_real(b)
    local ok, err, code = rename(ra, rb)
    if ok then return ok, err, code end
    local target = open(rb, 'rb')
    local source = open(ra, 'rb')
    if target and source then
      target:close()
      source:close()
      if remove(rb) then return rename(ra, rb) end
    else
      if target then target:close() end
      if source then source:close() end
    end
    return ok, err, code
  end
else
  os.rename = function(a, b) return rename(to_real(a), to_real(b)) end
end

-- loadfile, dofile and require read the real file but name the chunk with the virtual path ("@/home/we/dust/code/x.lua"),
-- as on the device: libraries find their own folder with debug.getinfo(1).source (nb does:
-- debug.getinfo(1).source:match("@?" .. _path.code .. "(.*/)")), and error messages and tracebacks show the path the script knows.
-- (the real path is in the "virtual /home/we -> ..." line the log starts with)
local _loadfile, _dofile = loadfile, dofile
local function load_named(file, mode, env, has_env)
  -- file is the path as the caller gave it; real_file is where it is
  local real_file = to_real(file)
  local f, err = open(real_file, 'rb')
  if f == nil then
    return nil, 'cannot open ' .. to_virtual(file)
  end
  local text = f:read('a')
  f:close()
  if text == nil then
    return nil, 'cannot read ' .. to_virtual(file)
  end
  -- what loadfile does: skip a UTF-8 byte order mark, and a first line that starts with # (the newline stays: line numbers)
  if text:sub(1, 3) == '\239\187\191' then text = text:sub(4) end
  if text:sub(1, 1) == '#' then text = text:gsub('^[^\n]*', '', 1) end
  local name = '@' .. to_virtual(real_file)
  if has_env then
    return load(text, name, mode or 'bt', env)
  end
  return load(text, name, mode or 'bt')
end

loadfile = function(path, ...)
  if path == nil then return _loadfile(nil, ...) end -- standard input
  return load_named(path, (...), select(2, ...), select('#', ...) >= 2)
end
dofile = function(path)
  if path == nil then return _dofile() end
  local chunk, err = load_named(path)
  if chunk == nil then error(err, 0) end
  return chunk()
end

--- shell
-- Windows, a home folder with a blank in its name (C:/Users/Jane Smith/Verdandi): in a SHELL command the replacement of /home/we must be quoted for the shell, or the path falls in two words. outside quotes the blanks
-- are escaped, inside quotes (the script quoted it) the path is put in as it is. elsewhere (Linux, macOS, a home without a blank) this is to_real
-- Windows build (norns.exe has _norns.listdir): the bundled busybox has no `find -printf`; core/find_printf.lua rewrites the one form scripts use (docs/port/phase-m9.md)
local find_printf = (type(_norns) == 'table' and _norns.listdir ~= nil) and require('core/find_printf') or nil

local function to_real_shell_path(s)
  if type(s) ~= 'string' or package.config:sub(1, 1) ~= '\\' or not real:find('%s') or not s:find(VIRTUAL, 1, true) then
    return to_real(s)
  end
  local escaped = (real:gsub('%s', '\\%0'))
  -- the quoting context at the replacement: none (blanks are escaped), "..." or '...' (the path goes in as it is). a command substitution ($( ) or backticks) starts a NEW context even inside double quotes
  -- (the shell splits its words again): the saved context is pushed on `stack` and none is in force until the substitution ends. (test -n "$(find /home/we/... -name X)": the mod's check)
  local out, i, q, stack = {}, 1, nil, {}
  while i <= #s do
    local c = s:sub(i, i)
    if s:sub(i, i + #VIRTUAL - 1) == VIRTUAL and not (i > 1 and s:sub(i - 1, i - 1):match('[%w_%.%-]')) and not s:sub(i + #VIRTUAL, i + #VIRTUAL):match('[%w_%.%-]') then
      out[#out + 1] = q and real or escaped
      i = i + #VIRTUAL
    elseif c == '\\' and q ~= "'" then
      out[#out + 1] = s:sub(i, i + 1)
      i = i + 2
    elseif q ~= "'" and c == '$' and s:sub(i + 1, i + 1) == '(' then
      stack[#stack + 1] = {q = q, par = 0, kind = '$('}
      q = nil
      out[#out + 1] = '$('
      i = i + 2
    elseif q ~= "'" and c == '`' then
      local top = stack[#stack]
      if top and top.kind == '`' then
        q = top.q
        stack[#stack] = nil
      else
        stack[#stack + 1] = {q = q, par = 0, kind = '`'}
        q = nil
      end
      out[#out + 1] = c
      i = i + 1
    elseif q == nil and c == '(' and #stack > 0 and stack[#stack].kind == '$(' then
      stack[#stack].par = stack[#stack].par + 1
      out[#out + 1] = c
      i = i + 1
    elseif q == nil and c == ')' and #stack > 0 and stack[#stack].kind == '$(' then
      local top = stack[#stack]
      if top.par > 0 then
        top.par = top.par - 1
      else
        q = top.q
        stack[#stack] = nil
      end
      out[#out + 1] = c
      i = i + 1
    else
      if q == nil and (c == "'" or c == '"') then q = c elseif q == c then q = nil end
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat(out)
end

local function to_real_shell(s)
  if find_printf and type(s) == 'string' then s = find_printf.rewrite(s) end
  return to_real_shell_path(s)
end

local execute, popen = os.execute, io.popen
os.execute = function(cmd) return execute(to_real_shell(cmd)) end

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
  local f, err, code = popen(to_real_shell(cmd), mode)
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
    return f, to_virtual(file) -- the loader data (the chunk's second argument, require's second result)
  end
end
package.searchers[2] = search(function() return package.path end, function(file) return load_named(file) end)
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
  'choose_file', 'listdir',
}

-- a glob pattern goes out real and the matches come back virtual (SYSTEM > MODS and the mod loader scan "<code>*/lib/mod.lua" with it)
local system_glob = _norns.system_glob
if type(system_glob) == 'function' then
  _norns.system_glob = function(pattern, ...)
    local matches, status = system_glob(to_real(pattern), ...)
    if type(matches) == 'table' then
      for i, path in ipairs(matches) do matches[i] = to_virtual(path) end
    end
    return matches, status
  end
end

local function wrap_arg(a)
  if type(a) == 'function' then
    return function(...) return a(map(to_virtual, ...)) end
  end
  return to_real(a)
end
local function wrap_shell_arg(a)
  if type(a) == 'function' then
    return function(...) return a(map(to_virtual, ...)) end
  end
  return to_real_shell(a)
end
local SHELL_FUNCTIONS = {execute = true, system_cmd = true} -- their string is a shell command

for _, name in ipairs(PATH_FUNCTIONS) do
  local f = _norns[name]
  if type(f) == 'function' then
    local wrap = SHELL_FUNCTIONS[name] and wrap_shell_arg or wrap_arg
    _norns[name] = function(...) return map(to_virtual, f(map(wrap, ...))) end
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
