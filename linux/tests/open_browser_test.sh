#!/bin/bash
# linux/tests/open_browser_test.sh: the MANUAL button (the same route as MAIDEN and the folder menu: open_url.c) starts the system's
# `xdg-open` the way a terminal would: the user's own HOME and XDG folders (the default browser is read from
# ~/.config/mimeapps.list, and linux/norns.sh gives norns the norns home as HOME), BROWSER and PATH untouched, the xdg-open that is
# first on PATH. a stub xdg-open records its environment. found on a laptop: the buttons opened Firefox while xdg-open in a terminal
# opened the default browser.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
FAILS=0
check() { if [ "$2" = "$3" ]; then echo "  ok    $1"; else echo "  FAIL  $1: got '$2', want '$3'"; FAILS=$((FAILS + 1)); fi; }
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/user" "$T/nh"
ln -s "$REPO" "$T/nh/norns"
cat > "$T/bin/xdg-open" <<'S'
#!/bin/sh
{
  echo "ARG=$1"
  echo "HOME=$HOME"
  echo "XDG_CONFIG_HOME=${XDG_CONFIG_HOME-unset}"
  echo "XDG_DATA_HOME=${XDG_DATA_HOME-unset}"
  echo "BROWSER=${BROWSER-unset}"
  echo "XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP-unset}"
  echo "WHICH=$(command -v xdg-open)"
} > "$XDG_LOG"
S
chmod +x "$T/bin/xdg-open"
echo '<html><body>manual</body></html>' > "$T/man.html"

# as a terminal user would have it: their HOME, one XDG folder set (config), one not (data), their BROWSER and desktop
HOME="$T/user" XDG_CONFIG_HOME="$T/user/cfg" BROWSER="$T/user/mybrowser" XDG_CURRENT_DESKTOP=X-Cinnamon \
    PATH="$T/bin:$PATH" XDG_LOG="$T/rec" NORNS_MANUAL="$T/man.html" NORNS_NO_SCLANG=1 NORNS_MAIDEN="$T/none" NORNS_HOME="$T/nh" \
    "$HERE/norns_probe.sh" "$HERE/probe_manual_button.lua" "$T/log" > /dev/null 2>&1
rec() { sed -n "s/^$1=//p" "$T/rec" 2> /dev/null; }
check "xdg-open got the manual" "$(rec ARG)" "$T/man.html"
check "HOME is the user's, not the norns home" "$(rec HOME)" "$T/user"
check "XDG_CONFIG_HOME is the user's" "$(rec XDG_CONFIG_HOME)" "$T/user/cfg"
check "XDG_DATA_HOME was not set and is not set" "$(rec XDG_DATA_HOME)" "unset"
check "BROWSER is as the user had it" "$(rec BROWSER)" "$T/user/mybrowser"
check "XDG_CURRENT_DESKTOP is as the user had it" "$(rec XDG_CURRENT_DESKTOP)" "X-Cinnamon"
check "the xdg-open that runs is the first one on PATH" "$(rec WHICH)" "$T/bin/xdg-open"
# nothing of the package may shadow the system's xdg-open
[ -z "$(find "$REPO/linux" "$REPO/build" -maxdepth 3 -name 'xdg-*' 2> /dev/null | grep -v '/tests/')" ] && echo "  ok    no xdg-* program in the tree" || { echo "  FAIL  an xdg-* program is in the tree"; FAILS=$((FAILS + 1)); }
[ $FAILS -eq 0 ] && echo "open_browser_test: all passed" || { echo "open_browser_test: $FAILS failed"; cat "$T/rec" 2> /dev/null; }
[ $FAILS -eq 0 ]
