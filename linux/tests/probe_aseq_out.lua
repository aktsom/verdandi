# what a script sends to the virtual MIDI device reaches the ALSA sequencer: client "Verdandi", port "Verdandi out" (linux/tests/aseq_dump_test.c listens; run_all.sh puts its path in $ASEQ; needs a kernel sequencer). the same sends as probe_jackmidi_out.lua
# a note sent before anybody listens is dropped; then notes, cc, program change, pitch bend, pressure, sysex, start / continue / stop and 24 clock ticks, 20 ms apart, are sent:
# every one prints what it should be ("PROBE sent <hex>"), the capture client prints what arrived. nothing is sent in the last seconds: nothing may arrive then.
#sleep 4
vp = nil
for i = 1, 16 do if midi.vports[i].name == "virtual" then vp = i end end
print("PROBE virtual vport", vp)
for id, d in pairs(midi.devices) do print("PROBE device", d.name) end
m = midi.connect(vp)
function hexof(t) local d = midi.to_data(t) local s = {} for i = 1, #d do s[#s + 1] = string.format("%02x", d[i]) end return table.concat(s, " ") end
function sent(t) print("PROBE sent", hexof(t)) end
m:note_on(61, 100, 1)
print("PROBE sent before a listener (dropped)")
#sh ("$ASEQ" aseq_a 12 1 > "$MARKS.cap" 2>&1 &)
#sh ("$ASEQ" aseq_b 12 0 > "$MARKS.nolink" 2>&1 &)
#sleep 3
print("PROBE listening")
sent{type = "note_on", note = 60, vel = 100, ch = 1}; m:note_on(60, 100, 1)
sent{type = "note_off", note = 60, vel = 40, ch = 1}; m:note_off(60, 40, 1)
sent{type = "cc", cc = 7, val = 64, ch = 2}; m:cc(7, 64, 2)
sent{type = "program_change", val = 5, ch = 3}; m:program_change(5, 3)
sent{type = "pitchbend", val = 8292, ch = 1}; m:pitchbend(8292, 1)
sent{type = "key_pressure", note = 60, val = 30, ch = 1}; m:key_pressure(60, 30, 1)
sent{type = "channel_pressure", val = 9, ch = 4}; m:channel_pressure(9, 4)
print("PROBE sent", "f0 7d 01 02 03 f7"); m:send({0xf0, 0x7d, 1, 2, 3, 0xf7})
sent{type = "start"}; m:start()
sent{type = "continue"}; m:continue()
sent{type = "stop"}; m:stop()
sent{type = "song_position", lsb = 16, msb = 0}; m:song_position(16, 0)
clock.run(function() for i = 1, 24 do m:clock() clock.sleep(0.02) end print("PROBE clock burst done") end)
#sleep 3
print("PROBE quiet from here")
#sleep 4
print("PROBE jackmidi out done")
