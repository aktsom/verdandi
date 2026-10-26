-- the MANUAL button of the device window (linux/tests/manual_button_test.sh): xdg-open is a stub that writes its argument to $XDG_LOG.
-- the button is at 795..865 x 70..110 of the 960 x 630 skin, 16 points of margin: a click at 0.853 / 0.160 of the window
#sleep 3
print("PROBE manual note before", _menu.maiden_note)
#click Verdandi 0.853 0.160
#sleep 1
print("PROBE manual note after", _menu.maiden_note)
#shot @home/manual-button.png
#sleep 10
print("PROBE manual note later", _menu.maiden_note)
