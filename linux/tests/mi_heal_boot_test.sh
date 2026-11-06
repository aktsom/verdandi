#!/bin/bash
# linux/tests/mi_heal_boot_test.sh <log>: a headless boot (norns_probe.sh) with Verdandi's own mi-UGens pack and a Raspberry Pi download (fake ELF header) next to it:
# the launcher moves the download aside before sclang starts, sclang compiles without an ELF or class error, the window note shows once, and a download while
# norns runs gets a note and the CLEAN UP line (probe_mi_heal.lua). needs the built pack
# (NORNS_MI_TEST_PACK or build/package/cache/mi-ugens-pack from linux/package.sh mi); prints "SKIP ..." and exits 77 without it.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
LOG="$1"
PACK="${NORNS_MI_TEST_PACK:-$REPO/build/package/cache/mi-ugens-pack/mi-UGens}"
[ -f "$PACK/.verdandi-stamp" ] || { echo "SKIP mi_heal_boot_test: no stamped pack at $PACK"; exit 77; }
[ -x "$REPO/build/linux/mi_heal" ] || { echo "SKIP mi_heal_boot_test: build/linux/mi_heal is not built (linux/build.sh)"; exit 77; }
H="$(mktemp -d)"
ln -s "$REPO" "$H/norns"
E="$H/.local/share/SuperCollider/Extensions"
NORNS_HOME="$H" NORNS_MI_PACK="$PACK" "$REPO/linux/mi-ugens-seed.sh" seed "$PACK" "$H" > /dev/null 2>&1
mkdir -p "$E/arm-pack/Classes"
for c in MiPlaits MiRings MiBeads; do
    printf '\177ELF\001\001\001\000\000\000\000\000\000\000\000\000\003\000\050\000\000\000' > "$E/arm-pack/$c.so"
    echo "// theirs" > "$E/arm-pack/Classes/$c.sc"
done
export NORNS_HOME="$H" NORNS_MI_PACK="$PACK" MI_FOREIGN_INTERVAL=1
"$REPO/linux/tests/norns_probe.sh" "$REPO/linux/tests/probe_mi_heal.lua" "$LOG" > /dev/null 2>&1
{
    echo "PROBE sclang errors: $(grep -ac "wrong ELF\|duplicate Class\|not found" "$H/logs/sclang.log" 2>/dev/null)"
    echo "PROBE disabled: $(ls "$H/disabled" 2>/dev/null | grep -vc MANIFEST)"
} >> "$LOG"
rm -rf "$H"
exit 0
