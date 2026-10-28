#!/usr/bin/env python3
"""gen_variant_margin.py MODE OUTDIR: layouts of the black margin around the screen (ui-plan.md section 1.8). a copy of the current Linux layout of the real
device_skin.c (built with NORNS_LINUX_DESKTOP) with the bezel changed; the product files are only read.

 MODE today    the current Linux layout: bezel 540 x 284, screen 512 x 256 (4 px per screen pixel), margin 14 on all sides (variant.h only)
 MODE abs      the Mac's margins in units (16.5 left and right, 14 top and bottom) around the 4 px screen: bezel 545 x 284
 MODE shrink   the Mac's margins as a fraction of the screen (4.297 % of its width on each side, 7.292 % of its height above and below), the bezel kept at
               540 x 284: the screen becomes 495.7 x 247.9 (3.873 px per screen pixel)
 MODE grow     the same proportions around the 4 px screen (512 x 256): the bezel grows to 556 x 293.3 (bottom edge kept at y 594, left edge at x 36), K1 and E1
               and the right cluster move to stay balanced (K2 K3 E2 E3 16 units right, 130 units between the pairs, the cluster centred on the bezel)
"""
import sys, os
mode, out = sys.argv[1], sys.argv[2]
here = os.path.dirname(os.path.abspath(__file__))
skin = os.path.join(here, "../../../matron/src/platform/macos")
c = open(os.path.join(skin, "device_skin.c")).read()
MX, MY = 16.5 / 384, 14.0 / 192            # the Mac's margins as a fraction of the screen's width and height
bx, bw, bh, unit = 36.0, 540.0, 284.0, 4.0
by_bottom = 594.0
if mode == "abs":
    bw = 512 + 33
elif mode == "shrink":
    sw = min(540 / (1 + 2 * MX), 2 * 284 / (1 + 2 * MY))
    unit = sw / 128
elif mode == "grow":
    bw, bh = 512 * (1 + 2 * MX), 256 * (1 + 2 * MY)
by = by_bottom - bh
def rep(s, a, b):
    assert a in s, a
    return s.replace(a, b, 1)
if mode != "today":
    c = rep(c, "static const double bezel_x = 36, bezel_y = 310, bezel_w = 540, bezel_h = 284;",
            "static const double bezel_x = %.3f, bezel_y = %.3f, bezel_w = %.3f, bezel_h = %.3f;" % (bx, by, bw, bh))
if mode == "grow":
    row_bottom = 36 + 40
    top = (row_bottom + by) / 2
    k2x = bx + bw + 3 + 25 + 35.65
    cy = by + bh / 2
    dy = 140.3
    c = rep(c, "static const pt_t key_pos[3] = {{71.65, 193}, {639.65, 522.15}, {779.65, 522.15}};",
            "static const pt_t key_pos[3] = {{71.65, %.2f}, {%.2f, %.2f}, {%.2f, %.2f}};" % (top, k2x, cy + dy / 2, k2x + 130, cy + dy / 2))
    c = rep(c, "static const pt_t enc_pos[3] = {{194.7, 193}, {729.35, 381.85}, {869.35, 381.85}};",
            "static const pt_t enc_pos[3] = {{194.7, %.2f}, {%.2f, %.2f}, {%.2f, %.2f}};" % (top, k2x + 89.7, cy - dy / 2, k2x + 130 + 89.7, cy - dy / 2))
open(os.path.join(out, "device_skin_variant.c"), "w").write(c)
open(os.path.join(out, "variant.h"), "w").write(
    "#define V_UNIT %.4f\n#define V_BEZEL_X %.3f\n#define V_BEZEL_Y %.3f\n#define V_BEZEL_W %.3f\n#define V_BEZEL_H %.3f\n#define V_PAD 14\n#define V_DX 0\n" % (unit, bx, by, bw, bh))
sw, sh = 128 * unit, 64 * unit
print("%-6s bezel %.1f x %.1f (x %.1f..%.1f, y %.1f..%.1f), screen %.1f x %.1f = %.3f px per screen pixel, margins: left/right %.2f, top/bottom %.2f units = %.2f %% of the screen width, %.2f %% of its height" %
      (mode, bw, bh, bx, bx + bw, by, by + bh, sw, sh, unit, (bw - sw) / 2, (bh - sh) / 2, 100 * (bw - sw) / 2 / sw, 100 * (bh - sh) / 2 / sh))
