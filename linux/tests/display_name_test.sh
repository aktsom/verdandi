#!/bin/bash
# linux/tests/display_name_test.sh: the name a person sees is "Verdandi Linux", defined once (linux/brand.sh), and the internal names
# did not change. the window title (under Xvfb), the menu entry, the .deb description, the manual's title and heading, the README.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
FAILS=0
check() { if [ "$2" = "$3" ]; then echo "  ok    $1"; else echo "  FAIL  $1: got '$2', want '$3'"; FAILS=$((FAILS + 1)); fi; }
has() { case "$2" in *"$3"*) echo "  ok    $1" ;; *) echo "  FAIL  $1: '$3' not in '$2'"; FAILS=$((FAILS + 1)) ;; esac; }
hasnt() { case "$2" in *"$3"*) echo "  FAIL  $1: '$3' is in '$2'"; FAILS=$((FAILS + 1)) ;; *) echo "  ok    $1" ;; esac; }
. "$REPO/linux/brand.sh"
check "the display name" "$VERDANDI_DISPLAY_NAME" "Verdandi Linux"
case "$VERDANDI_DISPLAY_NAME" in *"("*) echo "  FAIL  parentheses in the display name"; FAILS=$((FAILS + 1)) ;; *) echo "  ok    no parentheses" ;; esac

D="$("$REPO/linux/package.sh" print-desktop)"
check "menu entry name" "$(echo "$D" | sed -n 's/^Name=//p')" "$VERDANDI_DISPLAY_NAME"
has "menu entry comment says it is the Linux version of Verdandi, norns on the desktop" "$(echo "$D" | sed -n 's/^Comment=//p')" "Linux version of Verdandi, norns on the desktop"
check "menu entry still runs the command verdandi" "$(echo "$D" | sed -n 's/^Exec=//p')" "verdandi"
check "menu entry StartupWMClass is the window class from brand.sh" "$(echo "$D" | sed -n 's/^StartupWMClass=//p')" "$VERDANDI_WM_CLASS"
check "menu entry icon name unchanged" "$(echo "$D" | sed -n 's/^Icon=//p')" "verdandi"
DESC="$("$REPO/linux/package.sh" print-description)"
check "deb description first line" "$(echo "$DESC" | head -1)" "Description: $VERDANDI_DISPLAY_NAME: norns on the desktop"
has "deb description names the Linux version" "$DESC" "is the Linux version of Verdandi"
has "deb description keeps the attribution" "$DESC" "ha1dcre"
has "deb description keeps the licence statement" "$DESC" "GPL-3.0"
grep -q '^Package: verdandi$' "$REPO/linux/package.sh" && echo "  ok    package name is still verdandi" || { echo "  FAIL  package name"; FAILS=$((FAILS + 1)); }

M="$REPO/linux/manual/manual.html"
check "manual title" "$(sed -n 's:.*<title>\(.*\)</title>.*:\1:p' "$M")" "$VERDANDI_DISPLAY_NAME: manual"
check "manual first heading" "$(sed -n 's:.*<h1>\(.*\)</h1>.*:\1:p' "$M" | head -1)" "$VERDANDI_DISPLAY_NAME"
has "manual keeps the attribution" "$(cat "$M")" "ha1dcre"
R="$(cat "$REPO/readme-linux.md")"
check "README first heading" "$(head -1 "$REPO/readme-linux.md")" "# $VERDANDI_DISPLAY_NAME"
has "README says it is the Linux version of Verdandi" "$R" "Linux version of Verdandi"
has "README names the original author and the licence" "$R" "(ha1dcre)"
has "README keeps the licence and copyright notices" "$R" "keeps their licence"
has "readme.md points to the Linux README" "$(cat "$REPO/readme.md")" "readme-linux.md"
# the upstream notices are still there
[ -s "$REPO/LICENSE.txt" ] && echo "  ok    LICENSE.txt is there" || { echo "  FAIL  LICENSE.txt"; FAILS=$((FAILS + 1)); }
# internal names did not change
for n in 'JACK_MIDI_CLIENT MACOS_PRODUCT' ; do grep -q "$n" "$REPO/matron/src/platform/linux/jack_midi_in.cc" && echo "  ok    JACK client name still the product name" || { echo "  FAIL  JACK client name"; FAILS=$((FAILS + 1)); }; done
grep -q '"Verdandi:midi_in"' "$REPO/matron/src/platform/linux/midi_autoconnect.cc" && echo "  ok    port Verdandi:midi_in unchanged" || { echo "  FAIL  midi port name"; FAILS=$((FAILS + 1)); }

# the window title, through the real launcher
if command -v xdotool > /dev/null && command -v xprop > /dev/null && command -v Xvfb > /dev/null; then
    T="$(mktemp -d)"
    trap 'rm -rf "$T"' EXIT
    ln -s "$REPO" "$T/norns"
    NORNS_NO_SCLANG=1 NORNS_MAIDEN="$T/none" NORNS_HOME="$T" "$HERE/norns_probe.sh" "$HERE/probe_title.lua" "$T/log" > /dev/null 2>&1
    check "one window is titled exactly '$VERDANDI_DISPLAY_NAME'" "$(head -1 "$T/probe.marks" 2> /dev/null | tr -d ' ')" "1"
    # the window class the program sets, read from the window itself, equals the menu entry's StartupWMClass; the icon is set from a file
    check "the window class equals StartupWMClass of the menu entry" "$(sed -n 's/^CLASS //p' "$T/probe.marks" | head -1)" "\"$(echo "$D" | sed -n 's/^StartupWMClass=//p')\", \"$(echo "$D" | sed -n 's/^StartupWMClass=//p')\""
    check "SDL gets the class from the launcher (independent of the program's file name)" "$(sed -n 's/^ENV SDL_VIDEO_X11_WMCLASS=//p' "$T/probe.marks")" "$VERDANDI_WM_CLASS"
    ICON="$(sed -n 's/^ENV NORNS_ICON=//p' "$T/probe.marks")"
    [ -f "$ICON" ] && echo "  ok    the window icon comes from a file ($ICON)" || { echo "  FAIL  no window icon file: '$ICON'"; FAILS=$((FAILS + 1)); }
    # with no launcher (NORNS_DISPLAY_NAME unset) the title would be "Verdandi": the Mac app. the C helper is the only place
    has "the helper falls back to the product name" "$(cat "$REPO/matron/src/platform/common/display_name.h")" ": product;"
else
    echo "  skip  window title (xdotool or Xvfb missing)"
fi
[ $FAILS -eq 0 ] && echo "display_name_test: all passed" || echo "display_name_test: $FAILS failed"
[ $FAILS -eq 0 ]
