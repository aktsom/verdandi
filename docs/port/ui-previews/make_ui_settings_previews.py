#!/usr/bin/env python3
"""the two pictures of docs/port/ui-settings-plan.md. input: a capture of the REAL window (992 x 662, PARAMS page, white, brightness 1), taken by capture.lua under
Xvfb with the built norns (make_previews.sh does that). the screen is then tinted with the mapping of ui_tint.py: this is a stand-in (the setting is not built yet),
everything but the colour of the 512 x 256 screen rectangle is the real window.
usage: make_ui_settings_previews.py WINDOW.png OUT_DIR"""
import os
import sys
import textwrap

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ui_tint as ut

SX, SY, SW, SH = 74, 335, 512, 256  # the screen in the window at the design size (device_skin.c, Linux layout)
CROP = (40, 296, 622, 628)          # the bezel with a little of the box around it


def tinted(win, tint, brightness):
    out = win.copy().convert("RGB")
    px = out.load()
    lut = [ut.mapped(g, tint, brightness) for g in range(256)]
    for y in range(SY, SY + SH):
        for x in range(SX, SX + SW):
            px[x, y] = lut[px[x, y][0]]
    return out.crop(CROP)


def sheet(panels, path, title):
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 15)
    small = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 13)
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


win = Image.open(sys.argv[1]).convert("RGB")
out = sys.argv[2]
sheet([(tinted(win, ut.PRESETS[n], 1.0), l) for n, l in [
    ("white", "WHITE (as today), brightness 1: the reference - the menu text and the grey bar should be as you know them."),
    ("yellow", "YELLOW (FFD000), brightness 1: does the dim text (level 4) stay readable, and does it look like a yellow OLED?"),
    ("pink", "PINK (FF80B8), brightness 1: is the pink the one you want, and are the dim levels still apart from each other?")]],
    os.path.join(out, "ui-colours.png"), "Real window, PARAMS page, three colours (the tint is simulated, see ui-settings-plan.md)")
sheet([(tinted(win, ut.PRESETS["white"], b), l) for b, l in [
    (1.0, "brightness 1 (default): full."),
    (0.7, "brightness 0.7: look at the dim text (level 4) - is it still easy to read?"),
    (0.4, "brightness 0.4: the darkest you would run it? 0.1 would be a quarter of this.")]],
    os.path.join(out, "ui-brightness.png"), "Real window, PARAMS page, white at brightness 1, 0.7 and 0.4 (simulated)")
