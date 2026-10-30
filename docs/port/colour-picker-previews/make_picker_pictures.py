#!/usr/bin/env python3
"""the two pictures of docs/port/colour-picker-plan.md. the box, the keys, the encoders, the buttons and the screen's bezel are drawn by the REAL skin code (render_look.c of
../box-style-previews: device_skin.c and box_style.c with NORNS_LINUX_DESKTOP); the PICKER PANEL does not exist yet, so it is a STAND-IN drawn here (Pillow), at the layout size the plan proposes
(units of the 960 x 630 box; 1 unit = 992/992 = 1 px at this size). the text on the norns screen is a stand-in too (make_box_pictures.screen). usage: make_picker_pictures.py [OUTDIR]"""
import colorsys, os, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "box-style-previews"))
import make_box_pictures as M
from PIL import Image, ImageDraw, ImageFont

OUT = sys.argv[1] if len(sys.argv) > 1 else HERE
tmp = tempfile.mkdtemp()
exe = os.path.join(tmp, "render_look")
skin = os.path.join(M.REPO, "matron", "src", "platform", "macos"); lin = os.path.join(M.REPO, "matron", "src", "platform", "linux")
flags = subprocess.check_output(["pkg-config", "--cflags", "--libs", "cairo", "freetype2"], text=True).split()
subprocess.check_call(["cc", "-std=gnu11", "-O1", "-DNORNS_LINUX_DESKTOP", "-I" + skin, "-I" + lin, os.path.join(M.HERE, "render_look.c"), os.path.join(skin, "device_skin.c"),
                       os.path.join(lin, "box_palette.c"), os.path.join(lin, "box_style.c"), "-o", exe] + flags + ["-lm"])
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"

def hsv_hex(h, s, v):
    r, g, b = colorsys.hsv_to_rgb(h / 360.0, s, v)
    return (round(r * 255), round(g * 255), round(b * 255))

def panel(im, x, y, w, h, hsv, sel, blocky, face, edge, text):
    """strips: H (rainbow at the current S and V), S (from V grey to the full colour at the current H and V), B (from black to the full colour at the current H and S)"""
    d = ImageDraw.Draw(im)
    f = ImageFont.truetype(FONT, 17); fb = ImageFont.truetype(FONT, 24)
    r = 6 if blocky else 14
    d.rounded_rectangle([x - 3, y - 3, x + w + 3, y + h + 3], r + 3, fill=edge)
    d.rounded_rectangle([x, y, x + w, y + h], r, fill=face)
    d.text((x + 18, y + 8), "COLOUR: BOX", font=f, fill=text)
    H, S, V = hsv
    cur = hsv_hex(H, S, V)
    hexs = "#%02X%02X%02X" % cur
    sx, sw, sh = x + 84, w - 84 - 215, 22
    rows = [("HUE", H / 360.0, lambda t: hsv_hex(360 * t, S, V), "%3d" % round(H)), ("SAT", S, lambda t: hsv_hex(H, t, V), "%3d" % round(S * 100)), ("BRI", V, lambda t: hsv_hex(H, S, t), "%3d" % round(V * 100))]
    for i, (name, val, fn, num) in enumerate(rows):
        yy = y + 44 + i * 40
        on = (i == sel)
        d.text((x + 18, yy + 3), name, font=f, fill=text if on else tuple(int(c * 0.6) for c in text))
        step = 8 if blocky else 1
        for px in range(0, sw, step):
            d.rectangle([sx + px, yy, sx + px + step - 1, yy + sh], fill=fn((px + step / 2) / sw))
        d.rectangle([sx - 2, yy - 2, sx + sw + 1, yy + sh + 2], outline=text if on else edge, width=3 if on else 1)
        mx = sx + round(val * (sw - 1))
        if blocky:
            d.rectangle([mx - 4, yy - 8, mx + 3, yy + sh + 8], fill=(255, 255, 255), outline=(0, 0, 0), width=2)
        else:
            d.polygon([(mx, yy - 2), (mx - 7, yy - 11), (mx + 7, yy - 11)], fill=(255, 255, 255), outline=(0, 0, 0))
            d.polygon([(mx, yy + sh + 2), (mx - 7, yy + sh + 11), (mx + 7, yy + sh + 11)], fill=(255, 255, 255), outline=(0, 0, 0))
            d.line([mx, yy - 2, mx, yy + sh + 2], fill=(255, 255, 255), width=2)
        d.text((sx + sw + 14, yy + 1), num, font=f, fill=text)
    # the result: a swatch and the code
    d.rectangle([x + w - 160, y + 40, x + w - 18, y + 40 + 60], fill=cur, outline=text, width=2)
    d.text((x + w - 160, y + 40 + 68), hexs, font=fb, fill=text)
    d.text((x + w - 160, y + 40 + 100), "was #%s" % was, font=f, fill=tuple(int(c * 0.7) for c in text))
    d.text((x + 18, y + h - 28), "UP/DOWN strip  LEFT/RIGHT step  SHIFT bigger  ALT smaller  C centre  ENTER ok  ESC cancel", font=ImageFont.truetype(FONT, 13), fill=tuple(int(c * 0.8) for c in text))

def one(style, colours, name, face, edge, text, blocky, hsv, sel):
    screen = M.save(M.screen([("HUE", "%d" % round(hsv[0])), ("SATURATION", "%d" % round(hsv[1] * 100)), ("BRIGHTNESS", "%d" % round(hsv[2] * 100)), ("HEX", "#%02X%02X%02X" % hsv_hex(*hsv))],
                             sel=sel, hint="E2 strip  E3 change  K3 ok K2 cancel"), "pick_screen_%s.png" % style)
    out = os.path.join(tmp, name + ".png")
    subprocess.check_call([exe, out, screen] + colours, env=dict(os.environ, RENDER_STYLE=style))
    im = Image.open(out).convert("RGB")
    W, H = im.size
    # the panel sits over the empty upper part of the box: between the page buttons and the screen, from the screen's left edge to the right edge of the box's faces
    panel(im, 56, 100, 760, 196, hsv, sel, blocky, face, edge, text)
    return im

was = "3B6EA8"
_r, _g, _b = [int(was[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
_h, _s, _v = colorsys.rgb_to_hsv(_r, _g, _b)
HSV = (_h * 360, _s, _v)
dark = one("pixel", [c for c in M.SETS["DARK"]], "dark", (0x2c, 0x2e, 0x33), (0x13, 0x14, 0x16), (0xe4, 0xe6, 0xea), True, HSV, 1)
alu = one("aluminium", ["-"] * 5, "alu", (0xd6, 0xd8, 0xdc), (0x70, 0x72, 0x78), (0x22, 0x23, 0x26), False, HSV, 1)
dark.save(os.path.join(OUT, "picker-pixel-dark.png"))
alu.save(os.path.join(OUT, "picker-aluminium.png"))
print("ok")
