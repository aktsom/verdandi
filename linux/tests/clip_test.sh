#!/bin/bash
# the clipboard's C side: the classifier (clip_text.c) on every kind of text, and the real SDL clipboard round trip under Xvfb when there is one (docs/port/colour-picker-plan.md)
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO" || exit 1
T="$(mktemp -d)"
trap 'rm -rf "${T:?}"' EXIT
LN=matron/src/platform/linux
SDLF="$(pkg-config --cflags --libs sdl2 2> /dev/null)"
if [ -n "$SDLF" ]; then
    cc -std=gnu11 -Wall -Wextra -DHAVE_SDL -I $LN linux/tests/clip_text_test.c $LN/clip_text.c -o "$T/clip" $SDLF 2> "$T/cc.log" || { cat "$T/cc.log"; exit 1; }
else
    cc -std=gnu11 -Wall -Wextra -I $LN linux/tests/clip_text_test.c $LN/clip_text.c -o "$T/clip" 2> "$T/cc.log" || { cat "$T/cc.log"; exit 1; }
fi
if [ -z "${DISPLAY:-}" ] && command -v Xvfb > /dev/null; then
    Xvfb :98 -screen 0 800x600x24 > /dev/null 2>&1 &
    XV=$!
    export DISPLAY=:98
    sleep 1
    "$T/clip"; rc=$?
    kill "$XV" 2> /dev/null
    exit $rc
fi
"$T/clip"
