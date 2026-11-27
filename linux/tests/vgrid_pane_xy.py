#!/usr/bin/env python3
"""vgrid_pane_xy.py (M41, linux/tests/vgrid_pane_check.sh): where, inside the virtual grid window, a key or a button is, in window pixels.
the numbers are the drawing's own (matron/src/platform/macos/vgrid_skin.c): key pitch 44 units, key 31, 26.5 from the plate edge to the first key, margin 18, bar 50 with buttons of 64 x 26 (ROTATE 88 wide), gap 8.
   vgrid_pane_xy.py key <cols> <rows> <rot> <c> <r> <window w> <window h>   -> "x y": the centre of the device key (c, r) as the turned plate draws it
   vgrid_pane_xy.py button <cols> <rows> <rot> <1-4> <window w> <window h>  -> "x y": the centre of a button of the bar (4 = ROTATE)
   vgrid_pane_xy.py units <cols> <rows> <rot>                               -> "w h" the window in layout units
"""
import math
import sys

PITCH, KEY, EDGE, MARGIN, BAR, SW_W, SW_H, SW_GAP, ROT_W = 44.0, 31.0, 26.5, 18.0, 50.0, 64.0, 26.0, 8.0, 88.0


def to_screen(rot, cols, rows, c, r):
    rot &= 3
    if rot == 1:
        return rows - 1 - r, c
    if rot == 2:
        return cols - 1 - c, rows - 1 - r
    if rot == 3:
        return r, cols - 1 - c
    return c, r


def plate(n):
    return 2 * EDGE + (n - 1) * PITCH + KEY


def units(cols, rows, rot):
    sc, sr = (rows, cols) if rot & 1 else (cols, rows)
    return math.ceil(plate(sc) + 2 * MARGIN), math.ceil(plate(sr) + 2 * MARGIN + BAR), sc, sr


def layout(cols, rows, rot, w, h):
    uw, uh, sc, sr = units(cols, rows, rot)
    s = min(w / uw, h / uh)
    return s, (w - uw * s) / 2, (h - uh * s) / 2, sc, sr


def main():
    a = sys.argv[1:]
    if a[0] == "units":
        uw, uh, _, _ = units(int(a[1]), int(a[2]), int(a[3]))
        print(uw, uh)
        return
    cols, rows, rot = int(a[1]), int(a[2]), int(a[3])
    if a[0] == "key":
        c, r, w, h = int(a[4]), int(a[5]), float(a[6]), float(a[7])
        s, ox, oy, _, _ = layout(cols, rows, rot, w, h)
        sc, sr = to_screen(rot, cols, rows, c, r)
        x = MARGIN + EDGE + sc * PITCH + KEY / 2
        y = MARGIN + EDGE + sr * PITCH + KEY / 2
    else:
        i, w, h = int(a[4]), float(a[5]), float(a[6])
        s, ox, oy, sc, sr = layout(cols, rows, rot, w, h)
        widths = [SW_W, SW_W, SW_W, ROT_W]
        total = sum(widths) + 3 * SW_GAP
        x0 = MARGIN + (plate(sc) - total) / 2 + sum(widths[: i - 1]) + (i - 1) * SW_GAP
        x = x0 + widths[i - 1] / 2
        y = MARGIN + plate(sr) + (BAR - SW_H) / 2 + 4 + SW_H / 2
    print(int(ox + x * s), int(oy + y * s))


main()
