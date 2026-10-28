#!/usr/bin/env python3
"""gen_variant.py FACTOR OUTDIR: a copy of the real matron/src/platform/macos/device_skin.c with the screen FACTOR times bigger and the other
controls nudged, plus variant.h with the numbers the preview renderer needs. the product source is only read.

  the oled is drawn 3 device pixels per oled pixel today (3.04 fits, the code floors to a whole number): FACTOR 1.22 means 3.66 pixels
  per oled pixel. the bezel is the oled plus the 14 unit pad on every side, its left edge 36 units from the box edge and its bottom edge
  at y=600 (it is now at 77 and 576). K2, K3, E2 and E3 move right by round((FACTOR-1)*48) units. nothing else moves, nothing changes size.
"""
import sys, re, os

factor = float(sys.argv[1])
out = sys.argv[2]
src = os.path.join(os.path.dirname(os.path.abspath(__file__)), "base/device_skin.c")
s = open(src).read()
unit = 3.0 * factor
pad = 14
bw = 128 * unit + 2 * pad
bh = 64 * unit + 2 * pad
bx = 36.0
by = 600.0 - bh
dx = round((factor - 1) * 48)

old_bezel = "static const double bezel_x = 77, bezel_y = 356, bezel_w = 417, bezel_h = 220;"
assert old_bezel in s
s = s.replace(old_bezel, "static const double bezel_x = %.3f, bezel_y = %.3f, bezel_w = %.3f, bezel_h = %.3f;" % (bx, by, bw, bh))
old_keys = "static const pt_t key_pos[3] = {{109, 252}, {594, 542}, {749, 542}};"
old_encs = "static const pt_t enc_pos[3] = {{216, 252}, {672, 420}, {827, 420}};"
assert old_keys in s and old_encs in s
s = s.replace(old_keys, "static const pt_t key_pos[3] = {{109, 252}, {%d, 542}, {%d, 542}};" % (594 + dx, 749 + dx))
s = s.replace(old_encs, "static const pt_t enc_pos[3] = {{216, 252}, {%d, 420}, {%d, 420}};" % (672 + dx, 827 + dx))
open(os.path.join(out, "device_skin_variant.c"), "w").write(s)
open(os.path.join(out, "variant.h"), "w").write(
    "#define V_UNIT %.4f\n#define V_BEZEL_X %.3f\n#define V_BEZEL_Y %.3f\n#define V_BEZEL_W %.3f\n#define V_BEZEL_H %.3f\n#define V_PAD %d\n#define V_DX %d\n"
    % (unit, bx, by, bw, bh, pad, dx))
print("factor %.2f: %.2f device px per oled pixel, oled %.0f x %.0f, bezel x %.1f..%.1f y %.1f..%.1f, right cluster +%d" %
      (factor, unit, 128 * unit, 64 * unit, bx, bx + bw, by, by + bh, dx))
