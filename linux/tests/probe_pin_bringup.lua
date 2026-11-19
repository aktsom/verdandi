# M28 (run_all.sh, pin_bringup_scenario; VERDANDI_TEST_HOOKS=1): a press of PIN while the norns window is not in view brings it up and turns PIN on; in view it toggles. real window on Xvfb. the window is hidden with
# _norns.window_test(2) (the same state a window manager gives a window on another desktop), the press is the one the MIDI action and F7 make (_norns.window_action('pin')), the lines "pin report N" are read by the shell
#sleep 5
_norns.pin_report(1)
#sleep 0.5
print("PROBE pinup window_test hide", _norns.window_test(2))
#sleep 1
_norns.pin_report(2)
#sleep 0.5
_norns.window_action('pin')
#sleep 1.5
_norns.pin_report(3)
#sleep 0.5
_norns.window_action('pin')
#sleep 1
_norns.pin_report(4)
#sleep 0.5
_norns.window_action('pin')
#sleep 1
_norns.pin_report(5)
#sleep 0.5
_norns.window_test(2)
#sleep 1
_norns.pin_report(6)
#sleep 0.5
_norns.window_action('pin')
#sleep 1.5
_norns.pin_report(7)
#sleep 0.5
_norns.window_action('pin')
#sleep 1
_norns.pin_report(8)
#sleep 0.5
print("PROBE pin bringup done")
#xdo key ctrl+q
#sleep 4
