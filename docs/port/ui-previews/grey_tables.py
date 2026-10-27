#!/usr/bin/env python3
"""grey_tables.py OUTDIR: the grey tables of the previews. a table is 256 numbers (input grey -> output grey of the oled image, 0 and 255 stay).
the oled has 16 levels, level n is grey n*17 on the desktop screen today (cairo draws the screen in grey, level/15); the anti-aliased edges of
text have the greys in between, so the tables are curves, evaluated at every grey, and the 16 level values are printed in levels.txt.
  current  : out = in                         (level 4 -> 68, 27 %)
  gamma07  : out = 255 * (in/255) ** 0.70     (level 4 -> 102, 40 %)
  gamma05  : out = 255 * (in/255) ** 0.50     (level 4 -> 132, 52 %)
"""
import sys, os
out = sys.argv[1]
tables = {"current": 1.0, "gamma07": 0.70, "gamma05": 0.50}
lines = ["level  " + "  ".join("%-8s" % n for n in tables)]
rows = {n: [] for n in tables}
for n, gm in tables.items():
    t = [int(round(255 * (v / 255.0) ** gm)) for v in range(256)]
    open(os.path.join(out, n + ".lut"), "w").write("\n".join(map(str, t)) + "\n")
    rows[n] = [t[l * 17] for l in range(16)]
for l in range(16):
    lines.append("%5d  " % l + "  ".join("%-8s" % ("%d (%d%%)" % (rows[n][l], round(rows[n][l] * 100 / 255))) for n in tables))
open(os.path.join(out, "levels.txt"), "w").write("\n".join(lines) + "\n")
print("\n".join(lines))
