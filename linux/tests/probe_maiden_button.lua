-- the MAIDEN button of the device window (linux/tests/maiden_button_test.sh): xdg-open is a stub that writes its argument to $XDG_LOG.
-- the button is at 719..789 x 70..110 of the 960 x 630 skin, 16 points of margin: a click at 0.776 / 0.160 of the window
#sleep 3
print("PROBE note before", _menu.maiden_note)
#click Verdandi 0.776 0.160
#sleep 1
print("PROBE note after", _menu.maiden_note)
#shot @home/maiden-button.png
#sleep 10
print("PROBE note later", _menu.maiden_note)
