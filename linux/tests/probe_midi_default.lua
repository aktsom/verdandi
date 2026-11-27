-- M39 (linux/tests/midi_autoconnect_test.sh, scenario "default"): nothing in audio.conf, nothing in the environment. the fake "Midi-Bridge" client has Reaper's virtual port.
-- start: linked by itself. then the program quits (its port goes): one line "is gone", nothing linked. then it comes back with another number (Reaper restarted): linked again, one line.
#sleep 3
#sh jack_lsp -c > "$MARKS.start"
print("PROBE midi_in_status", _norns.midi_in_status())
#sh pkill -f "[f]ake_midi Midi-Bridge" || true
#sleep 4
#sh jack_lsp -c > "$MARKS.gone"
#sh ("$FAKEMIDI" "Midi-Bridge" "Client-131:(capture_0) Virtual RawMIDI" > /dev/null 2>&1 &)
#sleep 4
#sh jack_lsp -c > "$MARKS.back"
print("PROBE midi_in_status back", _norns.midi_in_status())
print("PROBE midi default done")
