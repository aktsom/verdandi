#!/bin/bash
# docs/port/ui-previews/make_previews.sh: the previews of docs/port/ui-plan.md. reproducible: run it from anywhere, it writes the PNGs next to itself.
#   real norns, headless (Xvfb + jackd dummy, linux/tests/norns_probe.sh) shows a menu page: that gives the real window (the current layout) and the
#   oled image. the skin code (matron/src/platform/macos/device_skin.c, only read) draws the layouts: the current one as it is, the others from a
#   copy with changed constants (gen_variant.py). nothing in the product is changed. the grey tables and the brightness are applied to the oled
#   image before it is drawn (grey_tables.py).
# needs: Xvfb, xdotool, ImageMagick (convert, compare), a C compiler, cairo's headers, python3, a built norns (linux/build.sh), sclang (the script loads an engine)
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
SKIN="$REPO/matron/src/platform/macos"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
cd "$HERE"

echo "== real norns: the PARAMS pages and the real window"
mkdir -p "$W/home/dust/code/uipreview"
cp "$HERE/uipreview.lua" "$W/home/dust/code/uipreview/"
ln -s "$REPO" "$W/home/norns"
NORNS_HOME="$W/home" "$REPO/linux/tests/norns_probe.sh" "$HERE/capture.lua" "$W/home/probe.log" > /dev/null 2>&1 || true
for f in oled-params.png oled-edit.png xscreen-params.png xscreen-edit.png window-geometry.txt; do
    [ -s "$W/home/$f" ] || { echo "capture failed: $f missing (see $W/home/probe.log)"; cp "$W/home/probe.log" "$HERE/capture-failed.log" 2> /dev/null; exit 1; }
done
eval "$(cat "$W/home/window-geometry.txt")" # X Y WIDTH HEIGHT
echo "   window $WIDTH x $HEIGHT at $X,$Y"
convert "$W/home/xscreen-edit.png" -crop "${WIDTH}x${HEIGHT}+${X}+${Y}" +repage "$HERE/layout-current-REAL-window.png"
convert "$W/home/xscreen-params.png" -crop "${WIDTH}x${HEIGHT}+${X}+${Y}" +repage "$HERE/layout-current-REAL-window-params-page.png"
cp "$W/home/oled-edit.png" "$W/oled.png"

echo "== grey tables"
python3 "$HERE/grey_tables.py" "$W" > "$HERE/grey-levels.txt"
cat "$HERE/grey-levels.txt" | head -3

echo "== layouts drawn by the skin code"
CFLAGS="-std=gnu11 -O1 -Wall -I$SKIN $(pkg-config --cflags cairo)"
LIBS="$(pkg-config --libs cairo) -lm"
# the current layout: the product's device_skin.c as it is
cc $CFLAGS "$HERE/render_preview.c" "$SKIN/device_skin.c" -o "$W/render_current" $LIBS
"$W/render_current" "$HERE/layout-current-rendered.png" "$W/oled.png" "$W/current.lut" 100
# fidelity: the rendered current layout against the real window (the same pixels except the oled's anti-aliasing and the lit LEDs)
echo "   rendered vs real window, RMSE: $(compare -metric RMSE "$HERE/layout-current-rendered.png" "$HERE/layout-current-REAL-window.png" null: 2>&1 || true)"
for pct in 20 22 25; do
    mkdir -p "$W/v$pct"
    python3 "$HERE/gen_variant.py" "1.$pct" "$W/v$pct" | sed 's/^/   /'
    cc $CFLAGS -DVARIANT -I"$W/v$pct" "$HERE/render_preview.c" "$W/v$pct/device_skin_variant.c" -o "$W/render_v$pct" $LIBS
    "$W/render_v$pct" "$HERE/layout-plus$pct.png" "$W/oled.png" "$W/current.lut" 100 1
done
"$W/render_v22" "$HERE/layout-plus22-smooth.png" "$W/oled.png" "$W/current.lut" 100 2

echo "== greys (current layout)"
for t in current gamma07 gamma05; do
    "$W/render_current" "$HERE/grey-$t.png" "$W/oled.png" "$W/$t.lut" 100
done
echo "== brightness (layout +22, grey table gamma07)"
for b in 100 70 40; do
    "$W/render_v22" "$HERE/brightness-$b.png" "$W/oled.png" "$W/gamma07.lut" "$b" 1
done

echo "== contact sheets"
# labelled strips: the screen alone (bezel included), side by side
strip() { # OUT LABEL1 FILE1 LABEL2 FILE2 ... CROP
    local out="$1" crop="$2"
    shift 2
    local parts=()
    while [ $# -gt 0 ]; do
        convert "$2" -crop "$crop" +repage -background '#1a1a1c' -gravity north -splice 0x26 -fill white -pointsize 16 -annotate +0+4 "$1" "$W/strip-$#.png"
        parts+=("$W/strip-$#.png")
        shift 2
    done
    convert "${parts[@]}" -background '#1a1a1c' -splice 8x0 +append "$out"
}
strip "$HERE/grey-compare.png" 424x228+88+366 \
    "current greys (level 4 = 68)" "$HERE/grey-current.png" "gamma 0.7 (level 4 = 101)" "$HERE/grey-gamma07.png" "gamma 0.5 (level 4 = 132)" "$HERE/grey-gamma05.png"
strip "$HERE/brightness-compare.png" 504x264+34+336 \
    "brightness 100 %" "$HERE/brightness-100.png" "brightness 70 %" "$HERE/brightness-70.png" "brightness 40 %" "$HERE/brightness-40.png"
# a part of the text of the +22 layout, zoomed 4x: nearest neighbour (crisp, some pixels one device pixel wider) against bilinear (even, softer)
for k in plus22 plus22-smooth; do convert "$HERE/layout-$k.png" -crop 180x70+60+425 +repage -filter point -resize 400% "$W/z-$k.png"; done
convert \( "$W/z-plus22.png" -background '#1a1a1c' -gravity north -splice 0x26 -fill white -pointsize 16 -annotate +0+4 "+22 percent: nearest neighbour (3.66 px per oled pixel)" \) \
    \( "$W/z-plus22-smooth.png" -background '#1a1a1c' -gravity north -splice 0x26 -fill white -pointsize 16 -annotate +0+4 "+22 percent: bilinear" \) -splice 0x0 -append "$HERE/zoom-nearest-vs-smooth.png"
for pct in 20 22 25; do convert "$HERE/layout-plus$pct.png" -resize 50% "$W/s-$pct.png"; done
convert "$HERE/layout-current-REAL-window.png" -resize 50% "$W/s-0.png"
convert \( "$W/s-0.png" "$W/s-20.png" +append \) \( "$W/s-22.png" "$W/s-25.png" +append \) -append "$HERE/layout-compare.png"
echo "done: $(ls "$HERE"/*.png | wc -l) PNGs in $HERE"
