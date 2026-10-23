-- SYSTEM > AUDIO apply with our own jackd (dummy driver): audio.conf and the audio mark are written like
-- lua/core/menu/audio.lua does, then norns restarts; norns.sh must restart jackd with the new rate and period
#sh jack_samplerate > "$MARKS.rate_before"
#sh printf 'rate=44100\nperiod=256\n' > "$NORNS_HOME/audio.conf"; touch "$NORNS_HOME/.norns-restart-audio"
_norns.restart()
#sleep 30
#sh jack_samplerate > "$MARKS.rate_after"; jack_bufsize > "$MARKS.buf_after"; jack_lsp | grep -c '^crone:' > "$MARKS.crone"
print("PROBE audio restart done")
