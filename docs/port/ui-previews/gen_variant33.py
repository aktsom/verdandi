#!/usr/bin/env python3
"""gen_variant33.py MODE OUTDIR: the +33 percent layout: the screen at exactly 4 device pixels per screen pixel (512 x 256 units at scale 1; whole
pixels, so crisp and even). a copy of the real device_skin.c and device_skin.h with other constants, plus variant.h; the product files are only read.

MODE  keep   the box and window keep today's size (960 x 630 units): the bezel moves to x 36 and bottom 600, K1 and E1 move up 30, and
             the right cluster (K2, K3, E2, E3) is re-spaced closer so that it fits between the bezel and the OUT fader.
MODE  wide   the box grows in width by 26 units (and the window with it): the cluster keeps its spacing and moves right, the fader and MUTE with it.
"""
import sys, os

mode = sys.argv[1]
out = sys.argv[2]
here = os.path.dirname(os.path.abspath(__file__))
skin = os.path.join(here, "../../../matron/src/platform/macos")
c = open(os.path.join(skin, "device_skin.c")).read()
h = open(os.path.join(skin, "device_skin.h")).read()

unit, pad = 4.0, 14
bw, bh = 128 * unit + 2 * pad, 64 * unit + 2 * pad  # 540 x 284
bx, by = 36.0, 600.0 - bh                           # bezel 36..576, 316..600
up = 30                                             # K1 and E1 move up so that the bezel's top clears E1's label
k1, e1 = (109, 252 - up), (216, 252 - up)
if mode == "keep":
    grow = 0
    # the cluster closer together: K2 at 634 (31 units of well from the bezel's edge plus 27 of space), 130 between K2 and K3 (now 155),
    # E2 78 right of K2 as now (672 - 594), E3 130 right of E2
    k2x, k3x = 634, 764
    e2x, e3x = 712, 842
    fader_x, mute_x = 913, 886
else:
    grow = 26
    dx = 38
    k2x, k3x = 594 + dx, 749 + dx
    e2x, e3x = 672 + dx, 827 + dx
    fader_x, mute_x = 913 + grow, 886 + grow

def rep(s, a, b):
    assert a in s, a
    return s.replace(a, b)

c = rep(c, "static const double bezel_x = 77, bezel_y = 356, bezel_w = 417, bezel_h = 220;",
        "static const double bezel_x = %.3f, bezel_y = %.3f, bezel_w = %.3f, bezel_h = %.3f;" % (bx, by, bw, bh))
c = rep(c, "static const pt_t key_pos[3] = {{109, 252}, {594, 542}, {749, 542}};",
        "static const pt_t key_pos[3] = {{%d, %d}, {%d, 542}, {%d, 542}};" % (k1[0], k1[1], k2x, k3x))
c = rep(c, "static const pt_t enc_pos[3] = {{216, 252}, {672, 420}, {827, 420}};",
        "static const pt_t enc_pos[3] = {{%d, %d}, {%d, 420}, {%d, 420}};" % (e1[0], e1[1], e2x, e3x))
c = rep(c, "static const double fader_x = 913,", "static const double fader_x = %d," % fader_x)
c = rep(c, "static const double mute_x = 886,", "static const double mute_x = %d," % mute_x)
h = rep(h, "#define SKIN_W 960", "#define SKIN_W %d" % (960 + grow))
open(os.path.join(out, "device_skin_variant.c"), "w").write(c)
open(os.path.join(out, "device_skin.h"), "w").write(h)
open(os.path.join(out, "variant.h"), "w").write(
    "#define V_UNIT %.4f\n#define V_BEZEL_X %.3f\n#define V_BEZEL_Y %.3f\n#define V_BEZEL_W %.3f\n#define V_BEZEL_H %.3f\n#define V_PAD %d\n#define V_DX 0\n"
    % (unit, bx, by, bw, bh, pad))
print("plus33 %s: 4 device px per oled pixel, oled %d x %d, bezel x %.0f..%.0f y %.0f..%.0f, box %d x 630 units, window %d x %d" %
      (mode, 128 * unit, 64 * unit, bx, bx + bw, by, by + bh, 960 + grow, 992 + grow, 662))
