#!/usr/bin/env python3
"""stage 1 of the colour work (docs/port/box-style-plan.md, "Stage 1: how the brushed aluminium takes a tint"): the two pictures. every aluminium window is drawn by the REAL skin code
(device_skin.c with NORNS_LINUX_DESKTOP and skin_set_look, via render_look.c); the pixel windows are drawn by the real box_style.c (RENDER_STYLE=pixel); the screen text is a stand-in. usage: make_tint_pictures.py OUT_DIR"""
import os, subprocess, sys, tempfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_box_pictures as M
from PIL import Image

OUT = sys.argv[1] if len(sys.argv) > 1 else M.HERE
tmp = tempfile.mkdtemp()
exe = os.path.join(tmp, "render_look")
skin = os.path.join(M.REPO, "matron", "src", "platform", "macos"); lin = os.path.join(M.REPO, "matron", "src", "platform", "linux")
flags = subprocess.check_output(["pkg-config", "--cflags", "--libs", "cairo", "freetype2"], text=True).split()
subprocess.check_call(["cc", "-std=gnu11", "-O1", "-DNORNS_LINUX_DESKTOP", "-I" + skin, "-I" + lin, os.path.join(M.HERE, "render_look.c"), os.path.join(skin, "device_skin.c"),
                       os.path.join(lin, "box_palette.c"), os.path.join(lin, "box_style.c"), "-o", exe] + flags + ["-lm"])
screen = M.save(M.screen([("STYLE", "ALUMINIUM"), ("PRESET", "CUSTOM"), ("BOX", "#3B6EA8"), ("KEYS", "#404246"), ("ENCODERS", "#DCDDE0"), ("BUTTONS", "#303135")], sel=2,
                         hint="E2 row  E3 change  K3 hex", scroll=(0, 9, 6)), "tint_screen.png")

def alu(colours, name, style="aluminium"):
    out = os.path.join(tmp, name + ".png")
    env = dict(os.environ, RENDER_STYLE=style)
    subprocess.check_call([exe, out, screen] + [c if c else "-" for c in colours], env=env)
    return Image.open(out).convert("RGB")

def label(im, text):
    from PIL import ImageDraw, ImageFont
    d = ImageDraw.Draw(im); f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 22)
    d.rectangle([0, im.height - 34, im.width, im.height], fill=(20, 20, 22)); d.text((10, im.height - 30), text, font=f, fill=(235, 235, 235)); return im

def sheet(panels, path):
    w, h = panels[0].size; cols = 3; rows = (len(panels) + cols - 1) // cols
    s = Image.new("RGB", (cols * (w + 10) + 10, rows * (h + 10) + 10), (24, 24, 26))
    for i, im in enumerate(panels): s.paste(im, (10 + (i % cols) * (w + 10), 10 + (i // cols) * (h + 10)))
    s = s.resize((s.width * 55 // 100, s.height * 55 // 100), Image.LANCZOS); s.save(path)

pix = alu(M.SETS["DARK"], "pix", "pixel")
a = [label(alu((None,) * 5, "a1"), "aluminium, today's grey (the default: not tinted)"), label(alu(("3a3d44", None, None, None, None), "a2"), "dark grey box  3A3D44"),
     label(alu(("3b6ea8", None, None, None, None), "a3"), "blue box  3B6EA8"), label(alu(("d9a066", None, None, None, None), "a4"), "warm box  D9A066"),
     label(pix, "pixel style, DARK look")]
sheet(a, os.path.join(OUT, "tint-aluminium-four.png"))
b = [label(alu((None, "e8a317", None, "1f4f6b", "f2f2f2"), "b1"), "grey box, amber keys E8A317, teal-blue buttons 1F4F6B"),
     label(alu(("3a3d44", "ff6b5a", "d8d8d8", "20242b", "ffd8c8"), "b2"), "dark grey box, coral keys FF6B5A, dark buttons"),
     label(alu(("3b6ea8", "f6e05e", "e8eef8", "142a4a", "ffffff"), "b3"), "blue box, yellow keys F6E05E, navy buttons"),
     label(alu(("d9a066", "4a2f1c", "f4e9d8", "7a3b1d", "fff1dc"), "b4"), "warm box, brown keys 4A2F1C, rust buttons 7A3B1D"),
     label(alu(M.SETS["COLOUR"], "pixc", "pixel"), "pixel style, COLOUR look")]
sheet(b, os.path.join(OUT, "tint-aluminium-contrast.png"))
print("ok")
