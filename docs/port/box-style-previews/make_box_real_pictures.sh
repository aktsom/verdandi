#!/bin/bash
# the pictures of docs/port/box-style-plan.md after the build: CAPTURES OF THE REAL WINDOW of the real norns (headless: Xvfb, dummy jackd) with the real SYSTEM > BOX page, the real pixel style and the
# real aluminium style. no stand-in. usage: make_box_real_pictures.sh OUT_DIR   (needs a built norns, xdotool, ImageMagick, python3 with PIL; run from anywhere)
set -u
REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
OUT="${1:-$(dirname "$0")}"
T="$(mktemp -d)"
trap 'rm -rf "${T:?}"' EXIT
shot() { # name, box.conf text, probe lines (after the page is open)
    local name="$1" conf="$2" lines="$3" H="$T/$1"
    mkdir -p "$H/dust/code/probe"
    ln -s "$REPO" "$H/norns"
    cp "$REPO/linux/tests/scripts/window_probe.lua" "$H/dust/code/probe/"
    printf '%b' "$conf" > "$H/box.conf"
    {
        echo "#sleep 5"
        echo 'norns.script.load("code/probe/window_probe.lua")'
        echo "#sleep 3"
        printf '%b' "$lines"
        echo "#sleep 1.5"
        echo "#shot @home/full.png"
        echo "#xdo key ctrl+q"
        echo "#sleep 3"
    } > "$H/probe.lua"
    NORNS_HOME="$H" "$REPO/linux/tests/norns_probe.sh" "$H/probe.lua" "$H/out.log" > /dev/null 2>&1
    convert "$H/full.png" -crop 992x662+144+69 +repage "$T/$name.png"
}
OPEN='_menu.set_mode(true)\n_menu.set_page("BOX")\n#sleep 1\npage = require "core/menu/box"\nbox = require "core/box_settings"\n'
DARK='style=pixel\npreset=DARK\nbox=2C2E33\nkeys=444853\nencoders=5D6270\nbuttons=3A3D45\nfont=E4E6EA\nshow_buttons=1\n'
LIGHT='style=pixel\npreset=LIGHT\nbox=D8D5CE\nkeys=F4F2ED\nencoders=B9B5AB\nbuttons=EBE8E1\nfont=34343A\nshow_buttons=1\n'
COLOUR='style=pixel\npreset=COLOUR\nbox=2B6F73\nkeys=F2B63D\nencoders=E9DFC8\nbuttons=1D4A4D\nfont=F7F0DE\nshow_buttons=1\n'
# 1. the aluminium window as it is by default, the BOX page on its screen
shot alu "" "$OPEN"'page.enc(2, 0)\n_menu.redraw()\n'
# 2. the pixel style, DARK, PRESET selected
shot dark "$DARK" "$OPEN"'page.enc(2, 1)\n_menu.redraw()\n'
# 3. LIGHT: the PRESET list with his own looks and the star
shot light "$LIGHT" "$OPEN"'box.select_look("COLOUR")\nbox.save_look("Barn door")\nbox.save_look("Sunday")\nbox.save_look("Pale mint")\nbox.select_look("LIGHT")\npage.init()\npage.enc(2, 1)\npage.key(3, 1)\npage.key(3, 0)\n_menu.redraw()\n'
# 4. COLOUR: the end of the page: SAVE and DELETE for one of his own looks in use
shot colour "$COLOUR" "$OPEN"'box.save_look("Barn door")\npage.init()\npage.enc(2, 20)\npage.enc(2, -1)\n_menu.redraw()\n'
python3 - "$T" "$OUT" << 'PY'
import sys
from PIL import Image, ImageDraw, ImageFont
t, out = sys.argv[1], sys.argv[2]
f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 22)
def sheet(a, b, la, lb, path):
    ia, ib = Image.open("%s/%s.png" % (t, a)).convert("RGB"), Image.open("%s/%s.png" % (t, b)).convert("RGB")
    s = Image.new("RGB", (ia.width + ib.width + 30, ia.height + 56), (24, 24, 26))
    s.paste(ia, (10, 10)); s.paste(ib, (ia.width + 20, 10))
    d = ImageDraw.Draw(s); d.text((12, ia.height + 20), la, font=f, fill=(235, 235, 235)); d.text((ia.width + 22, ia.height + 20), lb, font=f, fill=(235, 235, 235))
    s.save(path)
sheet("alu", "dark", "aluminium (the default)", "pixel, DARK", out + "/box-style-dark-vs-aluminium.png")
sheet("light", "colour", "pixel, LIGHT: the PRESET list", "pixel, COLOUR: SAVE and DELETE", out + "/box-style-light-and-colour.png")
PY
echo "ok: $OUT"
