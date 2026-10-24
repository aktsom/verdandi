-- a grid that norns has opened and a serialosc-device process that has it too (linux/tests/serialosc_test.sh).
-- $DEVLINK is the by-id symlink of the "grid", $DEVTTY the ttyACM-like file it points to, $FAKE a process that ignores its arguments.
-- only serialoscd and serialosc-detector at first: no conflict. then serialosc-device with the ttyACM name (norns opened the by-id
-- name): conflict, once in the log, a note on the device. then the process goes: the note goes.
#sh (exec -a /usr/bin/serialoscd "$FAKE" -c /var/lib/serialosc) & echo $! > "$MARKS.pid_d"; (exec -a /usr/bin/serialosc-detector "$FAKE") & echo $! > "$MARKS.pid_x"
#sleep 1
print("PROBE check without a device process", _norns.serialosc_check(os.getenv("DEVLINK")))
print("PROBE note 1", _menu.grid_note)
#sh (exec -a serialosc-devic "$FAKE" -c /var/lib/serialosc "$DEVTTY") & echo $! > "$MARKS.pid_v"
#sleep 6
print("PROBE text 2", _norns.grid_conflict_text())
print("PROBE note 2", _menu.grid_note)
#sh kill $(cat "$MARKS.pid_v")
#sleep 6
print("PROBE text 3", _norns.grid_conflict_text())
print("PROBE note 3", _menu.grid_note)
#sh kill $(cat "$MARKS.pid_d") $(cat "$MARKS.pid_x")
print("PROBE serialosc done")
