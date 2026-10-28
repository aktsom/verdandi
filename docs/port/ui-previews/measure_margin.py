#!/usr/bin/env python3
"""measure_margin.py IMAGE.png CX CY: the black margin around the screen in a rendered window whose screen image is all white. CX CY: a point inside the
screen (window pixels). walks left, right, up and down from it: to the screen's edge (the last pure white pixel), then to the first pixel that is not black
(the bezel's lip). prints the screen's size and the four margins in device pixels, and as a fraction of the screen's width and height."""
import subprocess, sys
png, cx, cy = sys.argv[1], int(float(sys.argv[2])), int(float(sys.argv[3]))
w, h = map(int, subprocess.check_output(["identify", "-format", "%w %h", png]).split())
raw = subprocess.check_output(["convert", png, "-depth", "8", "rgb:-"])
def px(x, y): i = 3 * (y * w + x); return raw[i], raw[i + 1], raw[i + 2]
white = lambda p: p == (255, 255, 255)
black = lambda p: max(p) <= 6
def walk(dx, dy):
    x, y = cx, cy
    while white(px(x + dx, y + dy)): x, y = x + dx, y + dy
    edge = (x, y)
    n = 0
    while black(px(x + dx, y + dy)): x, y = x + dx, y + dy; n += 1
    return edge, n
(l, ml), (r, mr), (u, mu), (d, md) = walk(-1, 0), walk(1, 0), walk(0, -1), walk(0, 1)
sw, sh = r[0] - l[0] + 1, d[1] - u[1] + 1
print("screen %d x %d px; margin left %d right %d top %d bottom %d px; as a fraction of the screen: sides %.2f %% of its width, top and bottom %.2f %% of its height" %
      (sw, sh, ml, mr, mu, md, 100 * (ml + mr) / 2 / sw, 100 * (mu + md) / 2 / sh))
