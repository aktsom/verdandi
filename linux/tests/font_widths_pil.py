#!/usr/bin/env python3
"""linux/tests/font_widths_pil.py FONT SIZE > table: the table of font metrics that linux/tests/font_widths_dump.c makes (cairo), made with Pillow instead, for a machine without cairo (a development stand-in: the numbers can
differ from cairo's by a fraction of a pixel; the CI uses the real table). usage: python3 linux/tests/font_widths_pil.py resources/liquid.ttf 8 > /tmp/fw.txt; FONT_WIDTHS=/tmp/fw.txt lua5.3 linux/tests/audio_page_windows_test.lua"""
import sys
from PIL import ImageFont
f = ImageFont.truetype(sys.argv[1], float(sys.argv[2]), layout_engine=ImageFont.Layout.BASIC)
for c in range(32, 127):
    ch = chr(c)
    bb = f.getbbox(ch) if ch != " " else (0, 0, 0, 0)
    print("C %d %s %s %s" % (c, f.getlength(ch), bb[0], max(0, bb[2] - bb[0])))
