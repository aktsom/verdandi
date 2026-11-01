-- serialosc runs and holds a grid that norns never opened (linux/tests/serialosc_test.sh unopened; KNOWN-ISSUES 31): the note must appear anyway (the owner's serialosc-device on /dev/ttyACM0 and /dev/ttyUSB0
-- kept norns from opening them, no grid appeared and no note came), also from the systemd unit alone with a grid plugged in, and go on its own when serialosc stops.
-- $FAKE is a process that ignores its arguments, $DEVTTY a ttyACM-like file, $UNITFILE the file standing for the unit's cgroup.procs
#sleep 1
print("PROBE note 0", _menu.grid_note)
#sh (exec -a /usr/bin/serialoscd "$FAKE" -c /var/lib/serialosc) & echo $! > "$MARKS.pid_d"; (exec -a /usr/bin/serialosc-detector "$FAKE") & echo $! > "$MARKS.pid_x"
#sleep 5
print("PROBE note serialosc without a grid", _menu.grid_note)
#sh (exec -a serialosc-devic "$FAKE" -c /var/lib/serialosc "$DEVTTY") & echo $! > "$MARKS.pid_v"; (exec -a serialosc-devic "$FAKE" -c /var/lib/serialosc /dev/ttyUSB0) & echo $! > "$MARKS.pid_w"
#sleep 6
print("PROBE note 1", _menu.grid_note)
print("PROBE text 1", _norns.grid_conflict_text())
print("PROBE window note 1", select(1, _menu.show_note))
#sh kill $(cat "$MARKS.pid_v") $(cat "$MARKS.pid_w")
#sleep 6
print("PROBE note 2", _menu.grid_note)
-- no serialosc process at all now: the unit alone (its cgroup lists a process) with a grid plugged in
#sh kill $(cat "$MARKS.pid_d") $(cat "$MARKS.pid_x")
#sh echo 1234 > "$UNITFILE"; mkdir -p "$BYID"; : > "$BYID/usb-monome_grid_m0000009-if00"
#sleep 6
print("PROBE note 3", _menu.grid_note)
#sh : > "$UNITFILE"
#sleep 6
print("PROBE note 4", _menu.grid_note)
print("PROBE serialosc unopened done")
