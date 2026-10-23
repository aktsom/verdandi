# norns follows a MIDI clock sent through JACK MIDI (linux/tests/jack_midi_clock_test.c): tempo, start, song
# position, stop, continue, a second start, and notes. run_all.sh puts the client's path in $JMT.
# every transport event prints the beat and tempo at that moment, so the checks need no exact timing.
clock.transport.start = function() print("PROBE transport start", string.format("%.2f", clock.get_beats()), string.format("%.1f", clock.get_tempo())) end
clock.transport.stop = function() print("PROBE transport stop", string.format("%.2f", clock.get_beats()), string.format("%.1f", clock.get_tempo())) end
params:set("clock_source", 2)
jm = nil
for i = 1, 16 do
  if midi.vports[i].name == "Verdandi JACK in" then jm = midi.connect(i); print("PROBE jack midi vport", i) end
end
print("PROBE jack midi found", jm ~= nil)
if jm then
  jm.event = function(data)
    local d = midi.to_msg(data)
    if d.type == "note_on" or d.type == "note_off" then print("PROBE jack note", d.type, d.note, d.vel) end
  end
end
#sh ("$JMT" > "$MARKS.client" 2>&1 &)
#sleep 13
print("PROBE source", params:string("clock_source"))
print("PROBE jackmidi done")
