-- a SuperCollider plug-in built for another machine in the norns home (linux/tests/plugin_note_test.sh): norns.sh reported it before sclang started, the
-- device window has a note while the file is there, and the note goes when the file has been moved away by hand ($FAKEPLUG)
#sleep 4
print("PROBE plugin note 1", _menu.plugin_note)
#sh mkdir -p "$NORNS_HOME/disabled-plugins" && mv "$FAKEPLUG" "$NORNS_HOME/disabled-plugins/"
#sleep 5
print("PROBE plugin note 2", _menu.plugin_note)
print("PROBE plugin done")
