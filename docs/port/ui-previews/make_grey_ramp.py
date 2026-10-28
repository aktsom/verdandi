#!/usr/bin/env python3
"""the picture of docs/port/ui-settings-plan.md section 2.1: the 16 screen levels on black, as the desktop draws them today (level n = grey 17 n) and with the
default grey correction (gamma 0.7). usage: make_grey_ramp.py OUT.png"""
import os
import sys
import textwrap

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ui_tint as ut

F = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
big, small = ImageFont.truetype(F, 15), ImageFont.truetype(F, 12)
SW, SH, GAP, X0 = 30, 56, 4, 10
W = X0 * 2 + 16 * SW + 15 * GAP
img = Image.new("RGB", (W, 330), (0, 0, 0))
d = ImageDraw.Draw(img)
y = 6
d.text((X0, y), "\n".join(textwrap.wrap("Look at levels 1 to 4 (the dim text of many scripts): the lower ramp separates them from the black and from each other.", 74)), fill=(235, 235, 235), font=small)
y = 48
for name, gamma in (("today: level n is grey 17 n (gamma 1.0)", 1.0), ("default mapping, gamma 0.7: level 4 = 101 instead of 68", 0.7)):
    d.text((X0, y), name, fill=(235, 235, 235), font=big)
    for lv in range(16):
        v = int(ut.corrected(lv * 17, gamma) + 0.5)
        x = X0 + lv * (SW + GAP)
        d.rectangle([x, y + 24, x + SW - 1, y + 24 + SH - 1], fill=(v, v, v))
        d.text((x + 2, y + 24 + SH + 3), "%d" % lv, fill=(150, 150, 150), font=small)
        d.text((x + 2, y + 24 + SH + 17), "%d" % v, fill=(110, 110, 110), font=small)
    y += 24 + SH + 40
img.save(sys.argv[1])
