-- a forward jump of JACK's frame time (jump_shim.c, file $JUMP_FILE) while the internal clock runs at 120 BPM, a script has
-- coroutines waiting on clock.sync and clock.sleep, and a fast metro records the largest beat count it reads
norns.script.load("code/jump/jump_probe.lua")
#sleep 4
#sh touch "$JUMP_FILE"
print("PROBE before jump", string.format("%.2f", util.time() - t0), string.format("%.2f", clock.get_beats()), #ev, sleeps)
#sleep 1
print("PROBE 1 s after", string.format("%.2f", util.time() - t0), string.format("%.2f", clock.get_beats()), #ev, sleeps, "maxbeat", string.format("%.2f", maxbeat))
#sleep 8
print("PROBE 9 s after", string.format("%.2f", util.time() - t0), string.format("%.2f", clock.get_beats()), #ev, sleeps, "maxbeat", string.format("%.2f", maxbeat))
for i = 1, #ev do print("PROBE ev", i, string.format("%.2f", ev[i][1]), string.format("%.2f", ev[i][2])) end
print("PROBE jump done")
