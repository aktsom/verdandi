#!/bin/bash
# docs/port/ui-previews/make_previews.sh: the pictures and numbers of docs/port/ui-plan.md that document the owner's decisions. reproducible: run it from anywhere, it
# writes the files listed in README.md next to itself and everything else into a temporary folder.
#   real norns, headless (Xvfb + jackd dummy, linux/tests/norns_probe.sh) shows a menu page: that gives the real window (the built layout) and the screen image.
#   the skin code (matron/src/platform/macos/device_skin.c, only read) draws the chosen layout and the margin options (the Linux layout table, built with
#   NORNS_LINUX_DESKTOP, with constants changed by a generator script in a copy) and the Mac layout (built without it). nothing in the product is changed.
#   UIPREVIEW_REUSE_CAPTURE=1 reuses oled-edit.png instead of starting norns for it; UIPREVIEW_SKIP_RESIZE=1 keeps the resize-real-*.png that are there.
# needs: Xvfb, xdotool, ImageMagick (convert, compare, identify), a C compiler, cairo's headers, python3, a built norns (linux/build.sh), sclang (the script loads an engine)
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
SKIN="$REPO/matron/src/platform/macos"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
cd "$HERE"
CFLAGS="-std=gnu11 -O1 -Wall -I$SKIN $(pkg-config --cflags cairo)"
LIBS="$(pkg-config --libs cairo) -lm"

echo "== real norns: the PARAMS > EDIT page and the real window (today's layout)"
if [ "${UIPREVIEW_REUSE_CAPTURE:-0}" = 1 ] && [ -s "$HERE/oled-edit.png" ]; then
    echo "   reusing oled-edit.png"
    cp "$HERE/oled-edit.png" "$W/oled.png"
else
    mkdir -p "$W/home/dust/code/uipreview"
    cp "$HERE/uipreview.lua" "$W/home/dust/code/uipreview/"
    ln -s "$REPO" "$W/home/norns"
    NORNS_HOME="$W/home" "$REPO/linux/tests/norns_probe.sh" "$HERE/capture.lua" "$W/home/probe.log" > /dev/null 2>&1 || true
    for f in oled-edit.png xscreen-edit.png window-geometry.txt; do
        [ -s "$W/home/$f" ] || { echo "capture failed: $f missing (see $W/home/probe.log)"; exit 1; }
    done
    eval "$(cat "$W/home/window-geometry.txt")" # X Y WIDTH HEIGHT
    echo "   window $WIDTH x $HEIGHT at $X,$Y"
    convert "$W/home/xscreen-edit.png" -crop "${WIDTH}x${HEIGHT}+${X}+${Y}" +repage "$HERE/layout-current-REAL-window.png"
    cp "$W/home/oled-edit.png" "$W/oled.png"
    cp "$W/home/oled-edit.png" "$HERE/oled-edit.png" # the screen image the pictures are made from (128 x 64)
fi

echo "== grey table (today's, identity; the others are in grey-levels.txt)"
python3 "$HERE/grey_tables.py" "$W" > "$HERE/grey-levels.txt"

echo "== the Mac layout (device_skin.c without NORNS_LINUX_DESKTOP), the reference of the margin comparison"
cc $CFLAGS "$HERE/render_preview.c" "$SKIN/device_skin.c" -o "$W/r_mac" $LIBS
"$W/r_mac" "$W/mac-edit.png" "$W/oled.png" "$W/current.lut" 100

echo "== the chosen layout: arrangement A without labels (ui-plan.md 1.6, 1.7)"
d="$W/ui-a"
mkdir -p "$d"
python3 "$HERE/gen_variant_ui.py" a 0 "$d" > /dev/null
cc -std=gnu11 -O1 -I"$d" -I"$SKIN" $(pkg-config --cflags cairo) -DVARIANT "$HERE/render_preview.c" "$d/device_skin_variant.c" -o "$d/render" $LIBS 2> /dev/null
"$d/render" "$HERE/layout-ui-a-nolabels.png" "$W/oled.png" "$W/current.lut" 100 1
# fidelity of the stand-in: the render of the chosen layout against the real window of the built layout (the same pixels but the screen's anti-aliasing)
echo "   render vs the real window, RMSE: $(compare -metric RMSE "$HERE/layout-ui-a-nolabels.png" "$HERE/layout-current-REAL-window.png" null: 2>&1 || true)"
cp "$d/numbers.txt" "$HERE/ui-numbers-a.txt"
cp "$d/checks.txt" "$HERE/ui-checks-a.txt"
cc -std=gnu11 -I"$d" $(pkg-config --cflags cairo) "$HERE/hit_check.c" "$d/device_skin_variant.c" -o "$W/hit_a" $LIBS
"$W/hit_a" > "$HERE/ui-hit-check-a.txt" && echo "   $(cat "$HERE/ui-hit-check-a.txt")"

echo "== the margin around the screen (ui-plan.md 1.8)"
convert -size 128x64 xc:white "$W/white.png"
"$W/r_mac" "$W/mac-white.png" "$W/white.png" "$W/current.lut" 100
{
    echo "margin around the screen, measured on renders whose screen is all white (device pixels at scale 1 = layout units)"
    echo "mac (the Mac layout, device_skin.c without the define): bezel 417 x 220 units (x 77..494, y 356..576), pad 14, 3 px per screen pixel:"
    echo "   $(python3 "$HERE/measure_margin.py" "$W/mac-white.png" 301.5 482)"
} > "$HERE/ui-margins.txt"
for m in today abs shrink grow; do
    d="$W/m-$m"
    mkdir -p "$d"
    python3 "$HERE/gen_variant_margin.py" "$m" "$d" | sed 's/^/   /' >> "$HERE/ui-margins.txt"
    cc -std=gnu11 -O1 -DNORNS_LINUX_DESKTOP -I"$d" -I"$SKIN" $(pkg-config --cflags cairo) -DVARIANT "$HERE/render_preview.c" "$d/device_skin_variant.c" -o "$d/render" $LIBS
    "$d/render" "$W/margin-$m.png" "$W/oled.png" "$W/current.lut" 100 4
    "$d/render" "$d/white.png" "$W/white.png" "$W/current.lut" 100 4
    read -r cx cy <<< "$(python3 - "$d/variant.h" << 'PY'
import re, sys
v = open(sys.argv[1]).read()
g = lambda n: float(re.search(n + r" ([0-9.]+)", v).group(1))
print(16 + g("V_BEZEL_X") + g("V_BEZEL_W") / 2, 16 + g("V_BEZEL_Y") + g("V_BEZEL_H") / 2)
PY
)"
    echo "      measured: $(python3 "$HERE/measure_margin.py" "$d/white.png" "$cx" "$cy")" >> "$HERE/ui-margins.txt"
done
sed 's/^/   /' "$HERE/ui-margins.txt"
mcap() { convert "$1" -resize 50% -background '#1a1a1c' -gravity north -splice 0x24 -fill white -pointsize 15 -annotate +0+3 "$2" -gravity northwest -extent 496x355 "$3"; }
mcap "$W/mac-edit.png" "Mac layout (reference): margin 4.3 / 7.3 percent" "$W/q-0.png"
mcap "$W/margin-today.png" "Linux today: 2.7 / 5.5 percent" "$W/q-1.png"
mcap "$W/margin-abs.png" "Mac margins in units (545 x 284)" "$W/q-2.png"
mcap "$W/margin-shrink.png" "Mac proportions, bezel kept (screen 3.87 px)" "$W/q-3.png"
mcap "$W/margin-grow.png" "Mac proportions, bezel grown (556 x 293, 4 px)" "$W/q-4.png"
convert \( "$W/q-0.png" "$W/q-1.png" "$W/q-2.png" +append \) \( "$W/q-3.png" "$W/q-4.png" +append \) -append "$HERE/layout-margin-compare.png"

echo "== resizing (ui-plan.md 1.9)"
{
    echo "== Linux layout (device_skin.c with NORNS_LINUX_DESKTOP)"
    cc -std=gnu11 -DNORNS_LINUX_DESKTOP -I"$SKIN" $(pkg-config --cflags cairo) "$HERE/geom_table.c" "$SKIN/device_skin.c" -o "$W/gt_linux" $LIBS && "$W/gt_linux"
    echo
    echo "== Mac layout (device_skin.c without the define)"
    cc -std=gnu11 -I"$SKIN" $(pkg-config --cflags cairo) "$HERE/geom_table.c" "$SKIN/device_skin.c" -o "$W/gt_mac" $LIBS && "$W/gt_mac"
} > "$HERE/ui-resize-numbers.txt"
SIZES="60:595x397 80:794x530 100:992x662 130:1290x861 160:1587x1059"
if [ "${UIPREVIEW_SKIP_RESIZE:-0}" != 1 ]; then
    # the real window of the real norns, resized, on a big virtual screen of its own
    Xvfb :98 -screen 0 2000x1400x24 > /dev/null 2>&1 &
    XV=$!
    sleep 1
    mkdir -p "$W/rhome/dust/code/uipreview"
    cp "$HERE/uipreview.lua" "$W/rhome/dust/code/uipreview/"
    ln -s "$REPO" "$W/rhome/norns"
    DISPLAY=:98 NORNS_HOME="$W/rhome" "$REPO/linux/tests/norns_probe.sh" "$HERE/resize_capture.lua" "$W/rhome/probe.log" > /dev/null 2>&1 || true
    kill $XV 2> /dev/null || true
    for sz in $SIZES; do
        pc="${sz%%:*}"; dim="${sz#*:}"
        [ -s "$W/rhome/xs-$pc.png" ] || { echo "resize capture failed: xs-$pc.png missing"; exit 1; }
        convert "$W/rhome/xs-$pc.png" -crop "${dim}+0+0" +repage "$HERE/resize-real-$pc.png"
    done
fi
# option A (simulated): the box and controls drawn by the real code at the window's size (vector, as today), the screen scaled with the window: nearest at a
# whole number of device pixels per screen pixel, otherwise enlarged by a whole number and scaled down smoothly
for sz in $SIZES; do
    pc="${sz%%:*}"; dim="${sz#*:}"
    "$W/m-today/render" "$W/optionA-$pc.png" "$W/oled.png" "$W/current.lut" 100 3 0 "${dim%x*}" "${dim#*x}"
done
rcap() { convert "$1" -resize 480x -background '#1a1a1c' -gravity north -splice 0x24 -fill white -pointsize 15 -annotate +0+3 "$2" -gravity northwest -extent 480x345 "$3"; }
for pc in 60 80 100 130 160; do
    rcap "$HERE/resize-real-$pc.png" "today, $pc percent" "$W/rr-$pc.png"
    rcap "$W/optionA-$pc.png" "option A, $pc percent" "$W/ra-$pc.png"
done
convert \( "$W/rr-60.png" "$W/rr-80.png" "$W/rr-100.png" "$W/rr-130.png" "$W/rr-160.png" +append \) \
    \( "$W/ra-60.png" "$W/ra-80.png" "$W/ra-100.png" "$W/ra-130.png" "$W/ra-160.png" +append \) -append "$HERE/resize-compare.png"
echo "done: $(ls "$HERE"/*.png | wc -l) PNGs in $HERE"
