#!/usr/bin/env python3
"""the pictures of docs/port/ui-settings-plan.md, made from CAPTURES OF THE REAL WINDOW with the real UI code (make_ui_pictures.sh takes them).
usage: make_ui_settings_previews.py CAPTURE_DIR OUT_DIR   (CAPTURE_DIR holds loops-1.0.png, loops-0.5.png, params-<colour>.png, params-b<brightness>.png)"""
import os
import sys
import textwrap

from PIL import Image, ImageDraw, ImageFont

F = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"


def sheet(panels, path, title):
    font, small = ImageFont.truetype(F, 15), ImageFont.truetype(F, 13)
    w, h = panels[0][0].size
    gap, head = 14, 46
    img = Image.new("RGB", (w, head + len(panels) * (h + 40 + gap)), (32, 32, 34))
    d = ImageDraw.Draw(img)
    d.text((8, 5), "\n".join(textwrap.wrap(title, 62)), fill=(235, 235, 235), font=font)
    y = head
    for im, label in panels:
        d.text((8, y), "\n".join(textwrap.wrap(label, 74)), fill=(200, 200, 200), font=small)
        img.paste(im, (0, y + 36))
        y += h + 40 + gap
    img.save(path)


cap, out = sys.argv[1], sys.argv[2]
load = lambda n: Image.open(os.path.join(cap, n + ".png")).convert("RGB")
sheet([(load("loops-1.0"), "GREYS 1.0 (linear, as before): the waveform (level 1), the labels and the markers (level 3) are nearly black."),
       (load("loops-0.5"), "GREYS 0.5 (the default): the same page; look at the waveform and the dim labels, they should be readable now.")],
      os.path.join(out, "ui-greys.png"), "A loops page in the style of Cheat Codes 2 (levels 3, 1, 3, 15), real window, brightness 1")
sheet([(load("params-white"), "WHITE, brightness 1, greys 0.5: the reference."),
       (load("params-yellow"), "YELLOW (FFD000): does it look like a yellow OLED, and is the dim text readable?"),
       (load("params-pink"), "PINK (FF80B8): is this the pink you want?")],
      os.path.join(out, "ui-colours.png"), "SYSTEM > UI colours, PARAMS page, real window, brightness 1, greys 0.5")
sheet([(load("params-b1.0"), "brightness 1 (the default)."),
       (load("params-b0.7"), "brightness 0.7: the dim text should still read easily."),
       (load("params-b0.4"), "brightness 0.4: the darkest you would run it? (0.1 is dim, a quarter of full brightness in the code values, not black)")],
      os.path.join(out, "ui-brightness.png"), "SYSTEM > UI brightness, PARAMS page, real window, white, greys 0.5")
