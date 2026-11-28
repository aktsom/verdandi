-- M44 (linux/tests/midi_autoconnect_test.sh, scenario "restored"): as "default", but the program's own port is linked to Verdandi:midi_in by the program
-- itself (FAKE_MIDI_LINK_TO: the way PipeWire restores a link, or a jack_connect that said "no" and linked all the same), so Verdandi's worker finds the
-- link already there. three quits and starts as the owner did on the laptop: another number (Client-131), another one (Client-132), and the first number back (Client-128; each quit is of a different port name, so the one-line-a-minute limit does not hide a line).
-- Verdandi's log must say "gone" at each quit and "connected"/"reconnected" at each return, with the port name.
#sleep 3
#sh jack_lsp -c > "$MARKS.start"
print("PROBE midi_in_status", _norns.midi_in_status())
#sh pkill -f "[f]ake_midi Midi-Bridge" || true
#sleep 4
#sh ("$FAKEMIDI" "Midi-Bridge" "Client-131:(capture_0) Virtual RawMIDI" > /dev/null 2>&1 &)
#sleep 4
#sh jack_lsp -c > "$MARKS.back1"
#sh pkill -f "[f]ake_midi Midi-Bridge" || true
#sleep 4
#sh ("$FAKEMIDI" "Midi-Bridge" "Client-132:(capture_0) Virtual RawMIDI" > /dev/null 2>&1 &)
#sleep 4
#sh jack_lsp -c > "$MARKS.back2"
#sh pkill -f "[f]ake_midi Midi-Bridge" || true
#sleep 4
#sh ("$FAKEMIDI" "Midi-Bridge" "Client-128:(capture_0) Virtual RawMIDI" > /dev/null 2>&1 &)
#sleep 4
#sh jack_lsp -c > "$MARKS.back3"
print("PROBE midi restored done")
