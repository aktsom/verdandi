#!/bin/bash
# the C side of the box styles (docs/port/box-style-plan.md): the palette (box_palette_test.c), the pixel style, the hidden row and the aluminium tint (box_style_test.c, with the screen's norns.ttf and with
# the built-in font), and the aluminium style with its DEFAULT colours: the same bytes as the code before the box styles existed (box_render_dump.c against box_aluminium_golden.txt, made from the
# committed device_skin.c of the step before: 6 states at 4 window sizes), and the Mac build: device_skin.c without NORNS_LINUX_DESKTOP compiles, passes macos/tests/device_skin_test.c, and gives the
# Mac layout (the file's Linux additions are all inside #ifdef NORNS_LINUX_DESKTOP, checked here)
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO" || exit 1
T="$(mktemp -d)"
trap 'rm -rf "${T:?}"' EXIT
FAIL=0
ok() { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; FAIL=1; }
CF="$(pkg-config --cflags cairo freetype2)"; LF="$(pkg-config --libs cairo freetype2)"
SK=matron/src/platform/macos; LN=matron/src/platform/linux

cc -std=gnu11 -Wall -Wextra -I $LN linux/tests/box_palette_test.c $LN/box_palette.c -o "$T/bpt" -lm 2> "$T/cc.log" || { bad "box_palette_test does not build"; cat "$T/cc.log"; }
[ -x "$T/bpt" ] && { "$T/bpt" > "$T/bpt.out" 2>&1 && ok "palette: $(tail -n 1 "$T/bpt.out")" || { bad "palette test"; cat "$T/bpt.out"; }; }

cc -std=gnu11 -Wall -Wextra -DNORNS_LINUX_DESKTOP -I $SK -I $LN $CF linux/tests/box_style_test.c $SK/device_skin.c $LN/box_style.c $LN/box_palette.c -o "$T/bst" $LF -lm 2> "$T/cc.log" || { bad "box_style_test does not build"; cat "$T/cc.log"; }
if [ -x "$T/bst" ]; then
    NORNS_TEST_TTF="$REPO/resources/norns.ttf" "$T/bst" > "$T/bst.out" 2>&1 && ok "pixel style, hidden row, fonts, sizes: $(tail -n 1 "$T/bst.out")" || { bad "box_style_test"; cat "$T/bst.out"; }
fi

# the aluminium style with its default colours: byte for byte
cc -std=gnu11 -O1 -DNORNS_LINUX_DESKTOP -I $SK -I $LN $CF linux/tests/box_render_dump.c $SK/device_skin.c $LN/box_style.c $LN/box_palette.c -o "$T/dump" $LF -lm 2> "$T/cc.log" || { bad "box_render_dump does not build"; cat "$T/cc.log"; }
if [ -x "$T/dump" ]; then
    mkdir -p "$T/new"
    "$T/dump" "$T/new"
    n=$(wc -l < linux/tests/box_aluminium_golden.txt)
    if (cd "$T/new" && sha256sum -c --quiet "$REPO/linux/tests/box_aluminium_golden.txt" > "$T/sha.out" 2>&1); then ok "aluminium, default colours: all $n renders are byte for byte the old ones"; else bad "aluminium renders differ from the golden hashes"; head -5 "$T/sha.out"; fi
fi

# PIXEL stays exactly as it is (docs/port/retro-look-plan.md): the same 24 renders (6 states at 4 window sizes, the DARK look) as the code before the retro looks, with the pixel look set to 0 and not set, and the
# same hit map; then the retro looks: sizes, layout, hit areas, outlines, decorations, determinism, the four built-in looks, the caches (box_retro_test.c)
cc -std=gnu11 -O1 -DNORNS_LINUX_DESKTOP -DHAVE_LOOK -DHAVE_VARIANT -I $SK -I $LN $CF linux/tests/box_render_dump.c $SK/device_skin.c $LN/box_style.c $LN/box_palette.c -o "$T/dumpp" $LF -lm 2> "$T/cc.log" || { bad "box_render_dump (pixel) does not build"; cat "$T/cc.log"; }
if [ -x "$T/dumpp" ]; then
    for vv in unset 0; do
        mkdir -p "$T/pix-$vv"
        if [ $vv = unset ]; then DUMP_PIXEL=1 "$T/dumpp" "$T/pix-$vv"; else DUMP_PIXEL=1 DUMP_VARIANT=0 "$T/dumpp" "$T/pix-$vv"; fi
        n=$(wc -l < linux/tests/box_pixel_golden.txt)
        if (cd "$T/pix-$vv" && sha256sum -c --quiet "$REPO/linux/tests/box_pixel_golden.txt" > "$T/sha.out" 2>&1); then ok "PIXEL (pixel look $vv): all $n renders are byte for byte the ones of the code before the retro looks"; else bad "PIXEL renders differ from the golden hashes ($vv)"; head -5 "$T/sha.out"; fi
    done
fi
cc -std=gnu11 -O1 -DNORNS_LINUX_DESKTOP -DHAVE_VARIANT -I $SK -I $LN $CF linux/tests/box_hit_dump.c $SK/device_skin.c $LN/box_style.c $LN/box_palette.c -o "$T/hitd" $LF -lm 2> "$T/cc.log" || { bad "box_hit_dump does not build"; cat "$T/cc.log"; }
if [ -x "$T/hitd" ]; then
    for vv in "" 0; do
        got=$("$T/hitd" $vv | sha256sum | cut -d' ' -f1)
        [ "$got" = "$(cat linux/tests/box_pixel_hits_golden.txt)" ] && ok "PIXEL hit areas are unchanged (a point every 4 units, row shown and hidden; look ${vv:-unset})" || bad "PIXEL hit areas changed"
    done
    [ "$("$T/hitd" 1 | sha256sum | cut -d' ' -f1)" != "$(cat linux/tests/box_pixel_hits_golden.txt)" ] && ok "RETRO's hit areas are its own (snapped to its block grid)" || bad "RETRO's hit map is PIXEL's"
fi
cc -std=gnu11 -Wall -Wextra -DNORNS_LINUX_DESKTOP -I $SK -I $LN $CF linux/tests/box_retro_test.c $SK/device_skin.c $LN/box_style.c $LN/box_palette.c -o "$T/brt" $LF -lm 2> "$T/cc.log" || { bad "box_retro_test does not build"; cat "$T/cc.log"; }
if [ -x "$T/brt" ]; then
    "$T/brt" > "$T/brt.out" 2>&1 && ok "retro looks: $(tail -n 1 "$T/brt.out")" || { bad "box_retro_test"; head -20 "$T/brt.out"; }
fi

# the Mac build and the Mac layout
cc -std=gnu11 -Wall -Wextra -I $SK $CF -c $SK/device_skin.c -o "$T/mac.o" 2> "$T/cc.log" && ok "device_skin.c compiles without NORNS_LINUX_DESKTOP (the Mac build)" || { bad "Mac build of device_skin.c"; cat "$T/cc.log"; }
cc -std=gnu11 -Wall -Wextra -I $SK $CF macos/tests/device_skin_test.c $SK/device_skin.c $SK/vgrid_skin.c $SK/varc_skin.c $SK/vkeys_skin.c -o "$T/mac_ds" $LF -lm 2> "$T/cc.log" || { bad "the Mac skin test does not build"; head -5 "$T/cc.log"; }
[ -x "$T/mac_ds" ] && { "$T/mac_ds" > "$T/mac.out" 2>&1 && ok "the Mac skin test (macos/tests/device_skin_test.c) passes on the shared file: $(tail -n 1 "$T/mac.out")" || { bad "the Mac skin test fails"; tail -5 "$T/mac.out"; }; }
# every Linux-only line of the shared file is inside an #ifdef NORNS_LINUX_DESKTOP (or its #else branch): the lines the box styles added
git diff --quiet HEAD -- matron/src/platform/macos 2> /dev/null
python3 - "$REPO" << 'PY' && ok "the Linux additions to device_skin.c/.h are all inside NORNS_LINUX_DESKTOP blocks (or are the stopt() calls, which are the old calls on the Mac)" || bad "an addition to a shared file is outside NORNS_LINUX_DESKTOP"
import re, sys
for f in ("matron/src/platform/macos/device_skin.c", "matron/src/platform/macos/device_skin.h"):
    depth_stack = []
    for n, line in enumerate(open(sys.argv[1] + "/" + f), 1):
        s = line.strip()
        if s.startswith("#ifdef NORNS_LINUX_DESKTOP"): depth_stack.append("L")
        elif s.startswith("#ifndef NORNS_LINUX_DESKTOP"): depth_stack.append("M")
        elif s.startswith("#if"): depth_stack.append("?")
        elif s.startswith("#else") and depth_stack: depth_stack[-1] = {"L": "M", "M": "L"}.get(depth_stack[-1], "?")
        elif s.startswith("#endif") and depth_stack: depth_stack.pop()
        if re.search(r"\b(skin_set_look|skin_set_pixel_look|skin_set_fast|look_fast|skin_set_buttons_shown|look_style|look_shown|look_muted|part_tinted|look_col|box_style_|box_tint_stop|BOX_PART_)", line) and "stopt(" not in line:
            if "L" not in depth_stack and not s.startswith(("//", "*", "/*")):
                print("%s:%d outside: %s" % (f, n, s)); sys.exit(1)
PY
# the clipboard and picker additions to the shared window and Lua binding files are all inside NORNS_LINUX_DESKTOP blocks
python3 - "$REPO" << 'PY' && ok "the clipboard additions to sdl_bridge.cc/.h and weaver.cc are all inside NORNS_LINUX_DESKTOP blocks" || bad "a clipboard line of a shared file is outside NORNS_LINUX_DESKTOP"
import re, sys
for f in ("matron/src/platform/macos/sdl_bridge.cc", "matron/src/platform/macos/sdl_bridge.h", "matron/src/weaver.cc"):
    stack = []
    for n, line in enumerate(open(sys.argv[1] + "/" + f), 1):
        s = line.strip()
        if s.startswith("#ifdef NORNS_LINUX_DESKTOP"): stack.append("L")
        elif s.startswith("#ifndef NORNS_LINUX_DESKTOP"): stack.append("M")
        elif s.startswith("#if"): stack.append("?")
        elif s.startswith("#else") and stack: stack[-1] = {"L": "M", "M": "L"}.get(stack[-1], "?")
        elif s.startswith("#endif") and stack: stack.pop()
        if re.search(r"clipboard|clip_text|clip_classify|CLIP_MAX|clip_status", line) and not s.startswith(("//", "*", "/*")):
            if "L" not in stack:
                print("%s:%d outside: %s" % (f, n, s)); sys.exit(1)
PY
[ $FAIL = 0 ] && echo "box_c_test: all passed"
exit $FAIL
