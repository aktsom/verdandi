-- an engine that failed to build (desktop builds): while a script waits for its engine, the part of logs/sclang.log written since the load began is
-- read; when sclang printed the error trace of that engine ("ERROR: Message 'ar' not understood" with "Engine_Autumn:alloc" in its call stack, usually
-- after "Class Decimator not found") the load is stopped at once instead of waiting for the 15 s timeout, with one plain line. READ ONLY.
-- docs/port/phase-m7.md section 4.
local M = {}

local TAIL = 256 * 1024
local BEFORE = 2500 -- how far before the trace of the engine its own error lines can lie

-- classes with a known home. the answer names the pack to install; any other class gets a general line
local PACKS = {
  Decimator = "sc3-plugins", SmoothDecimator = "sc3-plugins", Squiz = "sc3-plugins", Disintegrator = "sc3-plugins", MdaPiano = "sc3-plugins",
  NamAmp = "the NamAmp extension", NAM = "the NamAmp extension",
}

local function pack_of(class)
  if PACKS[class] then return PACKS[class] end
  if class:match("^Mi%u") then return "the mi-UGens pack" end
  return nil
end

-- the failure of `engine` in a log text: {engine=, class=, message=, line=, detail={...}} or nil
function M.find(text, engine)
  if not text or not engine or engine == "None" or engine == "" then return nil end
  local tag = "Engine_" .. engine .. ":"
  local from = 1
  while true do
    local i = text:find(tag, from, true)
    if not i then return nil end
    from = i + #tag
    local region = text:sub(math.max(1, i - BEFORE), i - 1)
    if text:sub(i, i + #tag + 4) == tag .. "alloc" then -- the call stack line itself: Engine_Autumn:alloc
      local class, message
      for c in region:gmatch("Class '?([%w_]+)'? not found") do class = c end
      for msg in region:gmatch("Message '([^']+)' not understood") do message = msg end
      -- an error trace has to be there: either the message or "ERROR:" before the stack
      if class or message or region:find("ERROR:", 1, true) then
        local f = {engine = engine, class = class, message = message}
        local why
        if class then
          local pack = pack_of(class)
          why = "class " .. class .. " is missing" .. (pack and ("; this needs " .. pack) or "; the extension that defines it is not installed")
          f.detail = {"engine " .. engine, "failed:", "class " .. class, "is missing" .. (pack and "." or ""), pack and ("needs " .. pack) or "extension not installed"}
        else
          why = "its code raised an error" .. (message and (" (message '" .. message .. "' not understood)") or "")
          f.detail = {"engine " .. engine, "failed:", "its code raised", "an error. see", "logs/sclang.log"}
        end
        f.why = why
        f.line = "engine " .. engine .. " failed: " .. why
        f.short = "engine " .. engine .. " failed"
        return f
      end
    end
  end
end

function M.size(path)
  local f = io.open(path, "rb")
  if not f then return 0 end
  local s = f:seek("end")
  f:close()
  return s or 0
end

-- the text written since byte `pos` (at most the last TAIL bytes of it)
function M.since(path, pos)
  local f = io.open(path, "rb")
  if not f then return "" end
  local size = f:seek("end")
  if size < (pos or 0) then pos = 0 end -- the log was replaced by a shorter one
  local from = math.max(pos or 0, size - TAIL)
  f:seek("set", from)
  local text = f:read("a") or ""
  f:close()
  return text
end

function M.check(path, pos, engine)
  if M.size(path) <= (pos or 0) then return nil end
  return M.find(M.since(path, pos), engine)
end

return M
