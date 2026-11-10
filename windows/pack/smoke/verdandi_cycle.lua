-- verdandi_cycle: the script of the start and restart cycle test (windows/ci/smoke-m1.sh). every time norns starts it resumes this script (the seeded system.state says so); it counts its starts in a file
-- of its data folder, prints VERDANDI_CYCLE <n>, and a few seconds after init asks for a restart (SYSTEM > RESTART: norns.exe ends with exit code 42, the launcher starts everything again) until the count has
-- reached the number of cycles (cycles.txt next to the count, default 10); then it prints VERDANDI_CYCLE_DONE and shuts down (SLEEP: exit code 0, the launcher ends).
engine.name = nil

local function read_number(file, default)
  local f = io.open(file, "r")
  if not f then return default end
  local n = tonumber(f:read("l") or "")
  f:close()
  return n or default
end

function init()
  local data = norns.state.data
  local n = read_number(data .. "cycle.txt", 0) + 1
  local total = read_number(data .. "cycles.txt", 10)
  local f = io.open(data .. "cycle.txt", "w")
  if f then f:write(n .. "\n") f:close() end
  print("VERDANDI_CYCLE " .. n .. " of " .. total)
  clock.run(function()
    clock.sleep(3)
    if n < total then
      print("VERDANDI_CYCLE_RESTART " .. n)
      _norns.restart()
    else
      print("VERDANDI_CYCLE_DONE " .. n)
      clock.sleep(1)
      norns.shutdown()
    end
  end)
end

function redraw()
  screen.clear()
  screen.level(15)
  screen.move(8, 30)
  screen.text("cycle test")
  screen.update()
end
