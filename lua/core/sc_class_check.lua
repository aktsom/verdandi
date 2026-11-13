-- the startup check of sclang.log (Linux desktop): a class that SuperCollider could not find ("Class 'X' not found", then the error that stops
-- an engine from building) and a class defined twice ("duplicate Class found"). one plain line per finding that names the folder, the class
-- and the likely cause. READ ONLY: nothing is moved or changed; the line says which command does that. the log is read from its end
-- (bounded). docs/port/mi-ugens.md section 5.
local M = {}

local TAIL = 256 * 1024

local function dir_of(p) return (p:match("^(.*)/[^/]*$")) or p end

-- the folder of a class file: <pack>/Classes/Foo.sc -> <pack>
local function folder_of(path)
  local d = dir_of(path)
  if d:match("/Classes$") then d = dir_of(d) end
  return d
end

local function inside(path, home)
  return home ~= nil and path:sub(1, #home + 1) == home .. "/"
end

local EXT = "/.local/share/SuperCollider/Extensions"

-- the findings of a log text. ctx = {home = norns home, pack = "own" | "foreign" | "none" (the state of the shipped mi-UGens copy), seeded = path of it}
function M.report(text, ctx)
  ctx = ctx or {}
  local home = ctx.home or "/home/we"
  local out, seen = {}, {}
  -- missing classes, in log order; the engine that was building comes from the trace ("Meta_Emplaitress:initClass")
  local first_engine = text:match("Meta_(%w+):initClass")
  for class in text:gmatch("Class '?([%w_]+)'? not found") do
    if not seen["m" .. class] then
      seen["m" .. class] = true
      local line
      local folder = ctx.ext or (home .. EXT)
      local who = first_engine and (" while " .. first_engine .. " was starting") or ""
      if class:match("^Mi%u") then
        local state
        if ctx.pack == "none" then state = "the pack is not in " .. folder .. "/mi-UGens (moved to disabled/, mi_ugens=0 in audio.conf, or another Mi*.sc kept it from being copied: see logs/launcher.log)"
        elseif ctx.pack == "own" then state = "the pack is in " .. folder .. "/mi-UGens, so SuperCollider was started before it was copied or its class file is damaged: restart norns"
        else state = "the class belongs to the mi-UGens pack, which is not in " .. folder .. "/mi-UGens" end
        line = "SuperCollider could not find class " .. class .. "(mi-UGens)" .. who .. ": likely cause: " .. state ..
          "; the engine that needs it is missing (SUPERCOLLIDER FAIL or no sound from it). nothing was changed"
        line = line:gsub("%(mi%-UGens%)", " (mi-UGens)")
      else
        line = "SuperCollider could not find class " .. class .. who .. ": likely cause: the extension or script that defines it is not in " ..
          folder .. " or dust/code, or it failed to compile (see logs/sclang.log). nothing was changed"
      end
      out[#out + 1] = {kind = "missing", class = class, line = line}
    end
  end
  -- duplicate classes: "ERROR: duplicate Class found: 'X' " and the two files; one finding per pair of folders
  local pairs_ = {}
  for class, a, b in text:gmatch("duplicate Class found: '([%w_]+)'[^\n]*\n([^\n]+)\n([^\n]+)\n") do
    local fa, fb = folder_of(a), folder_of(b)
    local key = fa .. "\0" .. fb
    local g = pairs_[key]
    if not g then
      g = {kind = "duplicate", a = fa, b = fb, classes = {}}
      pairs_[key] = g
      out[#out + 1] = g
    end
    local have = false
    for _, c in ipairs(g.classes) do if c == class then have = true end end
    if not have then g.classes[#g.classes + 1] = class end
  end
  for _, g in ipairs(out) do
    if g.kind == "duplicate" then
      -- the copy to move aside: the one that is not Verdandi's own seeded folder, and inside the norns home
      local seeded = ctx.seeded or (home .. EXT .. "/mi-UGens")
      local target = g.a == seeded and g.b or g.a
      local shown = {}
      for i = 1, math.min(3, #g.classes) do shown[i] = g.classes[i] end
      local names = table.concat(shown, ", ") .. (#g.classes > 3 and (" and " .. (#g.classes - 3) .. " more") or "")
      local cause = (g.classes[1]:match("^Mi%u") and "the same pack twice (a script or mod fetched its own copy of mi-UGens next to the one Verdandi installed)")
        or "the same extension twice (two copies of it in the extension folder and dust/code)"
      local fix
      if inside(target, home) then
        fix = "to fix: verdandi tidy disable '" .. target .. "' 'duplicate classes' (moves it into " .. home .. "/disabled/, restorable; also SYSTEM > CLEAN UP), then restart norns"
        g.fix = {target = target, why = "duplicate classes (" .. names .. ")"}
      else
        fix = "to fix: move one of the two folders out of SuperCollider's reach by hand, it is outside your norns home (never delete)"
      end
      g.line = "SuperCollider found classes twice (" .. names .. ", " .. #g.classes .. " in all) in " .. g.a .. " and " .. g.b ..
        ": likely cause: " .. cause .. "; SuperCollider will not start (SUPERCOLLIDER FAIL). nothing was changed. " .. fix
      g.a, g.b = nil, nil
    end
  end
  return out
end

-- the findings of a log file; only the last TAIL bytes are read. none if the file is not there
function M.scan(path, ctx)
  local f = io.open(path, "rb")
  if not f then return {} end
  local size = f:seek("end")
  local from = size > TAIL and size - TAIL or 0
  f:seek("set", from)
  local text = f:read("a") or ""
  f:close()
  if from > 0 then text = text:gsub("^[^\n]*\n", "", 1) end -- the first line is cut
  return M.report(text, ctx)
end

-- ONE plain line for all missing classes (the start-up check of the Windows build): "SuperCollider classes missing: Decimator, SmoothDecimator (sc3-plugins), MiPlaits (mi-UGens)"
function M.summary(findings)
  local names, packs = {}, {}
  for _, f in ipairs(findings or {}) do
    if f.kind == "missing" then
      local pack = f.class:match("^Mi%u") and "mi-UGens" or (f.class:match("^Nam") and "NamAmp") or "sc3-plugins or another extension"
      names[#names + 1] = f.class .. " (" .. pack .. ")"
    end
  end
  if #names == 0 then return nil end
  return "SuperCollider classes missing: " .. table.concat(names, ", ") .. "; engines that use them will not start (see logs/sclang.log)"
end

-- the class library did not compile ("Library has not been compiled successfully"): what failed, in plain words, for the log (line) and for the norns screen (detail: short lines). returns nil when the text
-- does not say so. the same logic is in windows/launcher/sc_fail.h (launcher.log); both are tested on real sclang output
function M.compile_failure(text)
  if not text or not text:find("Library has not been compiled", 1, true) then return nil end
  local names, count = {}, 0
  for c in text:gmatch("duplicate Class found: '([%w_]+)'") do
    count = count + 1
    if count <= 6 then names[#names + 1] = c end
  end
  if count > 0 then
    local p1, p2 = text:match("duplicate Class found: '[%w_]+'[^\n]*\n([^\n]+)\n([^\n]+)")
    local list = table.concat(names, ", ") .. (count > 6 and ", ..." or "")
    return {
      kind = "duplicate", count = count, classes = names, first = p1, second = p2,
      line = "SuperCollider did not start: two files define the same class (" .. count .. ": " .. list .. "); the first two files: " .. tostring(p1) .. " and " .. tostring(p2) ..
        ". restart norns: the copy that is not part of Verdandi's own packs is moved to disabled\\ at the start; two folders of your own are not touched: move one by hand",
      detail = {"SuperCollider failed:", "two files define", "the same class:", (names[1] or "?") .. (count > 1 and (" +" .. (count - 1)) or ""), "restart norns"},
    }
  end
  local msg = text:match("ERROR: ([^\n]+)")
  local file = text:match("in file '([^']+)'")
  local line = "SuperCollider did not start: its class library did not compile" .. (msg and (" (" .. msg:gsub("%s+$", "") .. ")") or "") ..
    (file and (" in the file " .. file .. ". move that file, or its folder, out of dust\\code and the extensions folders (never delete) and restart norns") or ". see logs\\sclang.log")
  local short = file and file:match("([^/\\]+)$") or nil
  return {kind = "error", line = line, file = file, detail = {"SuperCollider failed:", "class library did", "not compile", short and ("file " .. short:sub(1, 16)) or "see sclang.log", "move it out, restart"}}
end

-- the end of a log file (the last TAIL bytes), "" when it is not there
function M.tail(path)
  local f = io.open(path, "rb")
  if not f then return "" end
  local size = f:seek("end")
  f:seek("set", size > TAIL and size - TAIL or 0)
  local text = f:read("a") or ""
  f:close()
  return text
end

-- the standing note for the device window
function M.note(findings)
  if not findings or #findings == 0 then return nil end
  return "SUPERCOLLIDER: class problem, see SYSTEM > CLEAN UP"
end

return M
