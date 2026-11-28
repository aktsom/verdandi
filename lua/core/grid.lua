--- Grid class
--
-- The [norns script reference](https://monome.org/docs/norns/reference/)
-- has [examples for this module](https://monome.org/docs/norns/reference/grid).
--
-- @module grid
-- @alias Grid

local vport = require 'vport'

local Grid = {}
Grid.__index = Grid

Grid.devices = {}
Grid.vports = {}

for i=1,4 do
  Grid.vports[i] = {
    name = "none",
    device = nil,

    key = nil,
    tilt = nil,
    
    led = vport.wrap_method('led'),
    all = vport.wrap_method('all'),
    refresh = vport.wrap_method('refresh'),
    rotation = vport.wrap_method('rotation'),
    intensity = vport.wrap_method('intensity'),
    tilt_enable = vport.wrap_method('tilt_enable'),
    
    cols = 0,
    rows = 0,
  }
end

-- constructor
-- @tparam integer id : arbitrary numeric identifier
-- @tparam string serial : serial
-- @tparam string name : name
-- @tparam userdata dev : opaque pointer to device
function Grid.new(id, serial, name, dev)
  local g = setmetatable({}, Grid)

  g.id = id
  g.serial = serial
  g.name = name.." "..serial
  g.dev = dev -- opaque pointer
  g.key = nil -- key event callback
  g.tilt = nil -- tilt event callback
  g.remove = nil -- device unplug callback
  g.rows = _norns.grid_rows(dev)
  g.cols = _norns.grid_cols(dev)
  g.port = nil

  -- autofill next postiion
  local connected = {}
  for i=1,4 do
    table.insert(connected, Grid.vports[i].name)
  end
  if not tab.contains(connected, g.name) then
    for i=1,4 do
      if Grid.vports[i].name == "none" then
        Grid.vports[i].name = g.name
        break
      end
    end
  end

  return g
end

--- static callback when any grid device is added;
-- user scripts can redefine
-- @static
-- @param dev : a Grid table
function Grid.add(dev)
  print("grid added:", dev.id, dev.name, dev.serial)
end

--- static callback when any grid device is removed;
-- user scripts can redefine
-- @static
-- @param dev : a Grid table
function Grid.remove(dev) end

--- set grid rotation.
-- @tparam integer val : rotation 0,90,180,270 as [0, 3]
function Grid:rotation(val)
  _norns.grid_set_rotation(self.dev, val)
  self.rows = _norns.grid_rows(self.dev)
  self.cols = _norns.grid_cols(self.dev)
  Grid.update_devices()
end

--- enable/disable grid tilt.
-- @tparam integer id : sensor
-- @tparam integer val : off/on [0, 1]
function Grid:tilt_enable(id, val)
  if (val == 1) then
    _norns.grid_tilt_enable(self.dev, id)
  else
    _norns.grid_tilt_disable(self.dev, id)
  end
end

--- set state of single LED on this grid device.
-- @tparam integer x : column index (1-based!)
-- @tparam integer y : row index (1-based!)
-- @tparam integer val : LED brightness level in [0, 15]
-- @tparam bool rel : relative brightness (add to existing level)
function Grid:led(x, y, val, rel)
  _norns.grid_set_led(self.dev, x, y, val, rel)
end

--- set state of all LEDs on this grid device.
-- @tparam integer val : LED brightness level in [0, 15]
-- @tparam bool rel : relative brightness (add to existing level)
function Grid:all(val, rel)
  _norns.grid_all_led(self.dev, val, rel)
end

--- update any dirty quads on this grid device.
function Grid:refresh()
  _norns.monome_refresh(self.dev)
end

--- intensity
-- @tparam integer i : intensity [0, 15]
function Grid:intensity(i)
  _norns.monome_intensity(self.dev, i)
end

--- create device, returns object with handler and send.
-- @static
-- @tparam integer n : vport index
function Grid.connect(n)
  local n = n or 1

  return Grid.vports[n]
end

--- clear handlers.
-- @static
function Grid.cleanup()
  for i=1,4 do
    Grid.vports[i].key = nil
    Grid.vports[i].tilt = nil
  end

  for _, dev in pairs(Grid.devices) do
    dev:all(0)
    dev:refresh()
    dev.key = nil
    dev.tilt = nil
  end

  Grid.add = function(dev)
    print("grid added:", dev.id, dev.name, dev.serial)
  end

  Grid.remove = function(dev) end
end

-- update devices.
-- @static
function Grid.update_devices()
  -- build list of available devices
  Grid.list = {}
  for _,device in pairs(Grid.devices) do
    device.port = nil
  end

  -- connect available devices to vports
  for i=1,4 do
    Grid.vports[i].device = nil
    Grid.vports[i].rows = 0
    Grid.vports[i].cols = 0       

    for _,device in pairs(Grid.devices) do
      if device.name == Grid.vports[i].name then
        Grid.vports[i].device = device
        Grid.vports[i].rows = device.rows
        Grid.vports[i].cols = device.cols
        device.port = i
      end
    end
  end
  if Grid.publish_peer then Grid.publish_peer() end
end

_norns.grid = {}

-- Linux desktop, M43 (docs/port/phase-m43.md): the switch between a real grid and the virtual grid. until now the virtual grid only joined the list: with a real grid on port 1 it got port 2, and the
-- script stayed on the real grid until the owner chose the device again on SYSTEM > DEVICES > GRID (and the other way round at the next removal). now the virtual grid is the active grid at once
-- (it takes port 1, the grid that had port 1 moves to the virtual grid's place), and when it goes the grid that was active before takes port 1 back; keys that were held on the grid that is left are
-- let go for the script (a key-up for each), the picture the script has drawn is on the grid that takes over (the copy of the LEDs is done in C, matron/src/device/device_monome.cc, before this
-- runs), a grid that is left is dark unless a script listens on its new port, and the script is told again that there is a grid (Grid.add) so that it reads the size again
local switching = os.getenv("NORNS_PLATFORM") == "linux"
local guarded_key -- (defined below with the key handler)
local VIRTUAL = "^virtual grid"
local held = {} -- [device id] = {["x,y"] = {x, y}}: the keys that are down on each grid (to be let go for the script when its grid is left)
Grid.switch = nil -- {prev = the name of the grid that had port 1 before the virtual grid took it}

local function is_virtual(g)
  return g ~= nil and g.name ~= nil and g.name:find(VIRTUAL) ~= nil
end

-- the script hears a key-up for every key that is down on this grid, then the table is empty
local function let_go(g)
  local keys = held[g.id]
  held[g.id] = nil
  if not keys then return end
  for _, k in pairs(keys) do
    if g.key ~= nil then guarded_key("grid key", g.key, k[1], k[2], 0) end
    if g.port and Grid.vports[g.port] and Grid.vports[g.port].key then guarded_key("grid key", Grid.vports[g.port].key, k[1], k[2], 0) end
  end
end

-- M45 (docs/port/phase-m45.md): the virtual grid never moves a real grid's slot for good. what it changes (its own slot 1, and the first free slot for the real grid it has pushed out of slot 1) is
-- written down with the value before ({slot = {set = what the switch wrote, pre = what was there}}), and at the end only these slots are put back, and only those that still hold what the switch wrote
-- (a slot the owner changed on SYSTEM > DEVICES > GRID in the meantime stays as the owner left it). the saved settings (core/state.lua) get the "pre" values too, so that a restart with the virtual grid on
-- does not make its slot the saved setting.
local function slot_names()
  local t = {}
  for i = 1, 4 do t[i] = Grid.vports[i].name end
  return t
end

-- the name a slot has in the saved settings: what it had before the switch, while the virtual grid is on and the slot still holds what the switch wrote
function Grid.persistent_name(i)
  local nm = Grid.vports[i].name
  local sw = Grid.switch
  if sw and sw.ov and sw.ov[i] and sw.ov[i].set == nm then return sw.ov[i].pre end
  return nm
end

-- the real grid that takes slot 1 back when the virtual grid goes (or that is in slot 1 now, with no virtual grid): its device is told to the C side, which copies the LEDs between it and the virtual grid
local function publish_peer()
  if not (switching and _norns.grid_peer) then return end
  local peer
  local sw = Grid.switch
  local want = sw and sw.prev or Grid.vports[1].name
  for _, d in pairs(Grid.devices) do
    if not is_virtual(d) and d.name == want then peer = d end
  end
  _norns.grid_peer(peer and peer.dev or nil)
end

Grid.publish_peer = publish_peer

-- the virtual grid was added (pre: the slot names before it was added): it is the active grid, in slot 1
local function take_over(g, pre)
  pre = pre or slot_names()
  for i = 1, 4 do if pre[i] == g.name then pre[i] = "none" end end -- (a saved name of the virtual grid itself is no setting of a real grid)
  for i = 1, 4 do Grid.vports[i].name = pre[i] end                 -- (undo the autofill of Grid.new)
  local prev = pre[1]
  local ov = {}
  local prev_dev, moved_to
  if prev ~= "none" then
    for _, d in pairs(Grid.devices) do
      if d ~= g and d.name == prev then prev_dev = d end
    end
    if prev_dev then let_go(prev_dev) end
    for i = 2, 4 do -- the grid that was in slot 1 goes to the first free slot (none when all are taken: it has no port until it is back)
      if Grid.vports[i].name == "none" then
        Grid.vports[i].name = prev
        ov[i] = {set = prev, pre = "none"}
        moved_to = i
        break
      end
    end
  end
  Grid.vports[1].name = g.name
  ov[1] = {set = g.name, pre = prev}
  Grid.switch = {prev = prev ~= "none" and prev or nil, moved_to = moved_to, ov = ov, id = g.id}
  Grid.update_devices()
  -- the grid that was pushed out of slot 1: dark, unless a script listens on the port it is on now
  if prev_dev and prev_dev.port and Grid.vports[prev_dev.port] and Grid.vports[prev_dev.port].key == nil then
    prev_dev:all(0)
    prev_dev:refresh()
  end
end

-- the virtual grid is going: its slot goes back to what it was, a real grid it had pushed out of slot 1 is in slot 1 again, nothing else changes. returns the real grid that is in slot 1 again, or nil
local function give_back(g)
  let_go(g)
  local sw = Grid.switch
  Grid.switch = nil
  local target
  if sw and sw.ov then
    for i = 4, 1, -1 do -- (the slot the real grid was moved to first, then slot 1)
      local o = sw.ov[i]
      if o and Grid.vports[i].name == o.set then Grid.vports[i].name = o.pre end
    end
    if sw.prev and Grid.vports[1].name == sw.prev then
      for _, d in pairs(Grid.devices) do
        if d ~= g and not is_virtual(d) and d.name == sw.prev then target = d end
      end
    end
  else
    for i = 1, 4 do -- (a virtual grid that was never taken over: only its own slot is cleared)
      if Grid.vports[i].name == g.name then Grid.vports[i].name = "none" end
    end
  end
  return target
end

-- grid add
_norns.grid.add = function(id, serial, name, dev)
  local pre = switching and is_virtual({name = name .. " " .. serial}) and slot_names() or nil
  local g = Grid.new(id,serial,name,dev)
  Grid.devices[id] = g
  Grid.update_devices()
  if switching and is_virtual(g) then take_over(g, pre) end
  if Grid.add ~= nil then Grid.add(g) end
end

-- grid remove
-- Linux desktop: a device that no vport holds (a fifth grid, a virtual grid, one that is not connected) has no port: upstream indexes the vport anyway and raises, the entry stays and the clear that follows
-- works on a half-removed device (docs/port/KNOWN-ISSUES.md 28). here the callbacks run under pcall (the error is logged) and the device always goes
local desktop = os.getenv("NORNS_PLATFORM") ~= nil
_norns.grid.remove = function(id)
  local g = Grid.devices[id]
  local took_over = nil
  if g and switching and is_virtual(g) then took_over = give_back(g) end
  if g and switching and not is_virtual(g) then held[id] = nil end
  if g and desktop then
    local vp = g.port and Grid.vports[g.port]
    if vp and vp.remove then
      local ok, err = pcall(vp.remove)
      if not ok then print("grid: remove callback of port " .. tostring(g.port) .. " failed: " .. tostring(err)) end
    end
    if Grid.remove then
      local ok, err = pcall(Grid.remove, Grid.devices[id])
      if not ok then print("grid.remove failed: " .. tostring(err)) end
    end
  elseif g then
    if Grid.vports[g.port].remove then
      Grid.vports[g.port].remove()
    end
    if Grid.remove then
      Grid.remove(Grid.devices[id])
    end
  end
  Grid.devices[id] = nil
  held[id] = nil
  Grid.update_devices()
  -- M43: the grid that took over is announced, so that a script reads its size again
  if took_over and Grid.devices[took_over.id] == took_over and Grid.add ~= nil then
    local ok, err = pcall(Grid.add, took_over)
    if not ok then print("grid.add failed: " .. tostring(err)) end
  end
end

-- Linux desktop: an error in a script's key handler (g.key or the vport's key) was only a line in the log, from a key press that then did nothing more (Cheat Codes 2: a pattern recording ended in an
-- error and the pads were silent afterwards). now it is logged with its traceback, shown on the window for a few seconds (_menu.handler_error, as for the menu's handlers), and the other handler of the
-- same press still runs. on the device the handlers are called as before
local guard_keys = os.getenv("NORNS_PLATFORM") ~= nil
guarded_key = function(what, fn, x, y, s)
  if not guard_keys then return fn(x, y, s) end
  local ok, err = xpcall(fn, function(e) return tostring(e) .. "\n" .. debug.traceback("", 2) end, x, y, s)
  if ok then return end
  print(what .. " handler error: " .. tostring(err))
  if _menu and _menu.handler_error then pcall(_menu.handler_error, what, err) end
end

-- redefine global grid key input handler
_norns.grid.key = function(id, x, y, s)
  local g = Grid.devices[id]
  if g ~= nil and switching then
    local h = held[id]
    if s == 1 then
      if not h then h = {}; held[id] = h end
      h[x .. "," .. y] = {x, y}
    elseif h then
      h[x .. "," .. y] = nil
    end
  end
  if g ~= nil then
    if g.key ~= nil then
      guarded_key("grid key", g.key, x, y, s)
    end

    if g.port then
      if Grid.vports[g.port].key then
        guarded_key("grid key", Grid.vports[g.port].key, x, y, s)
      end
    end
  else
    error('no entry for grid '..id)
  end
end

-- redefine global grid tilt input handler
_norns.grid.tilt = function(id, x, y, z)
  local g = Grid.devices[id]
  if g ~= nil then
    if g.tilt ~= nil then
      g.tilt(x, y, z)
    end

    if g.port then
      if Grid.vports[g.port].tilt then
        Grid.vports[g.port].tilt(x, y, z)
      end
    end
  else
    error('no entry for grid '..id)
  end
end


Grid.help = [[
-- -----------------------------------------------------------------------------
grid.connect( port )          create a grid table using device [port]
                                default [port] 1 if unspecified
                              (returns) grid table
.key( x, y, z )               function called with incoming grid key event
                                this should be redefined by the script
.tilt( x, y, z )               function called with incoming grid tilt event
                                this should be redefined by the script
:led( x, y, level )           set LED at [x,y] to [level]
                                [level] range is 0..15
:all( level )                 set all grid LED to [level]
                                [level] range is 0..15
:refresh()                    update the grid LED state

-- -----------------------------------------------------------------------------
-- example

lx,ly,lz = 0,0,0

-- connect grid
g = grid.connect()

-- key function
g.key = function(x,y,z)
  print(x,y,z)
  lx = x
  ly = y
  lz = z*15
  draw_grid()
end

-- simple draw function
draw_grid()
  g:all(0)
  g:led(lx,ly,lz)
  g:refresh()
end
--------------------------------------------------------------------------------
]]      

return Grid
