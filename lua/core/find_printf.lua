-- find_printf.lua: Windows build only (docs/port/phase-m9.md). the bundled busybox has no `find -printf`; scripts use it (the installer of twins: `find ... -type f -printf '%p!'`). a `-printf '<fmt>'` whose
-- directives are only %p (and %%) becomes `-exec printf '<fmt, %p as %s>' {} \;` (busybox has printf and find -exec). anything else (%f %h %s %T ..., a quote or a $ in the format) is left alone: it would fail as before,
-- but is never made to do something else. pure text: tested on Linux against GNU find (linux/tests/find_printf_test.lua).
local M = {}

-- the argument after "-printf" starting at position i (after the blanks): returns the text, the position after it, or nil
local function read_arg(s, i)
  local q = s:sub(i, i)
  if q == "'" then
    local e = s:find("'", i + 1, true)
    if not e then return nil end
    return s:sub(i + 1, e - 1), e + 1
  elseif q == '"' then
    local e = s:find('"', i + 1, true)
    if not e then return nil end
    return s:sub(i + 1, e - 1), e + 1
  end
  local w = s:match("^[^%s;|&()<>]+", i)
  if not w then return nil end
  return w, i + #w
end

-- the printf format and how many {} it takes, or nil when something in it cannot be done
local function convert(fmt)
  if fmt:find("[%$`']") then return nil end
  local out, n, i = {}, 0, 1
  while i <= #fmt do
    local c = fmt:sub(i, i)
    if c == "%" then
      local d = fmt:sub(i + 1, i + 1)
      if d == "p" then
        out[#out + 1] = "%s"
        n = n + 1
      elseif d == "%" then
        out[#out + 1] = "%%"
      else
        return nil
      end
      i = i + 2
    elseif c == "\\" then
      -- an escape of the format (\n, \t, \0, \\): printf reads the same ones
      out[#out + 1] = fmt:sub(i, i + 1)
      i = i + 2
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat(out), n
end

function M.rewrite(cmd)
  if type(cmd) ~= "string" or not cmd:find("-printf", 1, true) or not cmd:find("find", 1, true) then return cmd end
  local out, pos = {}, 1
  while true do
    local s, e = cmd:find("%-printf%s+", pos)
    if not s then break end
    -- "-printf" has to be a word of its own
    if s > 1 and not cmd:sub(s - 1, s - 1):match("%s") then
      out[#out + 1] = cmd:sub(pos, e)
      pos = e + 1
    else
      local fmt, after = read_arg(cmd, e + 1)
      local conv, n
      if fmt then conv, n = convert(fmt) end
      if conv then
        out[#out + 1] = cmd:sub(pos, s - 1)
        out[#out + 1] = "-exec printf '" .. conv .. "'" .. string.rep(" {}", n) .. " \\;"
        pos = after
      else
        out[#out + 1] = cmd:sub(pos, e)
        pos = e + 1
      end
    end
  end
  out[#out + 1] = cmd:sub(pos)
  return table.concat(out)
end

return M
