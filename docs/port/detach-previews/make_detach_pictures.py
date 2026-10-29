#!/usr/bin/env python3
"""Mock-ups for docs/port/detach-plan.md, drawn over a real capture of today's window (real-window-today.png, 992 x 662 at 1:1 in a 1280 x 800 screen,
box origin 160,85): they show the placeholder and the screen window (the pop-out button of the first plan was removed). They are pictures of a proposal, not of
code. run: python3 make_detach_pictures.py"""
from PIL import Image, ImageDraw, ImageFont
import os
here = os.path.dirname(os.path.abspath(__file__))
src = Image.open(os.path.join(here, "real-window-today.png")).convert("RGB")
OX, OY = 160, 85  # layout unit (0,0) in the capture
def font(size, bold=False):
    for p in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",):
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()
def unit(x, y): return (OX + x, OY + y)

# the bezel (units): x 36..592, y 300.667..594; the screen 512 x 256 inside it (22 / 18.67 margins)
bx0, by0 = unit(36, 300.667); bx1, by1 = unit(592, 594)
sx0, sy0 = unit(36 + 22, 300.667 + 18.667); sx1, sy1 = unit(36 + 22 + 512, 300.667 + 18.667 + 256)

def button(d, x0, y0, w, h, label, icon=True):
    d.rounded_rectangle((x0, y0, x0 + w, y0 + h), radius=7, fill=(38, 39, 43), outline=(95, 96, 101))
    f = font(12, True)
    text = ("↗ " if icon else "") + label
    tw = d.textlength(text, font=f)
    d.text((x0 + (w - tw) / 2, y0 + h / 2 - 8), text, font=f, fill=(222, 223, 226))

# 2. detached: the main window keeps every control; the screen is a dark placeholder with one sentence
p = src.copy(); d = ImageDraw.Draw(p)
d.rounded_rectangle((sx0, sy0, sx1, sy1), radius=4, fill=(22, 23, 26))
f = font(17)
lines = ["The screen is in its own window.", "Click here or press F9 to bring it back."]
cy = (sy0 + sy1) / 2 - 22
for i, t in enumerate(lines):
    tw = d.textlength(t, font=f)
    d.text(((sx0 + sx1) / 2 - tw / 2, cy + i * 28), t, font=f, fill=(170, 172, 178))
p.save(os.path.join(here, "detached-main-window.png"))

# 3. the screen window: only the picture, 640 x 320 (5 x 128 by 5 x 64), no box (the title bar is the desktop's, drawn here as a plain bar)
scr = src.crop((int(sx0), int(sy0), int(sx1), int(sy1))).resize((640, 320), Image.NEAREST)
w = Image.new("RGB", (640 + 2, 320 + 30 + 1), (60, 60, 64))
w.paste(scr, (1, 30))
d = ImageDraw.Draw(w)
d.text((10, 7), "screen", font=font(13), fill=(230, 230, 232))
d.text((640 - 62, 6), "_  □  x", font=font(14), fill=(230, 230, 232))
w.save(os.path.join(here, "screen-window.png"))

# 4. the three side by side on a desktop-sized canvas (1280 x 800), to show the idea
c = Image.new("RGB", (1280, 800), (46, 52, 64))
m = p.resize((int(1280 * 0.58), int(800 * 0.58)))
c.paste(m, (20, 40))
c.paste(w.resize((int(w.width * 0.9), int(w.height * 0.9))), (700, 120))
dd = ImageDraw.Draw(c)
dd.text((24, 12), "main window while the screen is detached", font=font(14), fill=(220, 220, 225))
dd.text((704, 92), "the screen window (here 640 x 320, 5 x)", font=font(14), fill=(220, 220, 225))
c.save(os.path.join(here, "overview.png"))
print("written")
