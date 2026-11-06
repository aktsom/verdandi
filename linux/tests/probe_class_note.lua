-- the class check (lua/core/sc_class_check.lua) on the device window: a "duplicate Class found" in logs/sclang.log makes a note and one log line, and a log of a clean start
-- takes it away. the log is appended to and truncated from here (sclang keeps its own handle open for appending)
#sleep 3
print("PROBE class note 0", _menu.class_note)
#sh printf "ERROR: duplicate Class found: 'MiBeads' \n%s/.local/share/SuperCollider/Extensions/mi-UGens/Classes/MiBeads.sc\n%s/dust/code/mi-copy/Classes/MiBeads.sc\n\n" "$NORNS_HOME" "$NORNS_HOME" >> "$NORNS_HOME/logs/sclang.log"
#sleep 5
print("PROBE class note 1", _menu.class_note)
#sh : > "$NORNS_HOME/logs/sclang.log"
#sleep 5
print("PROBE class note 2", _menu.class_note)
print("PROBE class done")
