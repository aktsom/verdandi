local m = {
  confirmed = false
}

-- on a computer RESET sits in SYSTEM (core/menu/system.lua)
local back = os.getenv("NORNS_PLATFORM") ~= nil and "SYSTEM" or "SETTINGS"

m.key = function(n,z)
  if n==2 and z==1 then
    _menu.set_page(back)
  elseif n==3 and z==1 then
    m.confirmed = true
    _menu.redraw()
    _norns.execute("rm ~/dust/data/system.pset")
    _norns.execute("rm ~/dust/data/system.state")
    _norns.execute("rm "..paths.favorites)
    _norns.execute("rm "..paths.enabled_mods)
    _norns.execute("rm "..paths.display_settings)
    _norns.reset()
  end
end

m.enc = function(n,delta) end

m.redraw = function()
  screen.clear()
  screen.level(m.confirmed==false and 10 or 2)
  screen.move(64,40)
  screen.text_center(m.confirmed==false and "clear settings and restart?" or "restarting.")
  screen.update()
end

m.init = function() end
m.deinit = function() end

return m
