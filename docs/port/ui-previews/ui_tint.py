#!/usr/bin/env python3
"""the mapping of docs/port/ui-settings-plan.md section 2, as a reference implementation (the product code would do the same in C):
for a grey correction (gamma), a tint colour and a brightness, the colour of every grey 0..255 of the screen image.
  1. grey correction: g' = 255 * (g / 255) ** gamma (gamma 1.0 = linear, as the desktop was; default 0.5; 0 and 255 stay).
  2. the tint is normalised: its brightest channel becomes 255 (hue and saturation kept). black (000000) is not a tint.
  3. out(channel) = round_half_up(g' * tint(channel) / 255 * f(brightness)); brightness is 0.1 .. 1 in steps of 0.1 and f is a gentler curve at the low
     end: f(b) = b ** 0.6 (0.1 -> 0.251, 0.2 -> 0.381, 0.3 -> 0.486, 0.4 -> 0.577, 0.5 -> 0.660, 0.7 -> 0.807, 1 -> 1). one rounding, at the end.
usage: ui_tint.py table      the table of the plan (markdown)
       ui_tint.py greys      the 16 levels after the grey correction (gamma 1.0, 0.7, 0.5) and the device's own table (see the plan, section 2.1)
       ui_tint.py edge       the edge cases of custom colours
       ui_tint.py dump       every grey 0..255 for gamma 0.4..1.0, brightness 0.1..1 and five tints, one line each (the C test compares against it)
       ui_tint.py hex TEXT   parse a hex code the way the plan says (prints the colour or the error)"""
import re
import sys

PRESETS = {"white": (255, 255, 255), "yellow": (255, 208, 0), "pink": (255, 128, 184)}


def parse_hex(text):
    """3 or 6 hex digits, with or without a leading #, upper or lower case, surrounding blanks ignored. returns (r, g, b) or raises ValueError"""
    t = text.strip()
    if t.startswith("#"):
        t = t[1:]
    if not re.fullmatch(r"[0-9a-fA-F]{3}|[0-9a-fA-F]{6}", t):
        raise ValueError("a hex colour has 3 or 6 digits (0-9, a-f)")
    if len(t) == 3:
        t = "".join(c * 2 for c in t)
    rgb = tuple(int(t[i:i + 2], 16) for i in (0, 2, 4))
    if max(rgb) == 0:
        raise ValueError("black would hide the screen")
    return rgb


def normalise(rgb):
    m = max(rgb)
    return tuple(int(c * 255 / m + 0.5) for c in rgb)


def level_grey(level):
    return level * 17


DEFAULT_GAMMA = 0.5
BRIGHTNESS_EXPONENT = 0.6


def factor(brightness):
    return brightness ** BRIGHTNESS_EXPONENT


def corrected(grey, gamma=DEFAULT_GAMMA):
    return 255.0 * (grey / 255.0) ** gamma


def mapped(grey, tint, brightness, gamma=DEFAULT_GAMMA):
    g = corrected(grey, gamma)
    return tuple(int(g * c / 255 * factor(brightness) + 0.5) for c in normalise(tint))


def device_like(level):
    """what the real panel shows at pixel value 1..15 if its light output follows the grey scale table that ssd1322.cc writes for gamma 1.0
    (GS value = 8 * (level - 1), linear in light) and a monitor with gamma 2.2 shows it: the code value that gives the same light. level 0 and 1 are dark."""
    if level <= 1:
        return 0
    return int(255 * ((level - 1) / 14.0) ** (1 / 2.2) + 0.5)


def greys():
    out = ["| level | today (gamma 1.0) | gamma 0.7 | gamma 0.5 (default) | device-like (estimate) |", "|---|---|---|---|---|"]
    for lv in range(16):
        g = lv * 17
        out.append("| %d | %d (%d%%) | %d (%d%%) | %d (%d%%) | %d (%d%%) |" % ((lv, g, round(g / 2.55)) + tuple(
            v for gm in (0.7, 0.5) for v in (int(corrected(g, gm) + 0.5), round(corrected(g, gm) / 2.55))) + (device_like(lv), round(device_like(lv) / 2.55))))
    return "\n".join(out)


def hexs(rgb):
    return "%02X%02X%02X" % rgb


def table(gamma=DEFAULT_GAMMA):
    cols = [("white", PRESETS["white"]), ("yellow", PRESETS["yellow"]), ("pink", PRESETS["pink"]), ("custom 20C0A0", parse_hex("20C0A0"))]
    out = ["| level | grey |" + "".join(" %s 1 | %s 0.4 |" % (n.split()[0] if n != "custom 20C0A0" else "custom", n.split()[0] if n != "custom 20C0A0" else "custom") for n, _ in cols)]
    out[0] = "| level | grey | " + " | ".join("%s @ 1 | %s @ 0.4" % ((n,) * 2) for n, _ in cols) + " |"
    out.append("|" + "---|" * (2 + 2 * len(cols)))
    for lv in range(16):
        g = level_grey(lv)
        row = ["%d" % lv, "%d" % g]
        for _, rgb in cols:
            row.append(hexs(mapped(g, rgb, 1.0, gamma)))
            row.append(hexs(mapped(g, rgb, 0.4, gamma)))
        out.append("| " + " | ".join(row) + " |")
    return "\n".join(out)


def edge():
    cases = ["000000", "010000", "202020", "808080", "ffffff", "ff0000", "0000ff", "00000f", "fff", "#FFD000", "12"]
    for c in cases:
        try:
            rgb = parse_hex(c)
            n = normalise(rgb)
            print("%-8s -> tint %s; level 15 at 1: %s, level 4 at 0.4 (gamma 0.5): %s" % (c, hexs(n), hexs(mapped(255, rgb, 1.0)), hexs(mapped(68, rgb, 0.4))))
        except ValueError as e:
            print("%-8s -> rejected: %s" % (c, e))


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "table"
    if cmd == "table":
        print(table())
    elif cmd == "dump":
        for gi in range(4, 11):
            for bi in range(1, 11):
                for tint in ("FFFFFF", "FFD000", "FF80B8", "20C0A0", "202020"):
                    for g in range(256):
                        r, gg, b = mapped(g, parse_hex(tint), bi / 10.0, gi / 10.0)
                        print(gi / 10.0, bi / 10.0, tint, g, r, gg, b)
    elif cmd == "greys":
        print(greys())
    elif cmd == "edge":
        edge()
    elif cmd == "hex":
        try:
            print(hexs(parse_hex(sys.argv[2])))
        except ValueError as e:
            print("error:", e)
            sys.exit(1)
