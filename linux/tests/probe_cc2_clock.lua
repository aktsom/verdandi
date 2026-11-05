# Cheat Codes 2 ends a pattern recording (linux/tests/cc2_clock_test.sh): sync_clock_to_loop and lib/transport.lua ask params for the bare id "clock_midi_out" (norns up to 2.7.3 had it as an
# option, 1 = off, n + 1 = vport n; from 2.7.4 there are the toggles clock_midi_out_1 .. 16, and the desktop has both). the script is in dust/code/cheat_codes_2 (a clone with its nb submodule).
#sleep 6
norns.script.load("code/cheat_codes_2/cheat_codes_2.lua")
#sleep 30
print("PROBE cc2 loaded", tostring(all_loaded), tostring(params.lookup["clock_midi_out"] ~= nil))
params:set("sync_clock_to_pattern_1", 2)
grid_actions = require 'cheat_codes_2/lib/grid_actions'
grid_pat[1]:rec_start()
print("PROBE press", pcall(function() g.key(4, 3, 1) end))
#sleep 0.6
print("PROBE release", pcall(function() g.key(4, 3, 0) end))
print("PROBE press2", pcall(function() g.key(5, 3, 1) end))
#sleep 0.6
print("PROBE release2", pcall(function() g.key(5, 3, 0) end))
print("PROBE pat count", grid_pat[1].count, grid_pat[1].rec)
print("PROBE handler", pcall(function() grid_actions.grid_pat_handler(1) end))
print("PROBE redraw after", pcall(grid_redraw))
print("PROBE bank ids", bank[1].id, bank[2].id, bank[3].id)
-- the transport.lua line of the script: when it sends the clock to a port itself, the system's clock out for that port is switched off
params:set("clock_midi_out_2", 1)
print("PROBE bare reads", params:get("clock_midi_out"))
if params:get("clock_midi_out") - 1 == 2 then params:set("clock_midi_out", 1) end
print("PROBE slot 2 after", params:get("clock_midi_out_2"), params:get("clock_midi_out"))
-- an error in a script's grid key handler is on the window and in the log
grid.devices[99] = {port = nil, key = function() error("boom in a grid key") end}
print("PROBE grid key", pcall(_norns.grid.key, 99, 1, 1, 1))
print("PROBE note", tostring(_menu.error_note))
print("PROBE cc2 done")
