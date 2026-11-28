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

--- M38: the real name of an ext folder entry ("[ext] bass/" -> "bass"), nil for any other entry.
-- the link name in dust/audio is "[ext] <name>" (platform/common/extfolders.h); a folder shows with a "/" after it.
util.ext_real_name = function(entry)
  return type(entry) == "string" and entry:match("^%[ext%] (.+)/$") or nil
end

--- M38: how the platform orders the names of a folder: a function less(a, b) for names without the "/".
-- Windows: the native listing sorts the bytes of the names (uppercase before lowercase), so the same here.
-- Linux: `ls` sorts with the locale of the user (case, accents, punctuation); the same `sort` program with the same environment gives the same order, one call for all the names given.
-- when it cannot be asked, the names are compared by the lower case text and then the bytes.
-- @tparam table names every name the order is needed for
util.dir_less = function(names)
  if _norns and _norns.listdir then
    return function(a, b) return a < b end
  end
  local rank
  local tmp = os.tmpname()
  local f = tmp and io.open(tmp, "wb")
  if f then
    local seen = {}
    for _, n in ipairs(names) do
      if not n:find("[\r\n]") and not seen[n] then
        seen[n] = true
        f:write(n, "\n")
      end
    end
    f:close()
    local out = _norns.execute and _norns.execute('sort "' .. tmp .. '"') or ""
    local r, k = {}, 0
    for line in tostring(out):gmatch("[^\r\n]+") do
      k = k + 1
      if r[line] == nil then r[line] = k end
    end
    if k > 0 then rank = r end
  end
  if tmp then os.remove(tmp) end
  return function(a, b)
    local ra, rb = rank and rank[a], rank and rank[b]
    if ra and rb then return ra < rb end
    local la, lb = a:lower(), b:lower()
    if la ~= lb then return la < lb end
    return a < b
  end
end

--- M38: put the ext folders of a folder listing in the place of their REAL name. the listing has them as "[ext] <name>/" (sorted by that text, so they landed among the "e" names); they are moved
-- inside the folder group to the place a normal folder called <name> would have, by the same rules as the other folders (util.dir_less). the normal entries do not move. an ext folder and a normal
-- folder with the same name: the normal folder first, the ext folder right after it (the real folder is the one that was there first, and the order never changes between two listings).
-- the shown text is not changed (the "[ext] " mark stays), nor the names.
-- @tparam table list a listing as util.scandir returns it
-- @tparam function less optional less(a, b) on names without "/" (for tests)
-- @treturn table the same list, ordered
util.ext_place = function(list, less)
  local ext, normal, files, any = {}, {}, {}, false
  for i, e in ipairs(list) do
    local real = util.ext_real_name(e)
    if real then
      ext[#ext + 1] = {entry = e, name = real, i = i}
      any = true
    elseif e:sub(-1) == "/" then
      normal[#normal + 1] = e
    else
      files[#files + 1] = e
    end
  end
  if not any then return list end
  if not less then
    local names = {}
    for _, x in ipairs(ext) do names[#names + 1] = x.name end
    for _, e in ipairs(normal) do names[#names + 1] = e:sub(1, -2) end
    less = util.dir_less(names)
  end
  -- the ext folders among themselves by real name; a tie keeps the order of the listing
  table.sort(ext, function(a, b)
    if less(a.name, b.name) then return true end
    if less(b.name, a.name) then return false end
    return a.i < b.i
  end)
  local out, e = {}, 1
  for _, n in ipairs(normal) do
    local nn = n:sub(1, -2)
    while e <= #ext and less(ext[e].name, nn) do
      out[#out + 1] = ext[e].entry
      e = e + 1
    end
    out[#out + 1] = n
  end
  while e <= #ext do
    out[#out + 1] = ext[e].entry
    e = e + 1
  end
  for _, f in ipairs(files) do out[#out + 1] = f end
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
