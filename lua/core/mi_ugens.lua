-- the mi-UGens pack that Verdandi ships (Linux desktop): what the copy in the user's SuperCollider extension folder is, from the stamp that
-- linux/mi-ugens-seed.sh wrote with it. reads only. used by SYSTEM > CLEAN UP.
local M = {}

local function read_stamp(path)
  local f = io.open(path)
  if not f then return nil end
  local t = {}
  for line in f:lines() do
    local k, v = line:match("^(%w+)=(.*)$")
    if k then t[k] = v end
  end
  f:close()
  return t
end

-- {state = "none" | "foreign" | "own", serial, commit, built, verdandi}
function M.info(home)
  local dir = home .. "/.local/share/SuperCollider/Extensions/mi-UGens"
  local probe = io.open(dir .. "/.verdandi-stamp")
  if probe then probe:close() end
  if not probe then
    -- a folder opens on Linux and fails at the first read; a missing one does not open
    local d = io.open(dir)
    if d then d:close() return {state = "foreign"} end
    return {state = "none"}
  end
  local s = read_stamp(dir .. "/.verdandi-stamp")
  if not s or s.pack ~= "mi-UGens" or not s.commit then return {state = "foreign"} end
  return {state = "own", serial = tonumber(s.serial), commit = s.commit, built = s.built, verdandi = s.verdandi}
end

function M.line(i)
  if i.state == "none" then return nil end
  if i.state == "foreign" then return "mi-UGens: not from Verdandi, left as it is" end
  return "mi-UGens: " .. i.commit:sub(1, 7) .. ", shipped with Verdandi " .. (i.verdandi or "?")
end

function M.detail(i)
  if i.state ~= "own" then return M.line(i) or "" end
  return "built " .. (i.built or "?") .. " from v7b1/mi-UGens " .. i.commit:sub(1, 7) .. " (GPL-3.0-or-later; Mutable Instruments code MIT)"
end

return M
