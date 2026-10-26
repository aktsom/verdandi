#!/bin/bash
# linux/tests/manual_button_test.sh: the MANUAL button of the window. NORNS_MANUAL names a file that exists: xdg-open (a stub that records its argument) gets it.
# NORNS_MANUAL names a file that is not there, or is not set: nothing is opened and the window shows a note for a few seconds.
# linux/norns.sh sets NORNS_MANUAL to linux/manual/manual.html unless it is already set (checked here with NORNS_DECIDE_ONLY off: through the real launcher).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
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
echo '<html><body>manual</body></html>' > "$T/man.html"
run() { # name, NORNS_MANUAL value ("-" = leave the launcher's own)
    mkdir -p "$T/$1"
    ln -s "$REPO" "$T/$1/norns"
    if [ "$2" = "-" ]; then
        PATH="$T/bin:$PATH" XDG_LOG="$T/$1.xdg" NORNS_NO_SCLANG=1 NORNS_MAIDEN="$T/none" NORNS_HOME="$T/$1" \
            "$HERE/norns_probe.sh" "$HERE/probe_manual_button.lua" "$T/$1.log" > /dev/null 2>&1
    else
        PATH="$T/bin:$PATH" XDG_LOG="$T/$1.xdg" NORNS_MANUAL="$2" NORNS_NO_SCLANG=1 NORNS_MAIDEN="$T/none" NORNS_HOME="$T/$1" \
            "$HERE/norns_probe.sh" "$HERE/probe_manual_button.lua" "$T/$1.log" > /dev/null 2>&1
    fi
}
echo "== NORNS_MANUAL names a file"
run present "$T/man.html"
check "xdg-open got the file" "$(cat "$T/present.xdg" 2> /dev/null)" "$T/man.html"
has "no note" "$(grep 'PROBE manual note after' "$T/present.log")" "nil"
echo "== the file is missing"
run missing "$T/not-there.html"
check "nothing was opened" "$(cat "$T/missing.xdg" 2> /dev/null)" ""
has "the window says the manual is missing" "$(grep 'PROBE manual note after' "$T/missing.log")" "manual not found"
has "the note goes after a few seconds" "$(grep 'PROBE manual note later' "$T/missing.log")" "nil"
echo "== the launcher's own setting"
run own -
if [ -f "$REPO/linux/manual/manual.html" ]; then
    check "xdg-open got linux/manual/manual.html" "$(cat "$T/own.xdg" 2> /dev/null)" "$REPO/linux/manual/manual.html"
else
    check "no linux/manual/manual.html yet: nothing opened" "$(cat "$T/own.xdg" 2> /dev/null)" ""
    has "no linux/manual/manual.html yet: the window says so" "$(grep 'PROBE manual note after' "$T/own.log")" "manual not found"
fi
[ $FAILS -eq 0 ] && echo "manual_button_test: all passed" || { echo "manual_button_test: $FAILS failed"; tail -6 "$T/present.log" "$T/missing.log"; }
[ $FAILS -eq 0 ]
