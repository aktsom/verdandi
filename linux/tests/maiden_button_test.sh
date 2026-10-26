#!/bin/bash
# linux/tests/maiden_button_test.sh [MAIDEN_DIR]: the MAIDEN button of the window. with maiden listening it opens http://127.0.0.1:<port>/maiden
# (xdg-open is a stub that records its argument); with nothing listening it opens nothing and the window shows a note for a few seconds.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
MD="${1:-$(dirname "$REPO")/maiden}"
if [ ! -x "$MD/maiden" ]; then
    echo "SKIP: $MD/maiden is not built (linux/maiden-build.sh)"
    exit 0
fi
FAILS=0
check() { if [ "$2" = "$3" ]; then echo "  ok    $1"; else echo "  FAIL  $1: got '$2', want '$3'"; FAILS=$((FAILS + 1)); fi; }
has() { case "$2" in *"$3"*) echo "  ok    $1" ;; *) echo "  FAIL  $1: '$3' not in '$2'"; FAILS=$((FAILS + 1)) ;; esac; }
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
cat > "$T/bin/xdg-open" <<'S'
#!/bin/sh
echo "$1" >> "$XDG_LOG"
S
chmod +x "$T/bin/xdg-open"
PORT=$(python3 -I -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])')
run() { # name, maiden dir
    mkdir -p "$T/$1"
    ln -s "$REPO" "$T/$1/norns"
    PATH="$T/bin:$PATH" XDG_LOG="$T/$1.xdg" NORNS_MAIDEN="$2" NORNS_MAIDEN_PORT="$PORT" NORNS_NO_SCLANG=1 NORNS_HOME="$T/$1" \
        "$HERE/norns_probe.sh" "$HERE/probe_maiden_button.lua" "$T/$1.log" > /dev/null 2>&1
}
echo "== maiden is running"
run up "$MD"
check "xdg-open got maiden's page" "$(cat "$T/up.xdg" 2> /dev/null)" "http://127.0.0.1:$PORT/maiden"
has "no note" "$(grep 'PROBE note after' "$T/up.log")" "nil"
echo "== maiden is not built / not running"
run down "$T/none"
check "nothing was opened" "$(cat "$T/down.xdg" 2> /dev/null)" ""
has "the window shows the note" "$(grep 'PROBE note after' "$T/down.log")" "maiden is not running, see log"
has "the note goes after a few seconds" "$(grep 'PROBE note later' "$T/down.log")" "nil"
[ -s "$T/down/maiden-button.png" ] && cp "$T/down/maiden-button.png" "${MAIDEN_BUTTON_SHOT:-/dev/null}" 2> /dev/null
[ $FAILS -eq 0 ] && echo "maiden_button_test: all passed" || { echo "maiden_button_test: $FAILS failed"; tail -8 "$T/up.log" "$T/down.log"; }
[ $FAILS -eq 0 ]
