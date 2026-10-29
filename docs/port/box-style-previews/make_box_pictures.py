#!/usr/bin/env python3
"""the two pictures of docs/port/box-style-plan.md. NOTHING OF THE PIXEL STYLE EXISTS IN THE PRODUCT YET: the pixel windows here are a STAND-IN written for the plan (same
layout table, same palette formula, same pixel shapes as the plan describes; the product code will be C in the skin, this is Python on a 480 x 315 block grid). the aluminium window
is drawn by the real skin code (matron/src/platform/macos/device_skin.c with NORNS_LINUX_DESKTOP, via ../ui-previews/render_preview.c). the screens (the BOX page) are stand-ins too:
the page is not built; they are set in the norns font (resources/norns.ttf, 8 px, no smoothing) with the levels the real pages use (15 selected, 4 other, 2 hint).
usage: make_box_pictures.py OUT_DIR   (needs PIL, cairo's headers, a C compiler; run from anywhere)"""
import os, subprocess, sys, tempfile
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
OUT = sys.argv[1] if len(sys.argv) > 1 else HERE
FONT = ImageFont.truetype(os.path.join(REPO, "resources", "norns.ttf"), 8)

# ---------------------------------------------------------------- the palette formula (plan section 2.4)
def dark(c):   return tuple(round(v * 0.60) for v in c)               # edges, shadows, pressed faces
def darker(c): return tuple(round(v * 0.36) for v in c)               # outline, the surround of the window
def light(c):  return tuple(round(v + (255 - v) * 0.30) for v in c)   # top-left edges, hover
def hexc(s):   return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))

SETS = {  # box, keys, encoders, buttons, font
    "DARK":   ("2c2e33", "444853", "5d6270", "3a3d45", "e4e6ea"),
    "LIGHT":  ("d8d5ce", "f4f2ed", "b9b5ab", "ebe8e1", "34343a"),
    "COLOUR": ("2b6f73", "f2b63d", "e9dfc8", "1d4a4d", "f7f0de"),
}

# ---------------------------------------------------------------- the pixel layout table, in layout units (plan section 2.2); one block = 2 units
BOX_W, BOX_H, BLOCK = 960, 630, 2
BTN = [("MIX", 36), ("TAPE", 112), ("HOME", 188), ("PARAMS", 264), ("MIC", 359.3333), ("GRID", 435.3333), ("ARC", 511.3333), ("KEYS", 587.3333),
       ("MAIDEN", 682.6667), ("MANUAL", 758.6667), ("MUTE", 854)]
BTN_Y, BTN_W, BTN_H = 36, 70, 28
KEY_C = [(100, 188), (734, 530), (864, 530)]
KEY_S = 112
ENC_C = [(240, 188), (734, 376), (864, 376)]
ENC_D = 80
BEZEL = (36, 300.667, 556, 293.333)   # unchanged from the aluminium style

class Grid:
    def __init__(self, w, h, bg):
        self.im = Image.new("RGB", (w, h), bg); self.px = self.im.load(); self.w, self.h = w, h
    def put(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h: self.px[x, y] = c
    def rect(self, x0, y0, x1, y1, c):          # blocks, x1/y1 exclusive
        for y in range(int(y0), int(y1)):
            for x in range(int(x0), int(x1)): self.put(x, y, c)

def rr_inside(x, y, w, h, r):                  # pixel rounded rectangle: the corners are quarter pixel circles
    cx = min(max(x + 0.5, r), w - r); cy = min(max(y + 0.5, r), h - r)
    return (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 <= r * r

def draw_rr(g, x0, y0, w, h, r, fill, edge_dark, bevel_light, bevel_dark, bevel=1):
    """a pixel rounded rectangle: 1 block outline, then `bevel` blocks of light on the top and left edges and of dark on the bottom and right edges, then the fill"""
    ins = lambda x, y: 0 <= x < w and 0 <= y < h and rr_inside(x, y, w, h, r)
    for y in range(h):
        for x in range(w):
            if not ins(x, y): continue
            c = fill
            if not (ins(x - 1, y) and ins(x + 1, y) and ins(x, y - 1) and ins(x, y + 1)):
                c = edge_dark
            else:
                for d in range(1, bevel + 1):
                    if not (ins(x - 1 - d, y) and ins(x, y - 1 - d)): c = bevel_light; break
                    if not (ins(x + 1 + d, y) and ins(x, y + 1 + d)): c = bevel_dark; break
            g.put(x0 + x, y0 + y, c)

def disc(g, cx, cy, r, c, test=None):
    for y in range(int(cy - r) - 1, int(cy + r) + 2):
        for x in range(int(cx - r) - 1, int(cx + r) + 2):
            if (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 <= r * r and (test is None or test(x, y)): g.put(x, y, c)

def text_px(g, x, y, s, c):                    # norns.ttf 8 px, one text pixel = one block
    m = Image.new("1", (8 * len(s) + 4, 12), 0)
    ImageDraw.Draw(m).fontmode = "1"
    d = ImageDraw.Draw(m); d.fontmode = "1"; d.text((0, 0), s, font=FONT, fill=1)
    w = int(FONT.getlength(s)); mp = m.load()
    for yy in range(12):
        for xx in range(m.width):
            if mp[xx, yy]: g.put(x + xx, y + yy, c)
    return w

def render_pixel(colours, oled_png, hover=None, lit=("GRID",), down=None, ticks=(0, 3, 7)):
    box, keys, encs, btns, font = [hexc(c) for c in colours]
    surround = darker(box)
    W, H = BOX_W // BLOCK, BOX_H // BLOCK
    g = Grid(W + 16, H + 16, surround)           # 8 blocks of margin on every side (16 units)
    ox = oy = 8
    # hard shadow, then the box
    draw_rr(g, ox + 2, oy + 2, W, H, 11, darker(surround), darker(surround), darker(surround), darker(surround), 0)
    draw_rr(g, ox, oy, W, H, 11, box, darker(box), light(box), dark(box), 1)
    # bezel: a 2 block frame in the dark shade, a 1 block light line below and right, black inside
    bx, by, bw, bh = [v / BLOCK for v in BEZEL]
    bx0, by0, bx1, by1 = int(bx), int(by), int(bx + bw + 0.999), int(by + bh + 0.999)
    g.rect(ox + bx0 - 2, oy + by0 - 2, ox + bx1 + 2, oy + by1 + 2, darker(box))
    g.rect(ox + bx0 - 1, oy + by1 + 1, ox + bx1 + 2, oy + by1 + 2, light(box)); g.rect(ox + bx1 + 1, oy + by0 - 1, ox + bx1 + 2, oy + by1 + 2, light(box))
    g.rect(ox + bx0, oy + by0, ox + bx1, oy + by1, (0, 0, 0))
    # buttons
    for name, x in BTN:
        bxx, byy = int(round(x / BLOCK)), int(BTN_Y / BLOCK)
        wb, hb = BTN_W // BLOCK, BTN_H // BLOCK
        is_lit = name in lit; is_down = name == down
        face, ink = (font, btns) if is_lit else (btns, font)
        if hover == name and not is_down: face = light(face)
        dy = 1 if is_down else 0
        draw_rr(g, ox + bxx, oy + byy + dy, wb, hb - dy, 2, face, darker(box), light(face) if not is_down else face, dark(face), 1)
        w = int(FONT.getlength(name))
        text_px(g, ox + bxx + (wb - w) // 2, oy + byy + dy + (hb - 6) // 2 - 1, name, ink)
    # keys: rounded squares, pressed ones sink one block
    for i, (cx, cy) in enumerate(KEY_C):
        s = KEY_S // BLOCK; dy = 1 if down == "K%d" % (i + 1) else 0
        face = dark(keys) if dy else keys
        draw_rr(g, ox + cx // BLOCK - s // 2, oy + cy // BLOCK - s // 2 + dy, s, s, 5, face, darker(box), light(keys) if not dy else face, dark(keys), 2)
    # encoders: pixel discs, a lit crescent top left, a dark one bottom right, a notch that turns with the detents
    import math
    for i, (cx, cy) in enumerate(ENC_C):
        r = ENC_D // BLOCK // 2; ccx, ccy = ox + cx // BLOCK, oy + cy // BLOCK
        disc(g, ccx, ccy, r, darker(box))
        disc(g, ccx, ccy, r - 1, encs)
        disc(g, ccx, ccy, r - 1, light(encs), lambda x, y: (x + 0.5 - ccx) + (y + 0.5 - ccy) < -r * 0.62 and ((x + 0.5 - ccx) ** 2 + (y + 0.5 - ccy) ** 2) > (r - 4) ** 2)
        disc(g, ccx, ccy, r - 1, dark(encs), lambda x, y: (x + 0.5 - ccx) + (y + 0.5 - ccy) > r * 0.62 and ((x + 0.5 - ccx) ** 2 + (y + 0.5 - ccy) ** 2) > (r - 4) ** 2)
        disc(g, ccx, ccy, r - 6, light(encs) if hover == "E%d" % (i + 1) else encs)
        a = math.radians(-90 + 10 * ticks[i])
        disc(g, ccx + math.cos(a) * (r - 9), ccy + math.sin(a) * (r - 9), 2.2, dark(encs))
    # the screen at the product's place: 4 device pixels per screen pixel, drawn over the block layer afterwards
    big = g.im.resize((g.w * 2, g.h * 2), Image.NEAREST)           # 2 device pixels per block at the design size
    oled = Image.open(oled_png).convert("RGB").resize((512, 256), Image.NEAREST)
    big.paste(oled, (74, 335))                                        # skin_geom: oled_x 74, oled_y 335 at the design size
    return big

def render_aluminium(oled_png):
    tmp = tempfile.mkdtemp()
    lut = os.path.join(tmp, "lut.txt"); open(lut, "w").write(" ".join(str(i) for i in range(256)))
    exe = os.path.join(tmp, "render"); skin = os.path.join(REPO, "matron", "src", "platform", "macos")
    flags = subprocess.check_output(["pkg-config", "--cflags", "--libs", "cairo"], text=True).split()
    subprocess.check_call(["cc", "-std=gnu11", "-O1", "-DNORNS_LINUX_DESKTOP", "-I" + skin, os.path.join(REPO, "docs/port/ui-previews/render_preview.c"),
                           os.path.join(skin, "device_skin.c"), "-o", exe] + flags + ["-lm"])
    out = os.path.join(tmp, "alu.png")
    subprocess.check_call([exe, out, oled_png, lut, "100"])
    return Image.open(out).convert("RGB")

# ---------------------------------------------------------------- the stand-in screens: the BOX page (plan section 2.6)
def screen(lines, sel=None, hint="", marker_col=None, title=None, scroll=None, bar=True):
    im = Image.new("L", (128, 64), 0); d = ImageDraw.Draw(im); d.fontmode = "1"
    y = 9
    if title:
        d.text((0, 1), title, font=FONT, fill=4); y = 17
    for i, ln in enumerate(lines):
        k, v = ln if isinstance(ln, tuple) else (ln, "")
        lv = 15 if i == sel else (2 if k.startswith("-") else 4)
        d.text((0, y + 9 * i - 8), k, font=FONT, fill=lv)
        if v: d.text((120 - int(FONT.getlength(v)), y + 9 * i - 8), v, font=FONT, fill=lv)
    if scroll and bar:
        top, n, vis = scroll
        h = max(4, 54 * vis // n); yy = 8 + (54 - h) * top // max(1, n - vis)
        d.rectangle([126, yy, 127, yy + h], fill=6)
    d.text((0, 55), hint, font=FONT, fill=2)
    return im.point(lambda v: min(255, v * 17))

def save(im, name):
    p = os.path.join(tempfile.gettempdir(), name); im.save(p); return p

page_top = screen([("STYLE", "ALUMINIUM"), ("PRESET", "DARK"), ("BOX", "#2C2E33"), ("KEYS", "#444853"), ("ENCODERS", "#5D6270"), ("BUTTONS", "#3A3D45")], sel=0,
                  hint="E2 row  E3 change  (pixel only)", scroll=(0, 9, 6))
page_top_px = screen([("STYLE", "PIXEL"), ("PRESET", "DARK"), ("BOX", "#2C2E33"), ("KEYS", "#444853"), ("ENCODERS", "#5D6270"), ("BUTTONS", "#3A3D45")], sel=1,
                     hint="E2 row  E3 change  K3 list", scroll=(0, 9, 6))
preset_list_light = screen([("DARK", ""), ("LIGHT", "in use"), ("COLOUR", ""), ("- MY PRESETS -", ""), ("* BARN DOOR", ""), ("* SUNDAY", "")], sel=1,
                           hint="E2 pick  K3 use  K2 back", scroll=(0, 8, 6))
page_end_colour = screen([("ENCODERS", "#E9DFC8"), ("BUTTONS", "#1D4A4D"), ("FONT", "#F7F0DE"), ("SAVE", "name..."), ("DELETE", "* BARN DOOR")], sel=3,
                         hint="K3 save these colours", scroll=(4, 9, 6))
paths = {k: save(v, "bp_%s.png" % k) for k, v in dict(top=page_top, top_px=page_top_px, list_light=preset_list_light, end_colour=page_end_colour).items()}

def sheet(left, right, path):
    w = left.width + right.width + 30
    s = Image.new("RGB", (w, max(left.height, right.height) + 20), (24, 24, 26)); s.paste(left, (10, 10)); s.paste(right, (left.width + 20, 10)); s.save(path)

alu = render_aluminium(paths["top"])
pic1 = render_pixel(SETS["DARK"], paths["top_px"], lit=("PARAMS", "MIC"))
sheet(alu, pic1, os.path.join(OUT, "box-style-dark-vs-aluminium.png"))
pic_light = render_pixel(SETS["LIGHT"], paths["list_light"], lit=("KEYS",), hover="E2")
pic_colour = render_pixel(SETS["COLOUR"], paths["end_colour"], lit=("MIC", "MUTE"), down="K3")
sheet(pic_light, pic_colour, os.path.join(OUT, "box-style-light-and-colour.png"))
print("ok")
