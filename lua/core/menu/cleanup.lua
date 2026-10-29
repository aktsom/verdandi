-- SYSTEM > CLEAN UP (computers only, see core/menu/system.lua): what Verdandi keeps in the norns home besides your own files, with sizes: things it moved out of the way
-- (disabled/), logs, crash reports, seeded packs, cache. docs/port/clean-layout.md section 3.
--   E2 chooses a line, K3 opens it or acts, K2 goes back. nothing is changed without a second K3 (K2 = no).
--   PROBLEM lines (a plug-in for another machine that stops SuperCollider): K3 moves it into disabled/ (restorable)
--   DISABLED: K3 lists the items, K3 on one restores it
--   REMOVE >N DAYS (E3 sets N): what is older than N days in disabled/, the old logs, the crash reports, the seeded packs and the cache; K3 removes exactly that
-- never touched: dust/ (scripts, samples, data, captures), audio.conf, ui.conf. the work is done by linux/tidy.sh (NORNS_TIDY, set by the launcher)

local m = {pos = 1, rows = {}, mode = "groups", items = {}, ipos = 1, confirm = nil, msg = nil}

local AGES = {30, 90, 180, 365}
m.age = 2 -- 90 days

local TIDY = os.getenv("NORNS_TIDY")
local HOME = os.getenv("NORNS_HOME") or "/home/we"

local function q(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

local function run(args)
  if TIDY == nil or TIDY == "" then return "" end
  return util.os_capture(q(TIDY) .. " " .. args .. " 2>&1") or ""
end

local function human(b)
  b = tonumber(b) or 0
  local units = {"B", "K", "M", "G"}
  local i = 1
  while b >= 1024 and i < #units do b = b / 1024; i = i + 1 end
  if i == 1 then return string.format("%d%s", b, units[i]) end
  if b < 10 then return string.format("%.1f%s", b, units[i]) end
  return string.format("%d%s", b, units[i])
end

local function fit(s, w)
  if screen.text_extents(s) <= w then return s end
  local n = #s
  while n > 1 do
    n = n - 1
    if screen.text_extents(s:sub(1, n) .. "..") <= w then return s:sub(1, n) .. ".." end
  end
  return ".."
end

-- the data: tidy list --tsv, and the plug-in problems the launcher's check left
local function load_data()
  local groups = {disabled = {}, logs = {}, logcurrent = {}, crash = {}, seeded = {}, cache = {}, notours = {}}
  for line in run("list --tsv"):gmatch("[^\n]+") do
    local g, id, name, epoch, bytes, extra = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t?(.*)$")
    if g and groups[g] then
      table.insert(groups[g], {id = id, name = name, epoch = tonumber(epoch) or 0, bytes = tonumber(bytes) or 0, extra = extra})
    end
  end
  local problems = {}
  local f = io.open(HOME .. "/.plugin-fix")
  if f then
    for line in f:lines() do
      local target, why = line:match("^([^\t]+)\t?(.*)$")
      if target then
        local probe = io.open(target, "r")      -- a file or a folder (a folder opens, then fails to read)
        local exists = probe ~= nil
        if probe then probe:close() end
        if not exists then exists = os.rename(target, target) and true or false end
        if exists then table.insert(problems, {target = target, why = why ~= "" and why or "wrong-architecture plug-in"}) end
      end
    end
    f:close()
  end
  return groups, problems
end

local function total(list) local t = 0 for _, e in ipairs(list) do t = t + e.bytes end return t end

local function older_preview()
  local out = run("remove-older " .. AGES[m.age])
  local n, size = out:match("(%d+) item%(s%), (%S+)")
  return tonumber(n) or 0, size or "0B"
end

local function build_rows()
  local groups, problems = load_data()
  m.groups = groups
  local rows = {}
  for _, p in ipairs(problems) do
    local base = p.target:match("([^/]+)/?$") or p.target
    table.insert(rows, {name = "PROBLEM", label = "ARM PLUG-INS", mid = "", right = fit(base, 60), problem = p})
  end
  local nd = #groups.disabled
  table.insert(rows, {name = "DISABLED", label = "DISABLED", mid = nd .. (nd == 1 and " item" or " items"), right = human(total(groups.disabled))})
  local runs = #groups.logs + #groups.logcurrent
  table.insert(rows, {name = "LOGS", label = "LOGS", mid = runs .. (runs == 1 and " run" or " runs"), right = human(total(groups.logs) + total(groups.logcurrent))})
  table.insert(rows, {name = "CRASHES", label = "CRASHES", mid = tostring(#groups.crash), right = human(total(groups.crash))})
  table.insert(rows, {name = "SEEDED", label = "SEEDED", mid = #groups.seeded .. (#groups.seeded == 1 and " pack" or " packs"), right = human(total(groups.seeded))})
  table.insert(rows, {name = "CACHE", label = "CACHE", mid = "", right = human(total(groups.cache))})
  local n, size = older_preview()
  m.older_n, m.older_size = n, size
  table.insert(rows, {name = "REMOVE", label = "REMOVE >" .. AGES[m.age] .. " DAYS", mid = "", right = n .. (n == 1 and " item " or " items ") .. size, remove = true})
  m.rows = rows
  m.pos = util.clamp(m.pos, 1, #rows)
end

m.init = function()
  m.mode, m.confirm, m.msg = "groups", nil, nil
  m.pos = 1
  build_rows()
end

m.deinit = norns.none

local function say(s) m.msg = s end

local function ask(text, action)
  m.confirm = {text = text, action = action, back = m.mode}
  m.mode = "confirm"
end

m.key = function(n, z)
  if z ~= 1 then return end
  if m.mode == "confirm" then
    if n == 3 then
      local c = m.confirm
      m.confirm, m.mode = nil, "groups"
      m.msg = c.action()
      m.pos = 1
      build_rows()
    elseif n == 2 then
      m.mode = m.confirm.back or "groups"
      m.confirm = nil
      say("nothing was changed")
    end
    _menu.redraw()
    return
  end
  if m.mode == "list" then
    if n == 2 then
      m.mode = "groups"
    elseif n == 3 and m.list_kind == "DISABLED" and m.items[m.ipos] then
      local it = m.items[m.ipos]
      ask("RESTORE " .. it.name .. "? K3 yes  K2 no", function()
        local out = run("restore " .. q(it.id))
        return out:match("restored") and "restored: it is back where it was" or ((out:match("[^\n]+") or "could not restore"):sub(1, 60))
      end)
    end
    _menu.redraw()
    return
  end
  if n == 2 then
    _menu.set_page("SYSTEM")
    return
  end
  if n == 3 then
    local row = m.rows[m.pos]
    if row.name == "PROBLEM" then
      local p = row.problem
      ask("MOVE " .. (p.target:match("([^/]+)/?$") or p.target) .. " to disabled/? K3 yes  K2 no", function()
        local out = run("disable " .. q(p.target) .. " " .. q(p.why))
        local ok = out:match("moved ")
        return ok and "moved to disabled/: restore it from DISABLED" or ((out:match("[^\n]+") or "could not move it"):sub(1, 60))
      end)
    elseif row.remove then
      if m.older_n > 0 then
        ask("REMOVE " .. m.older_n .. " items, " .. m.older_size .. "? K3 yes  K2 no", function()
          local out = run("remove-older " .. AGES[m.age] .. " --yes")
          return out:match("removed") and "removed" or ((out:match("[^\n]+") or "nothing removed"):sub(1, 60))
        end)
      else
        say("nothing is older than " .. AGES[m.age] .. " days")
      end
    else
      local kind = row.name
      local list = ({DISABLED = m.groups.disabled, LOGS = m.groups.logs, CRASHES = m.groups.crash, SEEDED = m.groups.seeded, CACHE = m.groups.cache})[kind] or {}
      if kind == "LOGS" then
        list = {}
        for _, e in ipairs(m.groups.logcurrent) do table.insert(list, e) end
        for _, e in ipairs(m.groups.logs) do table.insert(list, e) end
      end
      m.items, m.ipos, m.list_kind, m.mode = list, 1, kind, "list"
      if #list == 0 then m.mode = "groups"; say("nothing here") end
    end
    _menu.redraw()
  end
end

m.enc = function(n, delta)
  m.msg = nil
  if m.mode == "confirm" then return end
  if m.mode == "list" then
    if n == 2 then m.ipos = util.clamp(m.ipos + delta, 1, math.max(1, #m.items)) end
  elseif n == 2 then
    m.pos = util.clamp(m.pos + delta, 1, #m.rows)
  elseif n == 3 and m.rows[m.pos] and m.rows[m.pos].remove then
    m.age = util.clamp(m.age + (delta > 0 and 1 or -1), 1, #AGES)
    build_rows()
    m.pos = #m.rows
  end
  _menu.redraw()
end

m.redraw = function()
  screen.clear()
  if m.mode == "confirm" then
    screen.level(15)
    screen.move(0, 24)
    screen.text(fit(m.confirm.text:match("^(.-)%?") and (m.confirm.text:match("^(.-)%?") .. "?") or m.confirm.text, 128))
    screen.level(10)
    screen.move(0, 44)
    screen.text("K3 yes  K2 no")
    screen.update()
    return
  end
  if m.mode == "list" then
    screen.level(15)
    screen.move(0, 8)
    screen.text(m.list_kind .. (m.list_kind == "DISABLED" and "  K3 = RESTORE" or ""))
    local first = math.max(1, math.min(m.ipos - 2, #m.items - 4))
    for i = 0, 4 do
      local it = m.items[first + i]
      if it then
        screen.level(first + i == m.ipos and 15 or 4)
        screen.move(0, 20 + 10 * i)
        screen.text(fit(it.name, 84))
        screen.move(127, 20 + 10 * i)
        screen.text_right(human(it.bytes))
      end
    end
    screen.update()
    return
  end
  -- the group lines scroll (5 visible); the REMOVE line is pinned at the bottom
  local last = #m.rows - 1
  local first = math.max(1, math.min(m.pos - 2, last - 4))
  for i = 0, 4 do
    local r = m.rows[first + i]
    if r and first + i <= last then
      local y = 10 * (i + 1)
      if i == 4 and m.msg then
        screen.level(10)
        screen.move(0, y)
        screen.text(fit(m.msg, 128))
      else
        screen.level(first + i == m.pos and 15 or 4)
        screen.move(0, y)
        screen.text(r.label)
        if r.mid ~= "" then screen.move(98, y); screen.text_right(r.mid) end
        screen.move(127, y)
        screen.text_right(r.right)
      end
    end
  end
  local r = m.rows[#m.rows]
  screen.level(m.pos == #m.rows and 15 or 4)
  screen.move(0, 62)
  screen.text(r.label)
  screen.move(127, 62)
  screen.text_right(r.right)
  screen.update()
end

return m
