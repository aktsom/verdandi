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
echo "== round 2b: the margin around the screen (ui-plan.md 1.8)"
convert -size 128x64 xc:white "$W/white.png"
cc $CFLAGS "$HERE/render_preview.c" "$SKIN/device_skin.c" -o "$W/r_mac" $LIBS
# the Mac layout: device_skin.c without NORNS_LINUX_DESKTOP, exactly what the Mac app compiles
"$W/r_mac" "$HERE/layout-margin-mac-reference.png" "$W/oled.png" "$W/current.lut" 100
"$W/r_mac" "$W/mac-white.png" "$W/white.png" "$W/current.lut" 100
{
    echo "margin around the screen, measured on renders whose screen is all white (device pixels at scale 1 = layout units)"
    echo "mac (the Mac layout, device_skin.c without the define): bezel 417 x 220 units (x 77..494, y 356..576), pad 14, 3 px per screen pixel:"
    echo "   $(python3 "$HERE/measure_margin.py" "$W/mac-white.png" 301.5 482)"
} > "$HERE/ui-margins.txt"
for m in today abs shrink grow; do
    d="$W/m-$m"
    mkdir -p "$d"
    python3 "$HERE/gen_variant_margin.py" "$m" "$d" | sed 's/^/   /' | tee -a "$HERE/ui-margins.txt" > /dev/null
    cc -std=gnu11 -O1 -DNORNS_LINUX_DESKTOP -I"$d" -I"$SKIN" $(pkg-config --cflags cairo) -DVARIANT "$HERE/render_preview.c" "$d/device_skin_variant.c" -o "$d/render" $LIBS
    "$d/render" "$HERE/layout-margin-$m.png" "$W/oled.png" "$W/current.lut" 100 4
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
cat "$HERE/ui-margins.txt" | sed 's/^/   /'
# the top-left corner of each bezel, 3x: the margin and the first line of text
corner() { # IMAGE X Y LABEL OUT   (X Y: the bezel's top-left corner in units; 16 is the window's margin)
    convert "$1" -crop 230x110+$(( $2 + 16 - 8 ))+$(( $3 + 16 - 8 )) +repage -filter point -resize 300% -background '#1a1a1c' -gravity north -splice 0x26 \
        -fill white -pointsize 16 -annotate +0+4 "$4" "$5"
}
corner "$HERE/layout-margin-mac-reference.png" 77 356 "Mac layout (reference)" "$W/k-0.png"
corner "$HERE/layout-margin-today.png" 36 310 "Linux today" "$W/k-1.png"
corner "$HERE/layout-margin-abs.png" 36 310 "Mac margins in units" "$W/k-2.png"
corner "$HERE/layout-margin-shrink.png" 36 310 "Mac proportions, bezel kept" "$W/k-3.png"
corner "$HERE/layout-margin-grow.png" 36 301 "Mac proportions, bezel grown" "$W/k-4.png"
convert "$W/k-0.png" "$W/k-1.png" "$W/k-2.png" +append "$W/kr1.png"
convert "$W/k-3.png" "$W/k-4.png" +append -background '#1a1a1c' -extent $(identify -format %w "$W/kr1.png")x "$W/kr2.png"
convert "$W/kr1.png" "$W/kr2.png" -background '#1a1a1c' -append "$HERE/margin-corner-compare.png"
mcap() { convert "$1" -resize 50% -background '#1a1a1c' -gravity north -splice 0x24 -fill white -pointsize 15 -annotate +0+3 "$2" -gravity northwest -extent 496x355 "$3"; }
mcap "$HERE/layout-margin-mac-reference.png" "Mac layout (reference): margin 4.3 % / 7.3 %" "$W/q-0.png"
mcap "$HERE/layout-margin-today.png" "Linux today: 2.7 % / 5.5 %" "$W/q-1.png"
mcap "$HERE/layout-margin-abs.png" "Mac margins in units (545 x 284)" "$W/q-2.png"
mcap "$HERE/layout-margin-shrink.png" "Mac proportions, bezel kept (screen 3.87 px)" "$W/q-3.png"
mcap "$HERE/layout-margin-grow.png" "Mac proportions, bezel grown (556 x 293, 4 px)" "$W/q-4.png"
convert \( "$W/q-0.png" "$W/q-1.png" "$W/q-2.png" +append \) \( "$W/q-3.png" "$W/q-4.png" +append \) -append "$HERE/layout-margin-compare.png"

echo "== round 2b: resizing (ui-plan.md 1.9)"
{
    echo "== Linux layout (device_skin.c with NORNS_LINUX_DESKTOP)"
    cc -std=gnu11 -DNORNS_LINUX_DESKTOP -I"$SKIN" $(pkg-config --cflags cairo) "$HERE/geom_table.c" "$SKIN/device_skin.c" -o "$W/gt_linux" $LIBS && "$W/gt_linux"
    echo
    echo "== Mac layout (device_skin.c without the define)"
    cc -std=gnu11 -I"$SKIN" $(pkg-config --cflags cairo) "$HERE/geom_table.c" "$SKIN/device_skin.c" -o "$W/gt_mac" $LIBS && "$W/gt_mac"
} > "$HERE/ui-resize-numbers.txt"
if [ "${UIPREVIEW_SKIP_RESIZE:-0}" != 1 ]; then
    # the real window of the real norns, resized: a big virtual screen of its own
    Xvfb :98 -screen 0 2000x1400x24 > /dev/null 2>&1 &
    XV=$!
    sleep 1
    mkdir -p "$W/rhome/dust/code/uipreview"
    cp "$HERE/uipreview.lua" "$W/rhome/dust/code/uipreview/"
    ln -s "$REPO" "$W/rhome/norns"
    DISPLAY=:98 NORNS_HOME="$W/rhome" "$REPO/linux/tests/norns_probe.sh" "$HERE/resize_capture.lua" "$W/rhome/probe.log" > /dev/null 2>&1 || true
    kill $XV 2> /dev/null || true
    for sz in 60:595x397 75:744x496 80:794x530 100:992x662 125:1240x828 130:1290x861 150:1488x993 160:1587x1059; do
        pc="${sz%%:*}"; dim="${sz#*:}"
        [ -s "$W/rhome/xs-$pc.png" ] || { echo "resize capture failed: xs-$pc.png missing"; exit 1; }
        convert "$W/rhome/xs-$pc.png" -crop "${dim}+0+0" +repage "$HERE/resize-real-$pc.png"
    done
fi
# option A (simulated): the box and controls drawn by the real code at the window's size (vector, as today), the screen scaled with the window: nearest at a whole
# number of device pixels per screen pixel, otherwise enlarged by a whole number and scaled down smoothly
for sz in 60:595x397 75:744x496 80:794x530 100:992x662 125:1240x828 130:1290x861 150:1488x993 160:1587x1059; do
    pc="${sz%%:*}"; dim="${sz#*:}"
    "$W/m-today/render" "$HERE/resize-optionA-$pc.png" "$W/oled.png" "$W/current.lut" 100 3 0 "${dim%x*}" "${dim#*x}"
done
rcap() { convert "$1" -resize 480x -background '#1a1a1c' -gravity north -splice 0x24 -fill white -pointsize 15 -annotate +0+3 "$2" -gravity northwest -extent 480x345 "$3"; }
for pc in 60 80 100 130 160; do
    rcap "$HERE/resize-real-$pc.png" "today, $pc %" "$W/rr-$pc.png"
    rcap "$HERE/resize-optionA-$pc.png" "option A, $pc %" "$W/ra-$pc.png"
done
convert \( "$W/rr-60.png" "$W/rr-80.png" "$W/rr-100.png" "$W/rr-130.png" "$W/rr-160.png" +append \) \
    \( "$W/ra-60.png" "$W/ra-80.png" "$W/ra-100.png" "$W/ra-130.png" "$W/ra-160.png" +append \) -append "$HERE/resize-compare.png"
# the screen at 80 percent (3.2 px per screen pixel): today's whole 3 px against option A, 4x zoom of the text
zoom() { convert "$1" -crop "$2" +repage -filter point -resize 400% -background '#1a1a1c' -gravity north -splice 0x26 -fill white -pointsize 16 -annotate +0+4 "$3" "$4"; }
zoom "$HERE/resize-real-80.png" 190x50+40+276 "today, 80 percent: 3 px per screen pixel (ideal 3.2)" "$W/zr.png"
zoom "$HERE/resize-optionA-80.png" 190x50+40+276 "option A, 80 percent: 3.2 px, enlarged 4x then scaled down" "$W/za.png"
convert "$W/zr.png" "$W/za.png" -append "$HERE/resize-zoom-80.png"
echo "done: $(ls "$HERE"/*.png | wc -l) PNGs in $HERE"
