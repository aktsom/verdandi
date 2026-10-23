-- the MIDI auto-connect (linux/tests/midi_autoconnect_test.sh): NORNS_MIDI_IN_FROM names "Fake DAW" and "Late DAW";
-- "Other" does not match. every state dumps jack_lsp -c to $MARKS.<state>
#sleep 3
#sh jack_lsp -c > "$MARKS.start"
print("PROBE midi_in_status", _norns.midi_in_status())
#sh jack_disconnect "Fake DAW:out" Verdandi:midi_in
#sh jack_lsp -c > "$MARKS.cut"
#sleep 4
#sh jack_lsp -c > "$MARKS.repaired"
#sh ("$FAKEMIDI" "Late DAW" > /dev/null 2>&1 &)
#sleep 4
#sh jack_lsp -c > "$MARKS.late"
print("PROBE midi_in_status late", _norns.midi_in_status())
print("PROBE midi link done")
