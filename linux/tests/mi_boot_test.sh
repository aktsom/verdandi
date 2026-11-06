#!/bin/bash
# linux/tests/mi_boot_test.sh <log> [off]: a headless boot (norns_probe.sh) with the Emplaitress mod enabled and the shipped mi-UGens pack: the launcher seeds the
# pack, sclang compiles it, the mod finds it ("emplaitress found mi ugens") and nothing is downloaded (fake wget and curl record any call).
# "off" = NORNS_MI_UGENS=0: nothing is seeded and the mod does try to download (the fake wget sees it): the check that the harness can fail.
# needs a pack (NORNS_MI_TEST_PACK, a stamped mi-UGens folder; linux/package.sh leaves one in build/package/cache/mi-ugens-pack) and a clone of
# the Emplaitress mod (NORNS_EMPLAITRESS). prints "SKIP ..." and exits 77 if either is missing.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
LOG="$1"
PACK="${NORNS_MI_TEST_PACK:-$REPO/build/package/cache/mi-ugens-pack/mi-UGens}"
EMP="${NORNS_EMPLAITRESS:-}"
[ -f "$PACK/.verdandi-stamp" ] || { echo "SKIP mi_boot_test: no stamped pack at $PACK (linux/package.sh, or NORNS_MI_TEST_PACK)"; exit 77; }
[ -f "$EMP/lib/mod.lua" ] || { echo "SKIP mi_boot_test: no clone of the Emplaitress mod (NORNS_EMPLAITRESS=<dir>)"; exit 77; }
H="$(mktemp -d)"
ln -s "$REPO" "$H/norns"
mkdir -p "$H/dust/code" "$H/dust/data" "$H/fakebin"
cp -R "$EMP" "$H/dust/code/emplaitress"
(cd "$REPO" && MODS_FILE="$H/dust/data/system.mods" lua5.3 -e 'package.path="lua/?.lua;lua/lib/?.lua;"..package.path; require("tabutil").save({"emplaitress"}, os.getenv("MODS_FILE"))' )
for c in wget curl; do printf '#!/bin/sh\necho "$0 $*" >> "%s/downloads.txt"\nexit 1\n' "$H" > "$H/fakebin/$c"; chmod +x "$H/fakebin/$c"; done
export PATH="$H/fakebin:$PATH"
export NORNS_MI_PACK="$PACK"
[ "${2:-}" = off ] && export NORNS_MI_UGENS=0
export NORNS_HOME="$H"
"$REPO/linux/tests/norns_probe.sh" "$REPO/linux/tests/probe_mi_boot.lua" "$LOG" > /dev/null 2>&1
{
    echo "PROBE downloads: $( [ -f "$H/downloads.txt" ] && cat "$H/downloads.txt" | tr '\n' ' ' || echo none)"
    echo "PROBE pack: $(ls "$H/.local/share/SuperCollider/Extensions/mi-UGens" 2>/dev/null | tr '\n' ' ')"
    echo "PROBE sclang: $(grep -ac "not found\|duplicate Class\|wrong ELF" "$H/logs/sclang.log" 2>/dev/null)"
} >> "$LOG"
rm -rf "$H"
exit 0
