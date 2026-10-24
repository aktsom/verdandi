-- script for linux/tests/probe_jump.lua: coroutines on clock.sync and clock.sleep, and a fast metro that records the
-- largest beat count it ever reads
function init()
  params:set("clock_source", 1)
  params:set("clock_tempo", 120)
  t0 = util.time()
  maxbeat = 0
  ev = {}
  sleeps = 0
  clock.run(function()
    while true do
      clock.sync(1)
      ev[#ev + 1] = {util.time() - t0, clock.get_beats()}
    end
  end)
  for i = 1, 8 do
    clock.run(function() while true do clock.sleep(0.5); sleeps = sleeps + 1 end end)
  end
  fast = metro.init(function() local b = clock.get_beats(); if b > maxbeat then maxbeat = b end end, 0.002, -1)
  fast:start()
end
