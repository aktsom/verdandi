--- Script class
-- @module script
-- @alias Script

local hook = require 'core/hook'

local Script = {}

-- Linux desktop (docs/port/KNOWN-ISSUES.md 29): a clear that cannot be stopped by one failing step, mod cleanup hooks only for a script that was started, a load that is waiting for its engine is
-- cancelled by the next clear, and a load that takes more than 15 s says so. everything else is upstream's code
local desktop = os.getenv("NORNS_PLATFORM") ~= nil
Script.WATCHDOG_SECONDS = 15
Script.mods_armed = false -- a script reached its pre_init hooks since the last cleanup hooks ran
Script.load_pending = nil -- {engine = name, t = the time the load began, warned = bool} while an engine load is waiting

local function try(name, f)
  if not desktop then return f() end
  local ok, err = pcall(f)
  if not ok then print("### script clear: " .. name .. " failed: " .. tostring(err)) end
end

--- a load that is still waiting for its engine: one line, once, with what it waits for
Script.check_load = function()
  local p = Script.load_pending
  if p == nil or p.warned or util.time() - p.t < Script.WATCHDOG_SECONDS then return end
  p.warned = true
  print("### script load is taking longer than " .. Script.WATCHDOG_SECONDS .. " s: still waiting for engine " .. tostring(p.engine)
    .. " (sclang busy or not answering? see logs/sclang.log)")
end

local function load_done()
  Script.load_pending = nil
  if Script.load_metro then pcall(function() Script.load_metro:stop() end) Script.load_metro = nil end
end

--- reset script environment.
-- ie redirect draw, key, enc functions, stop timers, clear engine, etc.
Script.clear = function()
  print("# script clear")
  _norns.free_engine()
  if desktop then
    -- whatever was loading is cancelled with its engine: a pending flag left behind would refuse every later engine.load (the next script never started)
    engine.is_loading = false
    Script.load_pending, Script.load_metro = nil, nil
  end

  if cleanup ~= nil then
    local ok, err
    ok, err = pcall(cleanup)
    if not ok then
      print("### cleanup failed with error: "..err)
    end
  end

  -- allow mods to do cleanup (desktop: only for a script that was started: the clear after a failed load must not run them again against parameters the first clear removed)
  if not desktop or Script.mods_armed then
    Script.mods_armed = false
    try("mod cleanup hooks", function() hook.script_post_cleanup() end)
  end

  -- unload asl package entry so `require 'asl'` works
  -- todo(pq): why is this not needed generally (e.g., for 'ui', 'util', etc.)?
  if package.loaded['asl'] ~= nil then
    package.loaded['asl'] = nil
  end

  if norns.lfo ~= nil then
    try("lfo", function() norns.lfo.lattice:destroy() end)
    norns.lfo = nil
  end

  -- reset embedded modules
  json = _json

  -- script local state
  local state = { }

  setmetatable(_G, {
    __index = function (_,k)
      return state[k]
    end,
    __newindex = function(_,k,v)
      state[k] = v
    end,
  })

  -- reset cleanup script
  cleanup = norns.none

  -- reset refresh callback
  refresh = norns.none

  -- reset oled redraw
  redraw = norns.blank

  -- redirect inputs to nowhere
  key = norns.none
  enc = norns.none

  -- reset encoders
  try("encoders", function() norns.enc.accel(0,true) norns.enc.sens(0,2) end)

  -- clear, redirect, and reset devices
  try("grid", function() grid.cleanup() end)
  try("arc", function() arc.cleanup() end)
  try("midi", function() midi.cleanup() end)
  try("hid", function() hid.cleanup() end)
  try("osc", function() osc.cleanup() end)

  -- stop all timers
  try("metros", function() metro.free_all() end)

  -- stop clock
  try("clock", function() clock.cleanup() end)

  -- stop all polls and clear callbacks
  try("polls", function() poll.clear_all() end)

  -- clear engine
  engine.name = nil

  -- clear softcut
  try("softcut", function() softcut.reset() end)

  -- restore default audio routing
  try("audio routing", function()
    if audio.routing_is_altered() then
      print("# restoring default audio routing")
      audio.routing_default()
    end
  end)

  -- clear init
  init = norns.none

  -- clear crow functions
  try("crow", function() norns.crow.init() end)

  -- clear HID device handlers
  try("keyboard", function() keyboard.clear() end)
  try("gamepad", function() gamepad.clear() end)

  -- clear last run
  norns.state.script = ''
  norns.state.name = 'none'
  norns.state.shortname = 'none'
  norns.state.path = _path["dust"]
  norns.state.data = _path.data
  norns.state.lib = norns.state.path
  norns.version.required = nil

  -- clear params
  try("params", function()
    params:clear()
    norns.pmap.clear()
    -- add audio menu
    audio.add_params()
    -- add clock menu
    clock.add_params()
    -- re-enable crow clock if needed
    if params:string("clock_source") == "crow" then
      crow.input[1].change = function() end
      crow.input[1].mode("change",2,0.1,"rising")
    end
  end)

  -- reset PLAY mode screen settings
  local status = norns.menu.status()
  if status == true then _norns.screen_restore() end

  screen.aa(0)
  screen.level(15)
  screen.line_width(1)
  screen.font_face(1)
  screen.font_size(8)

  if status == true then _norns.screen_save() end

  -- ensure finalizers run before next script
  collectgarbage()
end

Script.init = function()
  print("# script init")
  params.name = norns.state.shortname
  init()
  hook.script_post_init()
  _norns.screen_save()
end



--- load a script from the /scripts folder.
-- @tparam string filename file to load. leave blank to reload current file.
Script.load = function(filename)
  local name, path
  if filename == nil then
    filename = norns.state.script
    name = norns.state.name
    path = norns.state.path
  else
    filename = string.sub(filename,1,1) == "/" and filename or _path["dust"]..filename
    path, scriptname = filename:match("^(.*)/([^.]*).*$")
    name = string.sub(path, string.len(_path["code"]) + 1)
    -- append scriptname to the name if it doesn't match directory name in case multiple scripts reside in the same directory
    -- ex: we/study/study1, we/study/study2, ...
    if string.sub(name, -#scriptname) ~= scriptname then
      name_parts = tab.split(name, "/")
      table.insert(name_parts, scriptname)
      name = table.concat(name_parts, "/")
    end
  end

  local f=io.open(filename,"r")
  if f==nil then
    print("# script load failed, file not found: " .. filename)
  else
    io.close(f)

    Script.clear() -- clear script variables and functions

    print("# script load: " .. filename)

    norns.state.script = filename
    norns.state.name = name
    norns.state.shortname = norns.state.name:match( "([^/]+)$" )
    norns.state.path = path .. '/'
    norns.state.lib = path .. '/lib/'
    norns.state.data = _path.data .. name .. '/'
    norns.state.pset_last = 1

    if util.file_exists(norns.state.data) == false then
      print("### initializing data folder")
      util.make_dir(norns.state.data)
      if util.file_exists(norns.state.path.."/data") then
        _norns.execute("cp "..norns.state.path.."/data/*.pset "..norns.state.data)
        print("### copied default psets")
      end
    end

    local file = norns.state.data.."pset-last.txt"
    if util.file_exists(file) then
      local f = io.open(file,"r")
      io.input(f)
      local i = io.read("*line")
      io.close(f)
      if i then
        print("pset last used: "..i)
        norns.state.pset_last = tonumber(i)
      end
    end

    local status = norns.try(function() dofile(filename) end, "load fail") -- do the new script
    if status == true then
      norns.state.save() -- remember this script for next launch
      norns.script.nointerface = redraw == norns.blank -- check if redraw is present
      norns.script.redraw = redraw -- store redraw function for context switching
      norns.script.refresh = refresh -- store refresh function for context switching
      redraw = norns.none -- block redraw until Script.init
      refresh = norns.none -- block refresh until Script.init
      Script.run() -- load engine then run script-specified init function
    else
      Script.clear()
    end
  end
end

--- load engine, execute script-specified init (if present).
Script.run = function()
  if tonumber(norns.version.required) and tonumber(norns.version.required) > tonumber(norns.version.update) then
    norns.scripterror("version " .. norns.version.required .. " required")
    Script.clear()
    return
  end
  -- allow mods to do initialization
  hook.script_pre_init()
  Script.mods_armed = true

  print("# script run")
  local name = engine.name ~= nil and engine.name or "None"
  if engine.name ~= nil then print("loading engine: " .. engine.name) end
  if desktop then
    Script.load_pending = {engine = name, t = util.time(), warned = false}
    if metro and metro.init then
      local ok, m = pcall(metro.init, function() Script.check_load() end, 5, -1)
      if ok and m then Script.load_metro = m; m:start() end
    end
    local started = engine.load(name, function()
      load_done()
      Script.init()
    end)
    if not started then
      print("### engine " .. name .. " was not loaded (a load is pending, or the engine is not known): the script does not start")
      load_done()
    end
  else
    engine.load(name, Script.init)
  end
  norns.pmap.read() -- load parameter map
end

--- load script metadata.
-- @tparam string filename file to load
-- @treturn table meta table with metadata
Script.metadata = function(filename)
  local meta = {}
  local f=io.open(filename,"r")
  if f==nil then
    print("file not found: "..filename)
  else
    io.close(f)
    for line in io.lines(filename) do
      if util.string_starts(line,"--") then
        local skip_hyphens = string.sub(line,4,-1)
        local fix_newlines = string.gsub(skip_hyphens,"\r$","")
        table.insert(meta, fix_newlines)
      else
        if #meta == 0 then
          table.insert(meta, "no script information")
        end
        return meta
      end
    end
  end
  return meta
end



return Script
