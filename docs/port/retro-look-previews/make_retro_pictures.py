#!/usr/bin/env python3
"""the two pictures of docs/port/retro-look-plan.md. TODAY'S pixel style is drawn by the REAL code (box_style.c through ../box-style-previews/render_look.c, RENDER_STYLE=pixel). THE RETRO LOOKS DO NOT EXIST
IN THE PRODUCT: they are STAND-INS drawn here (Pillow) from the same layout table, the same five colours and the shade ramp the plan proposes, on a grid of B layout units per block (B = 4 or 3).
the norns screen text is a stand-in too (make_box_pictures.screen). usage: make_retro_pictures.py [OUTDIR]"""
import os, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "box-style-previews"))
import make_box_pictures as M
from PIL import Image, ImageDraw, ImageFont

OUT = sys.argv[1] if len(sys.argv) > 1 else HERE
tmp = tempfile.mkdtemp()

# ---------------------------------------------------------------- the shade ramp (7 shades per colour; today's four are s1 darker, s2 dark, s4 base, s5 light)
def mul(c, f): return tuple(round(v * f) for v in c)
def lit(c, t): return tuple(round(v + (255 - v) * t) for v in c)
def ramp(c): return [mul(c, .22), mul(c, .36), mul(c, .60), mul(c, .80), c, lit(c, .30), lit(c, .60)]

BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]   # ordered dither, 4 x 4 (16 levels)
def dith(a, b, t, x, y, mode):
    """blend a -> b by t (0..1) with a pattern that depends only on the block's x, y (deterministic)"""
    if mode == "checker": return b if (x + y) % 2 == 0 and t > 0.25 else (b if t > 0.75 else a)
    return b if (BAYER[y % 4][x % 4] + 0.5) / 16 < t else a

class G:
    def __init__(s, w, h, bg): s.w, s.h = w, h; s.im = Image.new("RGB", (w, h), bg); s.px = s.im.load()
    def put(s, x, y, c):
        if 0 <= x < s.w and 0 <= y < s.h: s.px[x, y] = c
    def rect(s, x0, y0, x1, y1, c):
        for y in range(int(y0), int(y1)):
            for x in range(int(x0), int(x1)): s.put(x, y, c)

def shape_in(w, h, cut):
    """a rectangle whose corners are cut stepwise: cut = blocks of the staircase (0 = square). returns a test (x, y) -> bool"""
    def f(x, y):
        if not (0 <= x < w and 0 <= y < h): return False
        dx = min(x, w - 1 - x); dy = min(y, h - 1 - y)
        return not (dx + dy < cut and dx < cut and dy < cut and (cut - dx) + (cut - dy) > cut + (0 if cut < 3 else cut // 3))
    return f

def rrect(g, x0, y0, w, h, cut, fill, outline, hi, sh, bevel=1, dither=None, fill2=None):
    ins = shape_in(w, h, cut)
    for y in range(h):
        for x in range(w):
            if not ins(x, y): continue
            c = fill if dither is None else dith(fill, fill2, 1 - y / max(1, h - 1), x0 + x, y0 + y, dither)
            if not (ins(x - 1, y) and ins(x + 1, y) and ins(x, y - 1) and ins(x, y + 1)): c = outline
            else:
                for d in range(1, bevel + 1):
                    if not (ins(x - 1 - d, y) and ins(x, y - 1 - d)): c = hi; break
                    if not (ins(x + 1 + d, y) and ins(x, y + 1 + d)): c = sh; break
            g.put(x0 + x, y0 + y, c)

def disc_in(cx, cy, r): return lambda x, y: (x + .5 - cx) ** 2 + (y + .5 - cy) ** 2 <= r * r

def render(v, colours, oled_png):
    B = v["B"]
    box, keys, encs, btns, font = [ramp(M.hexc(c)) for c in colours]
    W, H = 960 // B, -(-630 // B)             # the box in blocks (630 / 4 = 157.5: 158 blocks, 2 units taller)
    mg = -(-16 // B)
    g = G(W + 2 * mg, H + 2 * mg, box[1])
    ox = oy = mg
    sn = lambda u: int(round(u / B))           # a layout position in blocks (the snap)
    # the box: hard shadow, outline, face
    rrect(g, ox + 1, oy + 1, W, H, 6, box[0], box[0], box[0], box[0], 0)
    face_mode = v.get("face")
    rrect(g, ox, oy, W, H, 6, box[4], box[1], box[5], box[2], v["bevel"])
    spec = set()
    # the bezel (the screen's frame): 2 block frame, a light line below and right, black inside; the screen's place snapped to the grid when B = 4
    bx0, by0, bx1, by1 = sn(36), sn(300.667), sn(36 + 556), sn(300.667 + 293.333)
    keep = [(bx0 - 3, by0 - 3, bx1 + 3, by1 + 3)]
    BTN = [(n, x) for n, x in M.BTN]
    bw, bh = sn(70), sn(40)
    for n, x in BTN: keep.append((sn(x) - 1, sn(36) - 1, sn(x) + bw + 1, sn(36) + bh + 1))
    for cx, cy in M.KEY_C: keep.append((sn(cx) - sn(56) - 1, sn(cy) - sn(56) - 1, sn(cx) + sn(56) + 1, sn(cy) + sn(56) + 1))
    for cx, cy in M.ENC_C: keep.append((sn(cx) - sn(40) - 1, sn(cy) - sn(40) - 1, sn(cx) + sn(40) + 1, sn(cy) + sn(40) + 1))
    def free(x, y): return not any(a <= x < c and b <= y < d for a, b, c, d in keep)
    # the face texture: a calm vertical gradient (dithered) and sparse speckles, only where no control and no bezel is
    for y in range(1, H - 1):
        for x in range(1, W - 1):
            if not free(x, y): continue
            c = None
            if v.get("grad"):
                t = max(0.0, 1 - y / 14) * 0.55 if y < 14 else max(0.0, (y - (H - 16)) / 16) * 0.8
                if y < 14: c = dith(box[4], box[5], t, x, y, v["dither"])
                else:
                    c = dith(box[4], box[3], t, x, y, v["dither"]) if t > 0 else None
            if v.get("speckle") and ((x * 73856093) ^ (y * 19349663)) % v["speckle"] == 0:
                c = mul(box[4], .90) if ((x + y) & 1) else lit(box[4], .07)
            if v.get("scan") and y % 2 == 0 and c is None: c = dith(box[4], box[3], 0.14, x, y, "bayer")
            if c is not None: g.put(ox + x, oy + y, c)
    g.rect(ox + bx0 - 2, oy + by0 - 2, ox + bx1 + 2, oy + by1 + 2, box[1])
    g.rect(ox + bx0 - 1, oy + by1 + 1, ox + bx1 + 2, oy + by1 + 2, box[5]); g.rect(ox + bx1 + 1, oy + by0 - 1, ox + bx1 + 2, oy + by1 + 2, box[5])
    g.rect(ox + bx0, oy + by0, ox + bx1, oy + by1, (0, 0, 0))
    # a grille of slots, up in the empty part above the toast's place
    if v.get("grille"):
        for i in range(10):
            gx = ox + sn(420) + i * 3; gy = oy + sn(112)
            g.rect(gx, gy, gx + 2, gy + 6, box[0]); g.rect(gx, gy + 6, gx + 2, gy + 7, box[5])
    # buttons
    for n, x in BTN:
        if v.get("dropsh"): g.rect(ox + sn(x) + 1, oy + sn(36) + 1, ox + sn(x) + bw + 1, oy + sn(36) + bh + 1, box[1])
        isl = n in ("GRID",)
        face, ink = (font[4], btns[4]) if isl else (btns[4], font[4])
        fc2 = font[5] if isl else btns[5]
        rrect(g, ox + sn(x), oy + sn(36), bw, bh, v["bcut"], face, btns[0] if not isl else font[1], (face if False else (lit(face, .3) if True else face)), mul(face, .6), 1,
              dither=v.get("bdith"), fill2=lit(face, .12))
    # keys
    for cx, cy in M.KEY_C:
        s = 2 * sn(56)
        if v.get("dropsh"): g.rect(ox + sn(cx) - s // 2 + 1, oy + sn(cy) - s // 2 + 1, ox + sn(cx) + s // 2 + 1, oy + sn(cy) + s // 2 + 1, box[1])
        rrect(g, ox + sn(cx) - s // 2, oy + sn(cy) - s // 2, s, s, v["kcut"], keys[4], keys[0], keys[5], keys[2], v["kbevel"], dither=v.get("kdith"), fill2=keys[5])
    # encoders: a stepped disc, the rim, a pixel highlight, the cap, the notch
    for cx, cy in M.ENC_C:
        r = sn(40); ccx, ccy = ox + sn(cx), oy + sn(cy)
        for y in range(int(ccy - r) - 1, int(ccy + r) + 2):
            for x in range(int(ccx - r) - 1, int(ccx + r) + 2):
                d2 = (x + .5 - ccx) ** 2 + (y + .5 - ccy) ** 2
                if d2 > r * r: continue
                c = encs[4]
                if d2 > (r - 1) ** 2: c = encs[0]
                elif d2 > (r - 1 - v["rim"]) ** 2: c = encs[5] if (x + .5 - ccx) + (y + .5 - ccy) < -r * .6 else (encs[2] if (x + .5 - ccx) + (y + .5 - ccy) > r * .6 else encs[3])
                elif d2 <= (r * .55) ** 2: c = encs[3] if v.get("cap") else encs[4]
                if v.get("edith") and d2 <= (r - 1 - v["rim"]) ** 2 and d2 > (r * .55) ** 2:
                    t = ((x + .5 - ccx) + (y + .5 - ccy)) / (2 * r) + .5
                    c = dith(encs[5], encs[3], t, x, y, v["edith"])
                g.put(x, y, c)
        for dx, dy in v["hi"]: g.put(int(ccx + dx), int(ccy + dy), encs[6])
        g.rect(ccx - 1, ccy - r + 3, ccx + 1, ccy - r + 6, encs[0])
    # the picture at B units per block, the screen pasted at its place, the labels in half-block (2 unit) pixels
    big = g.im.resize((g.w * B, g.h * B), Image.NEAREST)
    oled = Image.open(oled_png).convert("RGB").resize((512, 256), Image.NEAREST)
    sx, sy = (76 - 16 + mg * B, 320 + mg * B) if B == 4 else (74 - 16 + mg * B, 335 - 16 + mg * B)
    big.paste(oled, (sx, sy))
    d = ImageDraw.Draw(big)
    fnt = M.FONT
    for n, x in BTN:
        isl = n in ("GRID",)
        ink = btns[4] if isl else font[4]; shadow = mul(font[4], .3) if isl else btns[0]
        w = int(fnt.getlength(n)) * 2
        tx = (ox + sn(x)) * B + (bw * B - w) // 2; ty = (oy + sn(36)) * B + (bh * B - 12) // 2 - 2
        for dd, col in ((((2, 2), shadow),) if (v.get("tshadow") and not isl) else ()) + (((0, 0), ink),):
            m = Image.new("1", (int(fnt.getlength(n)) + 4, 12), 0); dm = ImageDraw.Draw(m); dm.fontmode = "1"; dm.text((0, 0), n, font=fnt, fill=1); mp = m.load()
            for yy in range(12):
                for xx in range(m.width):
                    if mp[xx, yy]: d.rectangle([tx + dd[0] + xx * 2, ty + dd[1] + yy * 2, tx + dd[0] + xx * 2 + 1, ty + dd[1] + yy * 2 + 1], fill=col)
    # to the window size
    out = Image.new("RGB", (992, 662), box[1]); out.paste(big, ((992 - big.width) // 2, (662 - big.height) // 2))
    return out

VARS = {
    "recommended": dict(B=4, bevel=1, bcut=1, kcut=3, kbevel=1, rim=2, hi=[(-4, -5), (-3, -5), (-5, -4), (-4, -4)], cap=True, grad=False, speckle=190, grille=True, tshadow=True, dropsh=True, dither="bayer", edith="bayer", kdith=None, bdith=None),
    "chunky": dict(B=4, bevel=1, bcut=1, kcut=3, kbevel=2, rim=2, hi=[(-4, -5), (-3, -5)], cap=False, grad=False, speckle=0, grille=False, tshadow=False, dropsh=True, dither="bayer", edith=None, kdith=None, bdith=None),
    "dithered": dict(B=3, bevel=2, bcut=1, kcut=3, kbevel=1, rim=3, hi=[(-5, -6), (-4, -6), (-6, -5)], cap=True, grad=True, speckle=110, scan=True, grille=False, tshadow=False, dither="bayer", edith="bayer", kdith="bayer", bdith="checker"),
}

def label(im, text):
    d = ImageDraw.Draw(im); f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 20)
    d.rectangle([0, im.height - 30, im.width, im.height], fill=(18, 18, 20)); d.text((10, im.height - 27), text, font=f, fill=(235, 235, 235)); return im

def sheet(panels, path):
    w, h = panels[0].size; s = Image.new("RGB", (len(panels) * (w + 10) + 10, h + 20), (24, 24, 26))
    for i, im in enumerate(panels): s.paste(im, (10 + i * (w + 10), 10))
    s.save(path)

screen = M.save(M.screen([("STYLE", "PIXEL"), ("PRESET", "DARK"), ("BOX", "#2C2E33"), ("KEYS", "#444853"), ("ENCODERS", "#5D6270"), ("BUTTONS", "#3A3D45")], sel=2, hint="E2 row  E3 change  K3 hex", scroll=(0, 9, 6)), "retro_screen.png")
exe = os.path.join(tmp, "render_look")
skin = os.path.join(M.REPO, "matron", "src", "platform", "macos"); lin = os.path.join(M.REPO, "matron", "src", "platform", "linux")
flags = subprocess.check_output(["pkg-config", "--cflags", "--libs", "cairo", "freetype2"], text=True).split()
subprocess.check_call(["cc", "-std=gnu11", "-O1", "-DNORNS_LINUX_DESKTOP", "-I" + skin, "-I" + lin, os.path.join(M.REPO, "docs/port/box-style-previews/render_look.c"), os.path.join(skin, "device_skin.c"),
                       os.path.join(lin, "box_palette.c"), os.path.join(lin, "box_style.c"), "-o", exe] + flags + ["-lm"])
def today(colours):
    o = os.path.join(tmp, "today.png"); subprocess.check_call([exe, o, screen] + list(colours), env=dict(os.environ, RENDER_STYLE="pixel")); return Image.open(o).convert("RGB")
DARK, COLOUR = M.SETS["DARK"], M.SETS["COLOUR"]
sheet([label(today(DARK), "today's pixel style (the real code), DARK"), label(render(VARS["recommended"], DARK, screen), "recommended retro look (stand-in), DARK")], os.path.join(OUT, "retro-today-vs-recommended.png"))
sheet([label(render(VARS["chunky"], DARK, screen), "alternative A: chunky 8-bit (stand-in), DARK"), label(render(VARS["dithered"], COLOUR, screen), "alternative B: dithered 16-bit (stand-in), COLOUR")], os.path.join(OUT, "retro-alternatives.png"))
print("ok")
