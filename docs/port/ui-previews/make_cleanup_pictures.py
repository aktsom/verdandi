#!/usr/bin/env python3
"""the two pictures of docs/port/clean-layout.md: the proposed CLEAN UP page (a stand-in script drawn in the REAL window, example numbers) and the folder tree of the norns home.
usage: make_cleanup_pictures.py PAGE_CROP.png OUT_DIR"""
import os
import sys
import textwrap

from PIL import Image, ImageDraw, ImageFont

F = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
FM = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
page, out = sys.argv[1], sys.argv[2]

# 1. the page
im = Image.open(page).convert("RGB")
font = ImageFont.truetype(F, 15)
img = Image.new("RGB", (im.size[0], im.size[1] + 70), (32, 32, 34))
d = ImageDraw.Draw(img)
d.text((8, 5), "\n".join(textwrap.wrap("Proposed SYSTEM > CLEAN UP page (layout only, example numbers). Look at: is every group of files one line, with a size, and is the bottom line the only thing that deletes?", 62)), fill=(235, 235, 235), font=font)
img.paste(im, (0, 62))
img.save(os.path.join(out, "cleanup-page.png"))

# 2. the tree
mono = ImageFont.truetype(FM, 14)
small = ImageFont.truetype(F, 13)
lines = [
    ("~/Verdandi/                         the norns home (one folder; today it can be nested twice, see the plan)", "h"),
    ("  norns -> /opt/verdandi             link to the program (never a copy)", "n"),
    ("  dust/                              YOURS: scripts, audio, data, captures. Clean up never touches it", "u"),
    ("  audio.conf  ui.conf                YOURS: settings (two small files)", "u"),
    ("  matronrc.lua  version.txt          generated, tiny, needed", "n"),
    ("  logs/                              the last 5 runs of norns, sclang, jackd, maiden; launcher.log capped", "g"),
    ("    crash/                           the last 5 crash reports (one file per crash, made only at a crash)", "g"),
    ("  disabled/                          what Verdandi moved out of the way for you + MANIFEST.tsv (restorable)", "g"),
    ("  backups/                           made before any move of your files (a migration), with a manifest", "g"),
    ("  cache/                             caches of the libraries (graphics shader cache), capped, safe to delete", "g"),
    ("  .config/SuperCollider/             SuperCollider's own settings (it follows HOME: cannot move)", "s"),
    ("  .local/share/SuperCollider/        extensions: a seeded pack (stamped, ours) and anything you install", "s"),
    ("  .norns-* .mic-off .plugin-mismatch tiny marks, removed or rewritten at start", "s"),
    ("", "x"),
    ("outside the home: /opt/verdandi (the program), /usr/bin/verdandi, the desktop entry, the icon, the udev rule,", "o"),
    ("/usr/share/doc/verdandi (the package); systemd's coredumps (system managed);", "o"),
    ("~/.config/verdandi/home (only if you choose another home)", "o"),
]
col = {"h": (240, 240, 240), "n": (200, 200, 200), "u": (120, 200, 120), "g": (240, 200, 90), "s": (150, 170, 220), "o": (170, 170, 170), "x": (0, 0, 0)}
w = 1100
h = 70 + 21 * len(lines) + 60
t = Image.new("RGB", (w, h), (32, 32, 34))
d = ImageDraw.Draw(t)
d.text((8, 5), "\n".join(textwrap.wrap("The proposed layout of the norns home. Green = yours, never touched; yellow = made and managed by Verdandi, in a few fixed folders; blue = other programs' places that follow HOME; grey = tiny or generated. Look at: is every folder's job clear from its name?", 120)), fill=(235, 235, 235), font=small)
y = 62
for text, k in lines:
    d.text((10, y), text, fill=col[k], font=mono)
    y += 21
t.save(os.path.join(out, "cleanup-tree.png"))
