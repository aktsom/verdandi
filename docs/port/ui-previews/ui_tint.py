#!/usr/bin/env python3
"""the mapping of docs/port/ui-settings-plan.md section 2, as a reference implementation (the product code would do the same in C):
for a tint colour and a brightness, the colour of every grey 0..255 of the screen image.
  1. the tint is normalised: its brightest channel becomes 255 (hue and saturation kept). black (000000) is not a tint.
  2. out(channel) = round_half_up(grey * tint(channel) / 255 * brightness); brightness is 0.1 .. 1 in steps of 0.1.
usage: ui_tint.py table      the table of the plan (markdown)
       ui_tint.py edge       the edge cases of custom colours
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


def mapped(grey, tint, brightness):
    return tuple(int(grey * c / 255 * brightness + 0.5) for c in normalise(tint))


def hexs(rgb):
    return "%02X%02X%02X" % rgb


def table():
    cols = [("white", PRESETS["white"]), ("yellow", PRESETS["yellow"]), ("pink", PRESETS["pink"]), ("custom 20C0A0", parse_hex("20C0A0"))]
    out = ["| level | grey |" + "".join(" %s 1 | %s 0.4 |" % (n.split()[0] if n != "custom 20C0A0" else "custom", n.split()[0] if n != "custom 20C0A0" else "custom") for n, _ in cols)]
    out[0] = "| level | grey | " + " | ".join("%s @ 1 | %s @ 0.4" % ((n,) * 2) for n, _ in cols) + " |"
    out.append("|" + "---|" * (2 + 2 * len(cols)))
    for lv in range(16):
        g = level_grey(lv)
        row = ["%d" % lv, "%d" % g]
        for _, rgb in cols:
            row.append(hexs(mapped(g, rgb, 1.0)))
            row.append(hexs(mapped(g, rgb, 0.4)))
        out.append("| " + " | ".join(row) + " |")
    return "\n".join(out)


def edge():
    cases = ["000000", "010000", "202020", "808080", "ffffff", "ff0000", "0000ff", "00000f", "fff", "#FFD000", "12"]
    for c in cases:
        try:
            rgb = parse_hex(c)
            n = normalise(rgb)
            print("%-8s -> tint %s; level 15 at 1: %s, level 4 at 0.4: %s" % (c, hexs(n), hexs(mapped(255, rgb, 1.0)), hexs(mapped(68, rgb, 0.4))))
        except ValueError as e:
            print("%-8s -> rejected: %s" % (c, e))


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "table"
    if cmd == "table":
        print(table())
    elif cmd == "edge":
        edge()
    elif cmd == "hex":
        try:
            print(hexs(parse_hex(sys.argv[2])))
        except ValueError as e:
            print("error:", e)
            sys.exit(1)
