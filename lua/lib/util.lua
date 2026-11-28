--- Utility functions.
-- @module lib.util

util = {}

--- db to amp.
-- @tparam number db
-- @treturn number amp
util.dbamp = function(db)
  if db < -80 then db = -math.huge end
  return math.pow(10,db*0.05)
end

--- get system time in fractional seconds
-- @return time
util.time = function()
  local s,us = _norns.get_time()
  return s + us/1000000
end


--- scan directory, return file list.
-- @tparam string directory path to directory
-- @treturn table
util.scandir = function(directory)
  local i, t = 0, {}
  if _norns.listdir then -- Windows build: a native listing, same shape as `ls -p` (folders first, "/" after a folder name, no hidden names)
    return util.ext_place(_norns.listdir(directory) or t)
  end
  local text = _norns.execute('ls -pL --group-directories-first "'..directory..'"')
    for filename in text:gmatch("[^\r\n]+") do
    i = i + 1
    t[i] = filename
  end
  return util.ext_place(t)
end

--- M38/M42: the real name of an ext folder entry ("[ext] bass/" -> "bass"), nil for any other entry.
-- the link name in dust/audio is "[ext] <name>" (platform/common/extfolders.h); a folder shows with a "/" after it.
util.ext_real_name = function(entry)
  return type(entry) == "string" and entry:match("^%[ext%] (.+)/$") or nil
end

-- the order of names on the SYSTEM > EXT FOLDERS page (core/menu/extra.lua, M33): case is ignored; a name is cut into runs of digits and runs of other characters; two digit runs are compared as
-- numbers (2 before 10; the same number: the shorter run first, so 2 before 02); a digit run comes before a text run (a name that starts with a digit comes before one that starts with a letter);
-- text runs compare as lower case; a tie ends with the exact text, so the order is always the same
local function natural_runs(name)
  local out = {}
  for digits, text in tostring(name):gmatch("(%d*)(%D*)") do
    if digits ~= "" then out[#out + 1] = {digit = true, text = digits} end
    if text ~= "" then out[#out + 1] = {digit = false, text = text:lower()} end
  end
  return out
end

--- is a before b in that order? (a copy of core/menu/extra.lua's natural_less: linux/tests/ext_sort_test.lua checks that both give one order)
util.natural_less = function(a, b)
  local ra, rb = natural_runs(a), natural_runs(b)
  for i = 1, math.min(#ra, #rb) do
    local x, y = ra[i], rb[i]
    if x.digit ~= y.digit then return x.digit end
    if x.digit then
      local nx, ny = tonumber(x.text), tonumber(y.text)
      if nx ~= ny then return nx < ny end
      if #x.text ~= #y.text then return #x.text < #y.text end
    elseif x.text ~= y.text then
      return x.text < y.text
    end
  end
  if #ra ~= #rb then return #ra < #rb end
  return tostring(a) < tostring(b)
end

--- M42: the ext folders of a folder listing go together at the top of the list, A to Z among themselves by their REAL name (the rules of the SYSTEM > EXT FOLDERS page: util.natural_less), with the
-- "[ext] " mark kept in the shown text. every other entry follows, in the order the platform gave it (as it was before the ext folders were sorted at all). a normal folder with the same name as an ext
-- folder is a normal entry: it stays where the platform put it. a listing without an ext folder is returned as it is. one place for every file browser (fileselect, the params file picker): util.scandir
-- @tparam table list a listing as util.scandir returns it
-- @treturn table the same list when there is no ext folder, else a new one
util.ext_place = function(list)
  local ext, rest = {}, {}
  for i, e in ipairs(list) do
    local real = util.ext_real_name(e)
    if real then
      ext[#ext + 1] = {entry = e, name = real, i = i}
    else
      rest[#rest + 1] = e
    end
  end
  if #ext == 0 then return list end
  -- among themselves by real name; two with one real name (not possible through the EXT FOLDERS page) keep the order of the listing
  table.sort(ext, function(a, b)
    if util.natural_less(a.name, b.name) then return true end
    if util.natural_less(b.name, a.name) then return false end
    return a.i < b.i
  end)
  local out = {}
  for _, x in ipairs(ext) do out[#out + 1] = x.entry end
  for _, e in ipairs(rest) do out[#out + 1] = e end
  return out
end

--- check if file exists.
-- @tparam string name filepath
-- @treturn boolean true/false
util.file_exists = function(name)
  local f=io.open(name,"r")
  if f~=nil then
    io.close(f)
    return true
  elseif _norns ~= nil and _norns.path_is_dir ~= nil then
    -- Windows (Verdandi): fopen refuses to open a folder, where a norns (Linux) opens it, so on a norns this is true for a folder too and scripts rely on it
    -- (util.file_exists(_path.code.."nb"), cheat codes 2: util.file_exists(_path.code.."cheat_codes_2/lib/nb/lib/")). the native check asks the system whether the name is a folder
    return _norns.path_is_dir(name)
  else
    return false
  end
end

--- query file size.
-- @tparam string path filepath
-- @treturn number filesize in bytes
util.file_size = function(path)
  if path ~= nil then
    local f = io.open(path,"r")
    if f~=nil then
      local s = f:seek("end") -- get file size
      io.close(f)
      return s
    else
      error("no file found at "..path)
    end
  else
    error("util.file_size requires a path")
  end
end

--- make directory (with parents as needed).
-- @tparam string path
util.make_dir = function(path)
  _norns.execute("mkdir -p " .. path)
end


--- execute os command, capture output.
-- @tparam string cmd command
-- @param raw raw output (omit for scrubbed)
-- @return output
util.os_capture = function(cmd, raw)
  local s = _norns.execute(cmd)
  if raw then return s end
  s = string.gsub(s, '^%s+', '')
  s = string.gsub(s, '%s+$', '')
  s = string.gsub(s, '[\n\r]+', ' ')
  return s
end

--- string begins with.
-- @tparam string s string to examine
-- @tparam string start string to search for
-- @treturn boolean true or false
util.string_starts = function(s,start)
	if s then
		return string.sub(s,1,string.len(start))==start
	else return false
	end
end

--- trim string to a display width
-- @tparam string s string to trim
-- @tparam number width maximum width
-- @treturn string trimmed string
util.trim_string_to_width = function(s, width)
  if _norns.screen_text_extents(s) > width then
    while _norns.screen_text_extents(s .. "...") > width do
      s = string.gsub(s, "[^\128-\191][\128-\191]*$", "")
    end
    s = s .. "..."
  end
  return s
end

--- clamp values to min max.
-- @tparam number n value
-- @tparam number min minimum
-- @tparam number max maximum
-- @treturn number clamped value
util.clamp = function(n, min, max)
  return math.min(max,(math.max(n,min)))
end

-- linlin, linexp, explin, expexp ripped from SC source code
-- https://github.com/supercollider/supercollider/blob/cca12ff02a774a9ea212e8883551d3565bb24a6f/lang/LangSource/MiscInlineMath.h

--- convert a linear range to an exponential range
-- @tparam number slo lower limit of input range
-- @tparam number shi upper limit of input range
-- @tparam number dlo lower limit of output range (must be non-zero and of the same sign as dhi)
-- @tparam number dhi upper limit of output range (must be non-zero and of the same sign as dlo)
-- @tparam number f input to convert
-- @treturn number
function util.linexp(slo, shi, dlo, dhi, f)
  if f <= slo then
    return dlo
  elseif f >= shi then
    return dhi
  else
    return math.pow( dhi/dlo, (f-slo) / (shi-slo) ) * dlo
  end
end

--- map a linear range to another linear range.
-- @tparam number slo lower limit of input range
-- @tparam number shi upper limit of input range
-- @tparam number dlo lower limit of output range
-- @tparam number dhi upper limit of output range
-- @tparam number f input to convert
-- @treturn number
function util.linlin(slo, shi, dlo, dhi, f)
  if f <= slo then
    return dlo
  elseif f >= shi then
    return dhi
  else
    return (f-slo) / (shi-slo) * (dhi-dlo) + dlo
  end
end

--- convert an exponential range to a linear range.
-- @tparam number slo lower limit of input range (must be non-zero and of the same sign as shi)
-- @tparam number shi upper limit of input range (must be non-zero and of the same sign as slo)
-- @tparam number dlo lower limit of output range
-- @tparam number dhi upper limit of output range
-- @tparam number f input to convert
-- @treturn number
function util.explin(slo, shi, dlo, dhi, f)
  if f <= slo then
    return dlo
  elseif f >= shi then
    return dhi
  else
    return math.log(f/slo) / math.log(shi/slo) * (dhi-dlo) + dlo
  end
end

--- map an exponential range to another exponential range.
-- @tparam number slo lower limit of input range (must be non-zero and of the same sign as shi)
-- @tparam number shi upper limit of input range (must be non-zero and of the same sign as slo)
-- @tparam number dlo lower limit of output range (must be non-zero and of the same sign as dhi)
-- @tparam number dhi upper limit of output range (must be non-zero and of the same sign as dlo)
-- @tparam number f input to convert
-- @treturn number
function util.expexp(slo, shi, dlo, dhi, f)
  if f <= slo then
    return dlo
  elseif f >= shi then
    return dhi
  else
    return math.pow(dhi/dlo, math.log(f/slo) / math.log(shi/slo)) * dlo
  end
end

--- round to a multiple of a number
-- @tparam number number to round
-- @tparam number quant precision to round to
function util.round(number, quant)
  if quant == 0 then
    return number
  else
    return math.floor(number/(quant or 1) + 0.5) * (quant or 1)
  end
end

--- round up to a multiple of a number.
-- @tparam number number to round
-- @tparam number quant precision to round to
function util.round_up(number, quant)
  if quant == 0 then
    return number
  else
    return math.ceil(number/(quant or 1)) * (quant or 1)
  end
end

--- format string, seconds to h:m:s.
-- @tparam number s seconds
-- @treturn string seconds : seconds in h:m:s
function util.s_to_hms(s)
  local m = math.floor(s/60)
  local h = math.floor(m/60)
  m = m%60
  s = s%60
  return h ..":".. string.format("%02d",m) ..":".. string.format("%02d",s)
end

--- convert degrees to radians
-- @tparam number degrees
-- @treturn number radians
function util.degs_to_rads(degrees)
  return degrees * (math.pi / 180)
end

--- convert radians to degrees
-- @tparam number radians
-- @treturn number degrees
function util.rads_to_degs(radians)
  return radians * (180 / math.pi)
end

--- convert string to acronym
-- @tparam string name
-- @treturn string acronym
function util.acronym(name)
  name = name:gsub( "[%w']+", function( word )
    if not word:find "%U" then  return word  end
    return word:sub( 1, 1 )
  end )
  return (name:gsub("%s+", ""))
end

--- wrap a integer to a positive min/max range
-- @tparam integer n
-- @tparam integer min
-- @tparam integer max
-- @treturn integer cycled value
function util.wrap(n, min, max)
  if max < min then
    local temp = min
    min = max
    max = temp
  end
  if n >= min and n <= max then
    return n
  end
  local d = max - min + 1
  local y = (n - min) % d
  return y + min
end

--- wrap an integer to a positive min/max range but clamp the min
-- @tparam integer n
-- @tparam integer min
-- @tparam integer max
-- @treturn integer cycled value
function util.wrap_max(n, min, max)
  if max < min then
    local temp = min
    min = max
    max = temp
  end
  if n < min then
    return min
  end
  return util.wrap(n, min, max)
end

--- list the scripts below a code folder, as `find ... | grep -Ev "/(lib|data|crow|test|docs)/" | sort` does.
-- used where there is no find/grep (the Windows build); `listdir` is _norns.listdir, a parameter so that it can be tested.
-- @tparam string root path of the code folder, with a trailing "/"
-- @tparam function listdir function(path) -> table of names, folders with a trailing "/"
-- @treturn string the relative paths of the .lua files, one per line (at least one folder deep)
util.script_tree = function(root, listdir)
  listdir = listdir or _norns.listdir
  local out = {}
  local skip = {lib = true, data = true, crow = true, test = true, docs = true}
  local function walk(rel, depth)
    for _, name in ipairs(listdir(root .. rel) or {}) do
      if name:sub(-1) == "/" then
        local dir = name:sub(1, -2)
        if dir:sub(1, 1) ~= "." and not skip[dir] then
          walk(rel .. name, depth + 1)
        end
      elseif depth >= 1 and name:sub(-4) == ".lua" and name:sub(1, 1) ~= "." then
        out[#out + 1] = rel .. name
      end
    end
  end
  walk("", 0)
  table.sort(out)
  return table.concat(out, "\n")
end

--- names in a folder, one per line (instead of `ls`); "" when there is no native listing (not the Windows build)
util.ls_text = function(directory)
  if not _norns.listdir then return "" end
  return table.concat(_norns.listdir(directory) or {}, "\n")
end

--- copy a file by reading and writing it (instead of `cp`).
util.copy_file = function(from, to)
  local text = util.read_text(from)
  local f = io.open(to, "wb")
  if not f then return false end
  f:write(text)
  f:close()
  return true
end

--- read a whole text file, "" when it cannot be read (instead of `cat`).
util.read_text = function(name)
  local f = io.open(name, "rb")
  if not f then return "" end
  local text = f:read("a") or ""
  f:close()
  return text
end

return util
