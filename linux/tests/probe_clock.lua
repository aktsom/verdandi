-- the internal clock at 120 BPM must run at 2 beats per second whatever the JACK graph does around it
-- (linux/tests/clock_rate_test.sh). samples: wall time (date) next to clock.get_beats(), 5 times, 2 s apart
params:set("clock_source", 1)
params:set("clock_tempo", 120)
#sleep 1
#sh date +%s.%N >> "$MARKS.t"
print("PROBE beats", clock.get_beats())
#sleep 2
#sh date +%s.%N >> "$MARKS.t"
print("PROBE beats", clock.get_beats())
#sleep 2
#sh date +%s.%N >> "$MARKS.t"
print("PROBE beats", clock.get_beats())
#sleep 2
#sh date +%s.%N >> "$MARKS.t"
print("PROBE beats", clock.get_beats())
#sleep 2
#sh date +%s.%N >> "$MARKS.t"
print("PROBE beats", clock.get_beats())
print("PROBE clock done")
