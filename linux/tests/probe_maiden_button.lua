-- the MAIDEN button of the device window (linux/tests/maiden_button_test.sh): xdg-open is a stub that writes its argument to $XDG_LOG.
-- the button is at 682.7..752.7 x 36..76 of the 960 x 630 skin (Linux layout), 16 points of margin: a click at 0.740 / 0.109 of the window
#sleep 3
print("PROBE note before", _menu.maiden_note)
#click Verdandi 0.740 0.109
#sleep 1
print("PROBE note after", _menu.maiden_note)
#shot @home/maiden-button.png
#sleep 10
print("PROBE note later", _menu.maiden_note)
