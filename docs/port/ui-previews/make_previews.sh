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
if [ "${UIPREVIEW_REUSE_CAPTURE:-0}" = 1 ] && [ -s "$HERE/oled-edit.png" ]; then
    # only the layouts and greys again, from the oled image saved by an earlier run (the real-window pictures are kept as they are)
    echo "   reusing oled-edit.png"
    cp "$HERE/oled-edit.png" "$W/oled.png"
    REUSED=1
else
REUSED=0
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
cp "$W/home/oled-edit.png" "$HERE/oled-edit.png" # the screen image the other pictures are made from (128 x 64)
fi

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
# +33 percent: the screen at exactly 4 device pixels per screen pixel; the box and the window grow (gen_variant33.py: mode wide) or not (mode keep)
for m in keep wide; do
    mkdir -p "$W/v33$m"
    python3 "$HERE/gen_variant33.py" "$m" "$W/v33$m" | sed 's/^/   /'
    # the variant's own device_skin.h (SKIN_W) must come first
    cc -std=gnu11 -O1 -Wall -I"$W/v33$m" -I"$SKIN" $(pkg-config --cflags cairo) -DVARIANT "$HERE/render_preview.c" "$W/v33$m/device_skin_variant.c" -o "$W/render_v33$m" $LIBS
    case "$m" in keep) out="$HERE/layout-plus33.png" ;; wide) out="$HERE/layout-plus33-wider-box.png" ;; esac
    "$W/render_v33$m" "$out" "$W/oled.png" "$W/current.lut" 100 1
done
"$W/render_v22" "$HERE/layout-plus22-smooth.png" "$W/oled.png" "$W/current.lut" 100 2

echo "== round 2: the owner's layout (no OUT fader, MUTE in the top row, keys and encoders 15 percent bigger, the screen at 4 px)"
for arr in a b; do
    for lab in 1 0; do
        d="$W/ui$arr$lab"
        mkdir -p "$d"
        python3 "$HERE/gen_variant_ui.py" "$arr" "$lab" "$d" > "$d/out.txt"
        cc -std=gnu11 -O1 -Wall -I"$d" -I"$SKIN" $(pkg-config --cflags cairo) -DVARIANT "$HERE/render_preview.c" "$d/device_skin_variant.c" -o "$d/render" $LIBS
        name=$([ "$lab" = 1 ] && echo labels || echo nolabels)
        "$d/render" "$HERE/layout-ui-$arr-$name.png" "$W/oled.png" "$W/current.lut" 100 1
    done
    cp "$W/ui${arr}1/numbers.txt" "$HERE/ui-numbers-$arr.txt"
    cp "$W/ui${arr}1/checks.txt" "$HERE/ui-checks-$arr.txt"
    cc -std=gnu11 -I"$W/ui${arr}1" -I"$SKIN" $(pkg-config --cflags cairo) "$HERE/hit_check.c" "$W/ui${arr}1/device_skin_variant.c" -o "$W/hit_$arr" $LIBS
    "$W/hit_$arr" > "$HERE/ui-hit-check-$arr.txt" && echo "   arrangement $arr: $(cat "$HERE/ui-hit-check-$arr.txt")"
done
# MUTE on (the LED lights), arrangement a
"$W/uia1/render" "$HERE/layout-ui-a-labels-muted.png" "$W/oled.png" "$W/current.lut" 100 1 1

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
label() { convert "$1" -background '#1a1a1c' -gravity north -splice 0x26 -fill white -pointsize 16 -annotate +0+4 "$2" "$3"; }
label "$W/z-plus22.png" "+22 percent: nearest neighbour (3.66 px per oled pixel)" "$W/zl-1.png"
label "$W/z-plus22-smooth.png" "+22 percent: bilinear" "$W/zl-2.png"
convert "$W/zl-1.png" "$W/zl-2.png" -append "$HERE/zoom-nearest-vs-smooth.png"
# the word LEVELS at 8x in today's layout, +25 (3.75: columns of 4, 4, 4, 3 device pixels) and +33 (4: even)
letters() { convert "$1" -crop "$2" +repage -filter point -resize 800% "$3"; }
letters "$HERE/layout-current-rendered.png" 100x24+104+456 "$W/lt-0.png"
letters "$HERE/layout-plus25.png" 130x28+60+452 "$W/lt-1.png"
letters "$HERE/layout-plus33.png" 130x28+60+442 "$W/lt-2.png"
label "$W/lt-0.png" "today: 3 px per oled pixel (even)" "$W/ltl-0.png"
label "$W/lt-1.png" "+25 percent: 3.75 (columns of 4,4,4,3 px; rows the same)" "$W/ltl-1.png"
label "$W/lt-2.png" "+33 percent: 4 (even)" "$W/ltl-2.png"
convert "$W/ltl-0.png" "$W/ltl-1.png" "$W/ltl-2.png" -background '#1a1a1c' -append "$HERE/zoom-letters-today-25-33.png"
# the contact sheet of the layouts: today's real window and the five layouts, half size
for pct in 20 22 25; do convert "$HERE/layout-plus$pct.png" -resize 50% "$W/s-$pct.png"; done
convert "$HERE/layout-plus33.png" -resize 50% "$W/s-33.png"
convert "$HERE/layout-plus33-wider-box.png" -resize 50% "$W/s-33w.png"
convert "$HERE/layout-current-REAL-window.png" -resize 50% "$W/s-0.png"
tile() { convert "$1" -background '#1a1a1c' -gravity northwest -extent 509x331 "$2"; }
for k in 0 20 22 25 33 33w; do tile "$W/s-$k.png" "$W/t-$k.png"; done
convert \( "$W/t-0.png" "$W/t-20.png" "$W/t-22.png" +append \) \( "$W/t-25.png" "$W/t-33.png" "$W/t-33w.png" +append \) -append "$HERE/layout-compare.png"
# the compare sheet of round 2: today's real window against the new layouts, half size, captioned
cap() { convert "$1" -resize 50% -background '#1a1a1c' -gravity north -splice 0x24 -fill white -pointsize 15 -annotate +0+3 "$2" -gravity northwest -extent 496x355 "$3"; }
cap "$HERE/layout-current-REAL-window.png" "today (real window)" "$W/u-0.png"
cap "$HERE/layout-ui-a-labels.png" "A with labels" "$W/u-1.png"
cap "$HERE/layout-ui-a-nolabels.png" "A without labels" "$W/u-2.png"
cap "$HERE/layout-ui-b-labels.png" "B (alternative) with labels" "$W/u-3.png"
cap "$HERE/layout-ui-b-nolabels.png" "B without labels" "$W/u-4.png"
cap "$HERE/layout-ui-a-labels-muted.png" "A, MUTE on" "$W/u-5.png"
convert \( "$W/u-0.png" "$W/u-1.png" "$W/u-2.png" +append \) \( "$W/u-3.png" "$W/u-4.png" "$W/u-5.png" +append \) -append "$HERE/layout-compare-ui.png"
echo "done: $(ls "$HERE"/*.png | wc -l) PNGs in $HERE"
