#!/bin/bash
# linux/tests/capture_dir_linux_test.sh (M25): where a screenshot goes on Linux: <Pictures>/Verdandi, as on Windows (the Pictures folder is found as before: XDG_PICTURES_DIR, ~/.config/user-dirs.dirs, ~/Pictures);
# the dust folder when there is no Pictures folder or the subfolder cannot be made. the real norns on Xvfb takes a screenshot through the window action "screenshot" (the same code as Ctrl+Shift+S and the menu).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
FAILS=0
ok() { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; FAILS=$((FAILS + 1)); }
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
shot() { # name, XDG_PICTURES_DIR value: runs norns with that Pictures folder and takes one screenshot
    local H="$T/$1"
    mkdir -p "$H" && ln -s "$REPO" "$H/norns"
    printf '%s\n' "#sleep 3" "_norns.window_action('screenshot')" "#sleep 3" > "$T/$1.lua"
    XDG_PICTURES_DIR="$2" NORNS_MAIDEN="$T/none" NORNS_HOME="$H" "$HERE/norns_probe.sh" "$T/$1.lua" "$T/$1.log" > /dev/null 2>&1
}
count() { find "$1" -maxdepth 1 -name 'Verdandi *.png' 2> /dev/null | wc -l; }
mkdir -p "$T/pics"
shot a "$T/pics"
[ "$(count "$T/pics/Verdandi")" = 1 ] && ok "a Pictures folder: the screenshot is in Pictures/Verdandi" || bad "no screenshot in $T/pics/Verdandi (found: $(find "$T/pics" "$T/a/dust" -name '*.png' 2> /dev/null | tr '\n' ' '))"
[ "$(count "$T/pics")" = 0 ] && ok "and none directly in Pictures (as before M25)" || bad "a screenshot is directly in the Pictures folder"
shot b "$T/does-not-exist"
[ "$(count "$T/b/dust")" = 1 ] && ok "no Pictures folder: the screenshot is in the dust folder, as before" || bad "no screenshot in the dust folder (found: $(find "$T/b" -name '*.png' | tr '\n' ' '))"
mkdir -p "$T/pics2" && : > "$T/pics2/Verdandi"
shot c "$T/pics2"
[ "$(count "$T/c/dust")" = 1 ] && ok "the subfolder cannot be made (a file has its name): the dust folder" || bad "no screenshot in the dust folder when the subfolder cannot be made"
grep -aq "Pictures/Verdandi" "$T/a.log" && ok "the toast says where: Pictures/Verdandi" || echo "  note  (the toast text is not in the log: not counted)"
[ $FAILS -eq 0 ] && echo "capture_dir_linux_test: all passed" || echo "capture_dir_linux_test: $FAILS failed"
[ $FAILS -eq 0 ]
