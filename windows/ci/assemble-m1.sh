#!/usr/bin/env bash
# windows/ci/assemble-m1.sh (M1): the runnable folder and its zip. bash (Git Bash on the runner, or Linux for a dry run with fake inputs).
#   NORNS_BIN   folder with Verdandi.exe, norns.exe and the DLLs (build-norns.sh output)   SC_ZIP   sc-win64.zip of build-sc.sh   OUT   result folder (default ./m1-stage)
# result: $OUT/Verdandi/ (the program folder as the user gets it) and $OUT/Verdandi-windows-M1.zip
# shellcheck disable=SC2329
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=windows/ci/lib.sh
. "$HERE/lib.sh"
REPO="$(cd "$HERE/../.." && pwd)"
NORNS_BIN="${NORNS_BIN:?NORNS_BIN is not set}"
SC_ZIP="${SC_ZIP:?SC_ZIP is not set}"
OUT="${OUT:-$PWD/m1-stage}"
APP="$OUT/Verdandi"

unzip_to() { # zip dir
    if command -v 7z > /dev/null 2>&1; then 7z x "$1" "-o$2" -y > /dev/null; else unzip -q -o "$1" -d "$2"; fi
}
zip_dir() { # parent dir name zipfile
    if command -v 7z > /dev/null 2>&1; then (cd "$1" && 7z a -tzip -mx=6 "$3" "$2" > /dev/null); else (cd "$1" && zip -q -r "$3" "$2"); fi
}

assemble() {
    rm -rf "$OUT"
    mkdir -p "$APP"
    # program and DLLs
    cp "$NORNS_BIN"/* "$APP/" || return 1
    # norns's own files: the Lua side, fonts and images, the SuperCollider classes, the version
    for d in lua resources sc update; do
        cp -r "$REPO/$d" "$APP/$d" || return 1
    done
    rm -rf "$APP/sc/tests" "$APP/update/pack.sh" "$APP/update/test-update.sh" "$APP/update/update.sh"
    cp "$REPO/windows/pack/matronrc.lua" "$APP/matronrc.lua"
    cp "$REPO/windows/pack/README-M1.txt" "$APP/README.txt"
    # sclang runs "jack_connect ..." to wire scsynth into crone (Linux, macOS): there is no JACK server here in M1, so these stand-ins do nothing, quietly
    cp "$REPO"/windows/pack/jack_*.cmd "$APP/"
    mkdir -p "$APP/smoke" && cp "$REPO"/windows/pack/smoke/verdandi_*.lua "$APP/smoke/"
    # a small set of scripts for the first tests, copied into dust\code on the first start when that folder is empty (launcher). fetched here, not kept in the repository; not fatal:
    # without them the zip is the same, SELECT then says "no scripts found". awake: https://github.com/tehn/awake (licence to be checked by the owner); the commit is written next to it
    mkdir -p "$APP/dust-seed/code"
    if command -v git > /dev/null 2>&1 && git clone --quiet --depth 1 https://github.com/tehn/awake "$OUT/awake-src" 2> /dev/null; then
        mv "$OUT/awake-src" "$APP/dust-seed/code/awake"
        git -C "$APP/dust-seed/code/awake" rev-parse HEAD > "$APP/dust-seed/code/awake/SOURCE-COMMIT.txt" 2> /dev/null || true
        rm -rf "$APP/dust-seed/code/awake/.git"
        if [ -f "$APP/dust-seed/code/awake/awake.lua" ]; then echo "found: dust-seed/code/awake/awake.lua"; else echo "NOTE: awake fetched but awake.lua is not in it"; rm -rf "$APP/dust-seed/code/awake"; fi
    else
        echo "NOTE: awake could not be fetched; the zip has no seeded scripts"
        rm -rf "$OUT/awake-src"
    fi
    # SuperCollider, built in M0a (the zip holds one folder, SuperCollider)
    local tmp="$OUT/sc-unpacked"
    mkdir -p "$tmp"
    unzip_to "$SC_ZIP" "$tmp" || return 1
    [ -d "$tmp/SuperCollider" ] || { echo "no SuperCollider folder in $SC_ZIP"; return 1; }
    mv "$tmp/SuperCollider" "$APP/supercollider"
    rm -rf "$tmp"
    # licences
    mkdir -p "$APP/licenses"
    cp "$REPO/LICENSE.txt" "$APP/licenses/Verdandi-GPL-3.0.txt" 2> /dev/null || true
    cp "$APP/supercollider/COPYING" "$APP/licenses/SuperCollider-GPL.txt" 2> /dev/null || true
    # checks of the layout: what the launcher looks for
    local f ok=0
    for f in Verdandi.exe norns.exe matronrc.lua lua/core/config.lua resources/norns.ttf sc/core/Crone.sc supercollider/sclang.exe supercollider/scsynth.exe update/version.txt; do
        if [ -e "$APP/$f" ]; then echo "found: $f"; else echo "MISSING: $f"; ok=1; fi
    done
    return "$ok"
}

package() {
    zip_dir "$OUT" Verdandi "$OUT/Verdandi-windows-M1.zip" && find "$OUT" -maxdepth 1 -name 'Verdandi-windows-M1.zip' -size +1k
}

m0_init
m0_run assemble assemble || exit 0
m0_run package package
exit 0
