-- MIC / SYS / APP / OFF on a JACK server with a fake card and fake application streams
-- (linux/tests/input_test.sh). every state dumps jack_lsp -c to $MARKS.<state>. the monitor of the
-- fake card's output is present, a late application appears while SYS is on.
_norns.set_warning("")
#sh jack_lsp -c > "$MARKS.start"
_menu.set_input("off")
#sleep 1
#sh jack_lsp -c > "$MARKS.off"
_menu.set_input("mic")
#sleep 1
#sh jack_lsp -c > "$MARKS.mic"
_menu.set_input("system")
#sleep 2
#sh jack_lsp -c > "$MARKS.system"
#sh ("$FAKE" "Late App" app > /dev/null 2>&1 &)
#sleep 3
#sh jack_lsp -c > "$MARKS.system_late"
_menu.set_input("app", "Vivaldi", "Vivaldi")
#sleep 2
#sh jack_lsp -c > "$MARKS.app"
print("PROBE apps", table.concat(_norns.app_list(), ","))
_menu.set_input("monitor")
#sleep 2
#sh jack_lsp -c > "$MARKS.monitor"
_menu.set_input("mic")
#sleep 1
#sh jack_lsp -c > "$MARKS.mic_again"
print("PROBE input done")
