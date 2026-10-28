#!/bin/bash
# the pictures of docs/port/ui-settings-plan.md and the UI step 3 build: the REAL window (the built norns, under Xvfb) with ui.conf set to each look, cropped to the
# bezel. needs a built norns (linux/build.sh), Xvfb, xdotool, ImageMagick, python3 with PIL, sclang. writes ui-greys.png, ui-colours.png, ui-brightness.png next to itself.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
shot() { # name probe "ui.conf text"
    local h="$W/$1"
    mkdir -p "$h/dust/code/uipreview"
    cp "$HERE/uipreview.lua" "$HERE/loops_like.lua" "$h/dust/code/uipreview/"
    ln -s "$REPO" "$h/norns"
    printf '%b' "$3" > "$h/ui.conf"
    NORNS_HOME="$h" "$REPO/linux/tests/norns_probe.sh" "$HERE/$2" "$h/probe.log" > /dev/null 2>&1 || true
    [ -s "$h/window.png" ] || { echo "no picture for $1 (see $h/probe.log)"; exit 1; }
    # the window is at 144,69 on the screen (992 x 662); the bezel with a little of the box around it
    convert "$h/window.png" -crop 582x332+$((144 + 40))+$((69 + 296)) +repage "$W/$1.png"
}
for g in 1.0 0.5; do shot "loops-$g" pic_loops.lua "brightness=1.0\ncolour=white\ngreys=$g\n"; done
for c in white yellow pink; do shot "params-$c" pic_params.lua "brightness=1.0\ncolour=$c\ngreys=0.5\n"; done
for b in 1.0 0.7 0.4; do shot "params-b$b" pic_params.lua "brightness=$b\ncolour=white\ngreys=0.5\n"; done
python3 "$HERE/make_ui_settings_previews.py" "$W" "$HERE"
