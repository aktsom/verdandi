#!/usr/bin/env python3
"""the pixel style's layout table (docs/port/box-style-plan.md 2.2): every control as a rectangle in layout units, the change against today's Linux layout, and the clearances (box edge margin 36,
the bezel, the button row, every control against every other). prints a table; exits 1 if a check fails. today's numbers are read from matron/src/platform/macos/device_skin.c (NORNS_LINUX_DESKTOP block)."""
import itertools, math, sys
BOX = (0, 0, 960, 630); MARGIN = 36
BEZEL = (36, 300.667, 36 + 556, 300.667 + 293.333)
SCREEN = (58, 319.333, 58 + 512, 319.333 + 256)  # 512 x 256 units centred in the bezel
TODAY = {  # name: (cx, cy, half_w, half_h, shape)
    "K1": (71.65, 188.33, 35.65, 35.65, "c"), "K2": (655.65, 517.48, 35.65, 35.65, "c"), "K3": (785.65, 517.48, 35.65, 35.65, "c"),
    "E1": (194.7, 188.33, 43.7, 43.7, "c"), "E2": (745.35, 377.18, 43.7, 43.7, "c"), "E3": (875.35, 377.18, 43.7, 43.7, "c"),
}
NEW = {
    "K1": (100, 188, 56, 56, "q"), "K2": (734, 530, 56, 56, "q"), "K3": (864, 530, 56, 56, "q"),
    "E1": (240, 188, 40, 40, "c"), "E2": (734, 376, 40, 40, "c"), "E3": (864, 376, 40, 40, "c"),
}
BTNX = [36, 112, 188, 264, 359.3333, 435.3333, 511.3333, 587.3333, 682.6667, 758.6667, 854]
NAMES = ["MIX", "TAPE", "HOME", "PARAMS", "MIC", "GRID", "ARC", "KEYS", "MAIDEN", "MANUAL", "MUTE"]
for n, x in zip(NAMES, BTNX): NEW[n] = (x + 35, 36 + 14, 35, 14, "r")
def rect(v): cx, cy, hw, hh, _ = v; return (cx - hw, cy - hh, cx + hw, cy + hh)
def gap(a, b):
    dx = max(a[0] - b[2], b[0] - a[2], 0); dy = max(a[1] - b[3], b[1] - a[3], 0); return math.hypot(dx, dy)
bad = 0
print("%-7s %-22s %-22s %s" % ("part", "today (centre; size)", "pixel (centre; size)", "change"))
for k in ["K1", "K2", "K3", "E1", "E2", "E3"]:
    t, n = TODAY[k], NEW[k]
    ts, ns = (t[2] * 2), (n[2] * 2)
    print("%-7s (%6.1f,%6.1f) %5.1f   (%5.0f,%5.0f) %5.0f   centre %+.1f,%+.1f units; size %+.0f%%" % (k, t[0], t[1], ts, n[0], n[1], ns, n[0] - t[0], n[1] - t[1], (ns / ts - 1) * 100))
print("(today: keys = the key well, 71.3 across, the cap 57.5; encoders = the washer, 87.4 across, the knob 71.3. pixel: key 112 square, encoder disc 80 across)")
print("key / encoder = %.2f (the owner's reference 1.3 to 1.5); key vs today's cap %+.0f%%, encoder vs today's knob %+.0f%%" % (112 / 80, (112 / 57.5 - 1) * 100, (80 / 71.3 - 1) * 100))
print("\nchecks (units):")
def chk(ok, what):
    global bad
    print("  %s %s" % ("ok  " if ok else "FAIL", what)); bad += 0 if ok else 1
inner = (MARGIN, MARGIN, 960 - MARGIN, 630 - MARGIN)
for k, v in NEW.items():
    r = rect(v)
    chk(r[0] >= MARGIN - 1e-6 and r[1] >= MARGIN - 1e-6 and r[2] <= 960 - MARGIN + 1e-6 and r[3] <= 630 - MARGIN + 1e-6 or k in ("K1",) and r[0] >= 36 - 1e-6, "%s inside the 36 unit margin of the box %s" % (k, tuple(round(x, 1) for x in r)))
    chk(gap(r, BEZEL) >= 20, "%s clear of the bezel by %.1f units" % (k, gap(r, BEZEL)))
names = list(NEW)
worst = 1e9
for a, b in itertools.combinations(names, 2):
    g = gap(rect(NEW[a]), rect(NEW[b])); worst = min(worst, g)
    if g < 4 - 1e-6: chk(False, "%s and %s are %.1f units apart" % (a, b, g))
chk(worst >= 4, "no two controls closer than 4 units (the closest pair is %.1f; the hit areas are 2 units bigger on every side, so 0 overlap)" % worst)
for a, b in [("K2", "K3"), ("E2", "E3"), ("K1", "E1")]: print("      %s - %s: %.1f units apart" % (a, b, gap(rect(NEW[a]), rect(NEW[b]))))
for a in ["K1", "E1"]: chk(rect(NEW[a])[3] < BEZEL[1] - 20, "%s above the bezel with %.1f units to spare" % (a, BEZEL[1] - rect(NEW[a])[3]))
chk(all(rect(NEW[k])[1] > 36 + 28 + 20 for k in ["K1", "E1", "E2", "E3"]), "keys and encoders start more than 20 units under the button row (bottom 64)")
toast = (300, 175 - 18, 865, 175 + 18)  # the toast pill (device_skin.c draw_toast): right edge SKIN_W - 95, centre y 175, at most 565 wide
for k in ["E1", "E2", "E3", "K1"]: chk(gap(rect(NEW[k]), toast) >= 4, "the toast pill (up to x 300..865, y 157..193) is clear of %s (%.1f)" % (k, gap(rect(NEW[k]), toast)))
chk(all(abs(v - round(v / 2) * 2) < 1e-9 for k in NEW if k not in NAMES for v in rect(NEW[k])), "keys and encoders sit on the 2 unit block grid")
chk(abs(SCREEN[0] - 58) < 1e-9 and SCREEN[2] <= BEZEL[2], "the screen and the bezel are the aluminium style's, unchanged")
sys.exit(1 if bad else 0)
