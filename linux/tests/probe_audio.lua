-- crone's choice of sound card ports (linux/tests/audio_ports_test.sh): what norns says it connected to
warning, inc, outc = _norns.audio_status()
print("PROBE audio warning", warning)
print("PROBE audio in", inc)
print("PROBE audio out", outc)
#sh jack_lsp -c > "$MARKS.conn" 2>&1
#sleep 1
print("PROBE audio done")
