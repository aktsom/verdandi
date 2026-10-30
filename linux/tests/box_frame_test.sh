#!/bin/bash
# the window's frame time while it is resized (docs/port/box-style-plan.md, fixes after the owner's test): box_frame_bench draws 121 window sizes (640..1600 wide) for the aluminium style, the
# tinted aluminium and the pixel style, the way the window does while it is dragged (skin_set_fast(1): the box layers from the cached block image, the screen picture without the filter), and
# the way it does when the size has settled. two things are checked: (1) the average time per frame in the dragged mode stays under a generous budget (BENCH_BUDGET_MS, default 250 ms: a loaded
# headless machine is slow, this is for a regression to the old several-hundred-ms pixel frames, not a speed claim) and (2) the final image after the whole sequence, with the quick drawing off
# and the layers made again, is the same as a cold direct draw at that size (no old size left in a cache). the present step needs a display and is not part of this test
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO" || exit 1
T="$(mktemp -d)"
trap 'rm -rf "${T:?}"' EXIT
CF="$(pkg-config --cflags cairo freetype2)"; LF="$(pkg-config --libs cairo freetype2)"
SK=matron/src/platform/macos; LN=matron/src/platform/linux
cc -std=gnu11 -O2 -Wall -Wextra -DNORNS_LINUX_DESKTOP -I $SK -I $LN $CF linux/tests/box_frame_bench.c $SK/device_skin.c $LN/box_style.c $LN/box_palette.c -o "$T/bench" $LF -lm 2> "$T/cc.log" || { echo "  FAIL  box_frame_bench does not build"; cat "$T/cc.log"; exit 1; }
FAIL=0
for m in alu tint pixel retro 8bit 16bit; do
    for flag in --fast ""; do
        # the slow (settled, one-by-one crisp) sequence has no time budget here, only the final-image check
        if [ -n "$flag" ]; then B="${BENCH_BUDGET_MS:-250}"; else B=100000; fi
        if BENCH_BUDGET_MS="$B" "$T/bench" $m $flag --check > "$T/out.txt" 2>&1; then
            echo "  ok    $m ${flag:-settled}: $(grep 'rows differ' "$T/out.txt" | sed 's/^ *//'); $(grep -o 'total [0-9.]*' "$T/out.txt" | tail -n 1) ms per frame"
        else
            echo "  FAIL  $m ${flag:-settled}"; tail -n 6 "$T/out.txt"; FAIL=1
        fi
    done
done
[ $FAIL = 0 ] && echo "box_frame_test: all passed"
exit $FAIL
