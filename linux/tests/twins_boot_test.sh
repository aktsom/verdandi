#!/bin/bash
# linux/tests/twins_boot_test.sh <log> [off]: a headless boot (norns_probe.sh) of the real norns with the real script twins (a clone of github.com/danielrigler/twins, or NORNS_TWINS=<dir>) in
# dust/code/twins, on an EMPTY SuperCollider extension folder: the launcher seeds the shipped PortedPlugins pack and copies the TwinGrain that the script carries (lib/ugens) before sclang
# starts; twins' own installer logic then says "[installer] all libraries installed.", the engine "twins" loads, and nothing is downloaded (a fake wget and curl record any call).
# "off" = NORNS_PORTED=0 and NORNS_TWINS_GRAIN=0: nothing is seeded, the installer says what it said on the owner's laptop ("missing AnalogChew (class file: NO, server plugin: NO)"):
# the control that shows the check can fail. needs the pack (build/linux/portedplugins from linux/build.sh, or NORNS_PORTED_TEST_PACK) and twins; prints "SKIP ..." and exits 77 without.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
LOG="$1"
PACK="${NORNS_PORTED_TEST_PACK:-$REPO/build/linux/portedplugins/PortedPlugins}"
[ -f "$PACK/.verdandi-stamp" ] || { echo "SKIP twins_boot_test: no stamped PortedPlugins pack at $PACK (linux/build.sh, or NORNS_PORTED_TEST_PACK)"; exit 77; }
H="$(mktemp -d)"
trap 'rm -rf "$H"' EXIT
TW="${NORNS_TWINS:-}"
if [ -z "$TW" ] || [ ! -f "$TW/twins.lua" ]; then
    git clone -q --depth 1 https://github.com/danielrigler/twins "$H/twins-src" 2> /dev/null && TW="$H/twins-src" || TW=""
fi
[ -n "$TW" ] && [ -f "$TW/twins.lua" ] || { echo "SKIP twins_boot_test: no clone of the script twins (no network? NORNS_TWINS=<dir>)"; exit 77; }
ln -s "$REPO" "$H/norns"
mkdir -p "$H/dust/code" "$H/dust/data" "$H/fakebin"
cp -R "$TW" "$H/dust/code/twins"
rm -rf "$H/dust/code/twins/.git"
for c in wget curl; do printf '#!/bin/sh\necho "$0 $*" >> "%s/downloads.txt"\nexit 1\n' "$H" > "$H/fakebin/$c"; chmod +x "$H/fakebin/$c"; done
export PATH="$H/fakebin:$PATH"
export NORNS_PORTED_PACK="$PACK"
if [ "${2:-}" = off ]; then export NORNS_PORTED=0 NORNS_TWINS_GRAIN=0; fi
export NORNS_HOME="$H"
"$REPO/linux/tests/norns_probe.sh" "$REPO/linux/tests/probe_twins.lua" "$LOG" > /dev/null 2>&1
{
    echo "PROBE twins commit: $(git -C "$TW" log -1 --format=%h 2> /dev/null)"
    echo "PROBE downloads: $( [ -f "$H/downloads.txt" ] && tr '\n' ' ' < "$H/downloads.txt" || echo none)"
    echo "PROBE extensions: $(ls -A "$H/.local/share/SuperCollider/Extensions" 2> /dev/null | tr '\n' ' ')"
    echo "PROBE sclang problems: $(grep -ac 'duplicate Class\|wrong ELF\|not installed' "$H/logs/sclang.log" 2> /dev/null)"
    echo "PROBE sclang grains: $(grep -a 'twins: grains via' "$H/logs/sclang.log" 2> /dev/null | tail -n 1)"
} >> "$LOG"
exit 0
