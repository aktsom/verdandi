-- the MIDI output auto-connect (linux/tests/midi_out_link_test.sh): midi_out_to names "Fake Synth:" and "Late Synth"; "Other Synth" does not match. every state dumps jack_lsp -c to $MARKS.<state>
#sleep 3
#sh jack_lsp -c > "$MARKS.start"
#sh jack_disconnect Verdandi:midi_out "Fake Synth:in"
#sh jack_lsp -c > "$MARKS.cut"
#sleep 4
#sh jack_lsp -c > "$MARKS.repaired"
#sh ("$CAP" "Late Synth" 8 0 > /dev/null 2>&1 &)
#sleep 4
#sh jack_lsp -c > "$MARKS.late"
print("PROBE midi out link done")
