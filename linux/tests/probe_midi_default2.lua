-- M39 (scenario "default2"): two virtual ports of two programs, a hardware interface and the VirMIDI card in the graph: one source is linked, never the others
#sleep 3
#sh jack_lsp -c > "$MARKS.start"
print("PROBE midi_in_status", _norns.midi_in_status())
#sleep 4
#sh jack_lsp -c > "$MARKS.later"
print("PROBE midi default2 done")
