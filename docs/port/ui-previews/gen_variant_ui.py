#!/usr/bin/env python3
"""gen_variant_ui.py ARRANGEMENT LABELS OUTDIR: the layout of the owner's choice (round 2), made from a copy of the real device_skin.c / device_skin.h.
the product files are only read. one run makes one picture's skin: ARRANGEMENT a or b, LABELS 1 (K1..E3 text) or 0 (none).

 common to both
   box and window as today (960 x 630 units, 992 x 662 px at scale 1); margins of 36 units on all four sides: the page-button row starts at x 36 and ends at x 924
   at y 36; the bezel (the screen's recess, 540 x 284, the screen 512 x 256 at 4 px per screen pixel) is x 36..576, y 310..594.
   the OUT fader is gone; MUTE is the 11th button of the top row, same size (70 x 40), same style, same 6 unit spacing; three group gaps of 25.33 fill the row.
   keys and encoders 15 percent bigger: key well r 31 -> 35.65, cap 25 -> 28.75 (pressed 23 -> 26.45); encoder washer r 38 -> 43.7, knob 31 -> 35.65, top 25 -> 28.75.
 arrangement a (follows the standard norns legend): K1, E1 above the screen's left half, K1's well flush with the bezel's left edge; K2, K3, E2, E3 right of the screen,
   each encoder above and 78 units right of its key (as on the legend), the group centred in the free area right of the screen and on the screen's centre line.
 arrangement b (alternative): the three encoders and the keys in two bands: K1 E1 top left and E2 E3 top right on the same line, K2 K3 under their encoders at the
   bezel's bottom line.
"""
import sys, os, re

arr, labels, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
here = os.path.dirname(os.path.abspath(__file__))
skin = os.path.join(here, "../../../matron/src/platform/macos")
c = open(os.path.join(skin, "device_skin.c")).read()
h = open(os.path.join(skin, "device_skin.h")).read()

SCALE = 1.15
key_r, enc_r = 31 * SCALE, 38 * SCALE
margin = 36
row_y, btn_w, btn_h, gap_in = margin, 70, 40, 6
n_btn = 11
group_sizes = [4, 4, 2, 1]
total = 960 - 2 * margin
gap_group = (total - n_btn * btn_w - (n_btn - len(group_sizes)) * gap_in) / (len(group_sizes) - 1)
xs, x = [], float(margin)
for gi, gs in enumerate(group_sizes):
    for i in range(gs):
        xs.append(x)
        x += btn_w + (gap_in if i < gs - 1 else gap_group)
labels_txt = ["MIX", "TAPE", "HOME", "PARAMS", "MIC", "GRID", "ARC", "KEYS", "MAIDEN", "MANUAL", "MUTE"]

unit, pad = 4.0, 14
bw, bh = 128 * unit + 2 * pad, 64 * unit + 2 * pad
bx, by = float(margin), 630.0 - margin - bh
screen_cy = by + bh / 2
top_y = (row_y + btn_h + by) / 2          # K1/E1 centre line: halfway between the row and the bezel
k1 = (margin + key_r, top_y)
e1 = (k1[0] + 107 * SCALE, top_y)
if arr == "a":
    dy = 122 * SCALE
    ey, ky = screen_cy - dy / 2, screen_cy + dy / 2
    dxk = 78 * SCALE                       # the encoder is this far right of its key
    k2x = bx + bw + 28 + key_r             # 28 units between the bezel and K2's well
    k3x = k2x + 140
    e2x, e3x = k2x + dxk, k3x + dxk
    k2, k3, e2, e3 = (k2x, ky), (k3x, ky), (e2x, ey), (e3x, ey)
else:
    right = 960.0 - margin
    e3 = (right - enc_r, top_y)
    e2 = (e3[0] - 140, top_y)
    kyb = by + bh - key_r                  # the keys' wells end on the bezel's bottom line
    k2, k3 = (e2[0], kyb), (e3[0], kyb)

def rep(s, a, b):
    assert a in s, a
    return s.replace(a, b)

c = rep(c, "static const double bezel_x = 77, bezel_y = 356, bezel_w = 417, bezel_h = 220;",
        "static const double bezel_x = %.3f, bezel_y = %.3f, bezel_w = %.3f, bezel_h = %.3f;" % (bx, by, bw, bh))
c = rep(c, "static const pt_t key_pos[3] = {{109, 252}, {594, 542}, {749, 542}};",
        "static const pt_t key_pos[3] = {{%.2f, %.2f}, {%.2f, %.2f}, {%.2f, %.2f}};" % (k1 + k2 + k3))
c = rep(c, "static const pt_t enc_pos[3] = {{216, 252}, {672, 420}, {827, 420}};",
        "static const pt_t enc_pos[3] = {{%.2f, %.2f}, {%.2f, %.2f}, {%.2f, %.2f}};" % (e1 + e2 + e3))
c = rep(c, "static const double key_r = 31;", "static const double key_r = %.2f;" % key_r)
c = rep(c, "static const double enc_r = 38; // washer; the knob itself is 31", "static const double enc_r = %.2f; // washer; the knob itself is %.2f" % (enc_r, 31 * SCALE))
c = rep(c, "    double r = down ? 23 : 25;", "    double r = down ? %.2f : %.2f;" % (23 * SCALE, 25 * SCALE))
c = rep(c, "    const double r = 31, top = 25;", "    const double r = %.2f, top = %.2f;" % (31 * SCALE, 25 * SCALE))
c = rep(c, "key_r - 4);", "key_r - %.2f);" % (4 * SCALE))
# the button row: 11 buttons, MUTE last, the row at the margin
btn = "static const button_t buttons[] = {\n" + "".join('    {%.2f, "%s"},\n' % (xs[i], labels_txt[i]) for i in range(n_btn)) + "};"
c = re.sub(r"static const button_t buttons\[\] = \{.*?\n\};", lambda m: btn, c, count=1, flags=re.S)
c = rep(c, "static const double button_y = 70, button_w = 70, button_h = 40;", "static const double button_y = %d, button_w = 70, button_h = 40;" % row_y)
# no fader hit area, no separate MUTE hit area (MUTE is a button of the row)
c = rep(c, """    if (fabs(p.x - fader_x) <= fader_cap_w / 2 + 6 && p.y >= fader_top - fader_cap_h && p.y <= fader_bottom + fader_cap_h) {
        return SKIN_FADER;
    }
    if (p.x >= mute_x - 3 && p.x <= mute_x + mute_w + 3 && p.y >= mute_y - 3 && p.y <= mute_y + mute_h + 3) {
        return SKIN_MUTE;
    }
""", "")
c = rep(c, "(id == SKIN_MIC && st->input != SKIN_INPUT_OFF);", "(id == SKIN_MIC && st->input != SKIN_INPUT_OFF) || (id == SKIN_MUTE && st->out_muted);")
c = rep(c, "    if (id <= SKIN_KEYS) {\n        draw_led", "    if (id <= SKIN_KEYS || id == SKIN_MUTE) {\n        draw_led")
c = rep(c, "    draw_fader(cr, st);\n", "")
c = rep(c, "static void draw_fader(", "__attribute__((unused)) static void draw_fader(")
c = rep(c, "int hover = st->hover == SKIN_FADER;", "int hover = 0;")
if not labels:
    c = rep(c, "        draw_label(cr, key_pos[i], key_r, names[i][0]);\n        draw_label(cr, enc_pos[i], enc_r, names[i][1]);\n", "        (void)names;\n")
h = rep(h, "    SKIN_FADER = 17, // the OUT fader right of E3 (not on the device): norns' output level\n    SKIN_MUTE = 18,  // under it: output off and back",
        "    SKIN_MUTE = 17, // the last button of the top row: output off and back")
open(os.path.join(out, "device_skin_variant.c"), "w").write(c)
open(os.path.join(out, "device_skin.h"), "w").write(h)
open(os.path.join(out, "variant.h"), "w").write(
    "#define V_UNIT %.4f\n#define V_BEZEL_X %.3f\n#define V_BEZEL_Y %.3f\n#define V_BEZEL_W %.3f\n#define V_BEZEL_H %.3f\n#define V_PAD %d\n#define V_DX 0\n"
    % (unit, bx, by, bw, bh, pad))
# the numbers, for ui-plan.md
open(os.path.join(out, "numbers.txt"), "w").write(
    "arrangement %s labels %d\nbezel x %.1f..%.1f y %.1f..%.1f screen %d x %d\nbuttons x: %s (y %d, %d x %d)\nK1 %.1f,%.1f K2 %.1f,%.1f K3 %.1f,%.1f\nE1 %.1f,%.1f E2 %.1f,%.1f E3 %.1f,%.1f\nkey r %.2f enc r %.2f\n"
    % (arr, labels, bx, bx + bw, by, by + bh, 128 * unit, 64 * unit, " ".join("%.1f" % v for v in xs), row_y, btn_w, btn_h, *(k1 + k2 + k3), *(e1 + e2 + e3), key_r, enc_r))
print(open(os.path.join(out, "numbers.txt")).read())

# hit-test expectations for hit_check.c (ids: K1-K3 = 1..3, E1-E3 = 4..6, the buttons from 7: PAGE1..PAGE4, MIC, GRID, ARC, KEYS, MAIDEN, MANUAL, MUTE = 17; 0 = nothing)
pts = []
for i, p in enumerate((k1, k2, k3)):
    pts.append((p[0], p[1], 1 + i)); pts.append((p[0] + key_r + 3, p[1], 1 + i))
for i, p in enumerate((e1, e2, e3)):
    pts.append((p[0], p[1], 4 + i)); pts.append((p[0] + enc_r + 3, p[1], 4 + i))
for i in range(n_btn):
    pts.append((xs[i] + btn_w / 2, row_y + btn_h / 2, 7 + i))
for gi in (3, 7, 9):   # the gaps between button groups
    pts.append(((xs[gi] + btn_w + xs[gi + 1]) / 2, row_y + btn_h / 2, 0))
pts.append((bx + bw / 2, by + bh / 2, 0))   # the screen
pts.append((913, 340, 0))                   # where the fader was
if arr == 'a':
    pts.append((886 + 27, 537, 0))          # where MUTE was (arrangement b has K3 there)
pts.append((480, 140, 0))                   # the free band under the buttons
open(os.path.join(out, "hits.h"), "w").write("static const double CHK[][3] = {\n" + "".join("    {%.2f, %.2f, %d},\n" % p for p in pts) + "};\n")

# spacing checks (units): the hit areas (key r + 6, encoder r + 6, buttons 3 beyond their well) do not overlap each other, the bezel (3 lip) or the box edge
def gap_circle(a, ra, b, rb): return ((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2) ** 0.5 - ra - rb
ctrl = [("K1", k1, key_r + 6), ("K2", k2, key_r + 6), ("K3", k3, key_r + 6), ("E1", e1, enc_r + 6), ("E2", e2, enc_r + 6), ("E3", e3, enc_r + 6)]
lines = []
mn = min((gap_circle(a[1], a[2], b[1], b[2]), a[0] + "-" + b[0]) for i, a in enumerate(ctrl) for b in ctrl[i + 1:])
lines.append("smallest gap between two hit circles: %.1f units (%s)" % mn)
def gap_rect(p, r, x0, y0, x1, y1):
    dx = max(x0 - p[0], 0, p[0] - x1); dy = max(y0 - p[1], 0, p[1] - y1)
    return (dx * dx + dy * dy) ** 0.5 - r if (dx or dy) else -r
bz = (bx - 3, by - 3, bx + bw + 3, by + bh + 3)
row = (xs[0] - 3, row_y - 3, xs[-1] + btn_w + 3, row_y + btn_h + 3)
g_bez = min((gap_rect(p, r, *bz), n) for n, p, r in ctrl)
g_row = min((gap_rect(p, r, *row), n) for n, p, r in ctrl)
g_edge = min((min(p[0] - r, 960 - p[0] - r, p[1] - r, 630 - p[1] - r), n) for n, p, r in ctrl)
lines.append("smallest gap hit circle - bezel (with its lip): %.1f (%s); - button row (hit area): %.1f (%s); - box edge: %.1f (%s)" % (g_bez + g_row + g_edge))
open(os.path.join(out, "checks.txt"), "w").write("\n".join(lines) + "\n")
print("\n".join(lines))
