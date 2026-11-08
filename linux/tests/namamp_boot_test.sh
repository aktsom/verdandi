#!/bin/bash
# linux/tests/namamp_boot_test.sh <log>: the real princeton script in a headless boot (norns_probe.sh) that starts with the Raspberry Pi NamAmp.so in the extension folder, as a script's
# own install step leaves it: the launcher moves it aside (manifest) and seeds Verdandi's x86-64 copy before sclang starts; the engine says "princeton: NAM available"; the script's own install
# step (cmp / cp through the shims) sees NAM as installed and neither the copy nor the script's own file changes; a NAM model gives signal; a plug-in a script installs while norns runs gets a note and
# a CLEAN UP line and is moved after the confirmation (probe_namamp.lua). needs: the built pack (NORNS_NAMAMP_PACK, linux/package.sh namamp), a clone of the princeton script
# (NORNS_PRINCETON=<dir>) and the test tools gcc / jack. prints "SKIP ..." and exits 77 if one is missing.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
LOG="$1"
PACK="${NORNS_NAMAMP_PACK:-$REPO/build/package/cache/namamp-pack/NamAmp}"
PR="${NORNS_PRINCETON:-}"
[ -f "$PACK/NamAmp.so" ] && [ -f "$PACK/.verdandi-namamp" ] || { echo "SKIP namamp_boot_test: no stamped pack at $PACK (linux/package.sh namamp)"; exit 77; }
[ -f "$PR/princeton.lua" ] && [ -f "$PR/lib/nam/NamAmp.so" ] || { echo "SKIP namamp_boot_test: no clone of the princeton script (NORNS_PRINCETON=<dir>)"; exit 77; }
[ -x "$REPO/build/linux/plugin_arch_check" ] || { echo "SKIP namamp_boot_test: build/linux/plugin_arch_check is not built (linux/build.sh)"; exit 77; }
W="$(mktemp -d)"
mkdir -p /tmp/nam
gcc -O1 -o /tmp/nam/tone "$REPO/linux/tests/tone.c" $(pkg-config --cflags --libs jack) -lm 2> "$W/cc.log" || { cat "$W/cc.log"; echo "SKIP namamp_boot_test: cannot build the tone client"; exit 77; }
gcc -O1 -std=gnu11 -o /tmp/nam/jack_peak "$REPO/linux/tests/jack_peak.c" $(pkg-config --cflags --libs jack) -lm 2>> "$W/cc.log" || { echo "SKIP namamp_boot_test: cannot build jack_peak"; exit 77; }
H="$W/home"
mkdir -p "$H/dust/code" "$H/dust/data/princeton/nam" "$H/.local/share/SuperCollider/Extensions/princeton"
ln -s "$REPO" "$H/norns"
cp -a "$PR" "$H/dust/code/princeton"; rm -rf "$H/dust/code/princeton/.git"
cp "$REPO/linux/tests/fixtures/nam/wavenet.nam" "$REPO/linux/tests/fixtures/nam/lstm.nam" "$H/dust/data/princeton/nam/"
# the state a script's own install step leaves: its Raspberry Pi file in the extension folder (and an unrelated Raspberry Pi plug-in of another script)
cp "$PR/lib/nam/NamAmp.so" "$H/.local/share/SuperCollider/Extensions/princeton/NamAmp.so"
mkdir -p "$H/.local/share/SuperCollider/Extensions/other-script"
cp "$PR/lib/nam/NamAmp.so" "$H/.local/share/SuperCollider/Extensions/other-script/Other_scsynth.so"
echo "$(sha256sum "$PR/lib/nam/NamAmp.so" | cut -d' ' -f1)" > "$W/arm.sha"
export NORNS_HOME="$H" NORNS_NAMAMP_PACK="$PACK" MI_FOREIGN_INTERVAL=1
"$REPO/linux/tests/norns_probe.sh" "$REPO/linux/tests/probe_namamp.lua" "$LOG" > /dev/null 2>&1
{
    echo "PROBE arm sha: $(cat "$W/arm.sha")"
    echo "PROBE pack sha: $(sha256sum "$PACK/NamAmp.so" | cut -d' ' -f1)"
    for f in ext_before ext_after script_before script_after; do echo "PROBE $f: $(cat "$H/probe.marks.$f" 2>/dev/null)"; done
    echo "PROBE peak off: $(cat "$H/probe.marks.peak_off" 2>/dev/null)"
    echo "PROBE peak on: $(cat "$H/probe.marks.peak_on" 2>/dev/null)"
    echo "PROBE sclang elf errors: $(grep -ac "wrong ELF" "$H/logs/sclang.log" 2>/dev/null)"
    echo "PROBE nam available: $(grep -ac "princeton: NAM available" "$H/logs/sclang.log" 2>/dev/null)"
    echo "PROBE namamp loaded: $(grep -ac "^NamAmp: loaded" "$H/logs/sclang.log" 2>/dev/null)"
    echo "PROBE manifest: $(grep -ac "wrong-architecture plug-in" "$H/disabled/MANIFEST.tsv" 2>/dev/null)"
    echo "PROBE manifest namamp: $(grep -ac "NamAmp.so" "$H/disabled/MANIFEST.tsv" 2>/dev/null)"
    echo "PROBE moved other: $([ ! -e "$H/.local/share/SuperCollider/Extensions/other-script" ] && echo yes || echo no)"
} >> "$LOG"
rm -rf "$W"
exit 0
