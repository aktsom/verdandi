-- the window title (linux/tests/display_name_test.sh): how many windows are called exactly "Verdandi Linux", and the titles of all windows
#sleep 3
#sh xdotool search --name '^Verdandi Linux$' | wc -l > "$MARKS"
#sh for id in $(xdotool search --name '.'); do xdotool getwindowname $id; done | grep -i verdandi >> "$MARKS"
