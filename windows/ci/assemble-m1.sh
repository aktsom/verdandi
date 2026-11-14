#!/usr/bin/env bash
# windows/ci/assemble-m1.sh (M1): the runnable folder and its zip. bash (Git Bash on the runner, or Linux for a dry run with fake inputs).
#   NORNS_BIN   folder with Verdandi.exe, norns.exe and the DLLs (build-norns.sh output)   SC_ZIP   sc-win64.zip of build-sc.sh   OUT   result folder (default ./m1-stage)
# result: $OUT/Verdandi-<version>-<short hash>/ (the program folder as the user gets it: the zip has this one folder, so that every build unpacks into a folder of its own and an old build is never
# overwritten or mistaken for the new one) and $OUT/Verdandi-windows-<version>-<short hash>.zip; $OUT/ZIPNAME holds the file name, $OUT/BUILD.txt a copy of the zip's BUILD.txt.
#   FLAVOR  "" (default: WASAPI only, no ASIO code in the zip) or "asio": the zip that has the ASIO build of PortAudio (ASIO_DIR: the output of build-portaudio-asio.sh: libportaudio-2.dll, source/, PA-ASIO-BUILD.txt) and the
#           GPLv3 notices and sources that go with it (docs/port/asio-licence.md). its names: Verdandi-asio-<version>-<hash>/ and Verdandi-windows-asio-<version>-<hash>.zip
#   VERDANDI_VERSION  (default: the first line of windows/VERSION)   VERDANDI_HASH (default: the first 7 characters of git rev-parse HEAD)   VERDANDI_REPO (owner/name, for update-and-run; default $GITHUB_REPOSITORY)
# shellcheck disable=SC2329
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=windows/ci/lib.sh
. "$HERE/lib.sh"
REPO="$(cd "$HERE/../.." && pwd)"
NORNS_BIN="${NORNS_BIN:?NORNS_BIN is not set}"
SC_ZIP="${SC_ZIP:?SC_ZIP is not set}"
OUT="${OUT:-$PWD/m1-stage}"
VERSION="${VERDANDI_VERSION:-$(head -n 1 "$REPO/windows/VERSION" | tr -d '\r ')}"
HASH="${VERDANDI_HASH:-$(git -C "$REPO" rev-parse HEAD 2> /dev/null | cut -c1-7)}"
[ -n "$HASH" ] || HASH=nohash # (the first 7 characters of the commit: the same rule as windows/ci/publish-release.sh, so that the names agree)
BUILD="$VERSION $HASH"
FLAVOR="${FLAVOR:-}"
case "$FLAVOR" in
    "") APPNAME="Verdandi-$VERSION-$HASH"; ZIPNAME="Verdandi-windows-$VERSION-$HASH.zip" ;;
    asio)
        APPNAME="Verdandi-asio-$VERSION-$HASH"; ZIPNAME="Verdandi-windows-asio-$VERSION-$HASH.zip"
        ASIO_DIR="${ASIO_DIR:?ASIO_DIR is not set (FLAVOR=asio)}"
        ;;
    *) echo "FLAVOR must be empty or asio"; exit 1 ;;
esac
APP="$OUT/$APPNAME"

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
    # M6: maiden (built on Linux: windows/ci/build-maiden.sh), the portable tools (windows/ci/fetch-tools.sh: busybox.exe, MinGit) and the folder where plug-in packs for Windows are seeded from.
    # a missing part is said, not fatal: the checks of the smoke test then fail for it
    if [ -n "${MAIDEN_DIR:-}" ] && [ -f "$MAIDEN_DIR/maiden.exe" ]; then
        mkdir -p "$APP/maiden" && cp -r "$MAIDEN_DIR"/. "$APP/maiden/" || return 1
        mkdir -p "$APP/licenses" && cp "$APP/maiden/LICENSE-maiden.txt" "$APP/licenses/maiden-LICENSE.txt" 2> /dev/null || true
        echo "found: maiden\\maiden.exe and its web app"
    else
        echo "NOTE: no maiden in this zip (MAIDEN_DIR='${MAIDEN_DIR:-}')"
    fi
    if [ -n "${TOOLS_DIR:-}" ] && [ -f "$TOOLS_DIR/busybox.exe" ]; then
        cp -r "$TOOLS_DIR"/. "$APP/" || return 1
        echo "found: busybox.exe and tools\\mingit"
    else
        echo "NOTE: no busybox and MinGit in this zip (TOOLS_DIR='${TOOLS_DIR:-}')"
    fi
    mkdir -p "$APP/extensions-seed"
    cp "$REPO/windows/pack/extensions-seed-README.txt" "$APP/extensions-seed/README.txt"
    # M7: the plug-in packs built for Windows (sc3-plugins, mi-UGens, NamAmp when its source was named): one folder per pack, with their licences and revisions
    if [ -n "${PLUGINS_DIR:-}" ] && [ -d "$PLUGINS_DIR/seed" ]; then
        for pack in "$PLUGINS_DIR"/seed/*/; do
            [ -d "$pack" ] || continue
            n=$(basename "$pack")
            if find "$pack" -name '*.scx' | grep -q . && [ -f "$pack/PACK-ID.txt" ]; then
                cp -r "$pack" "$APP/extensions-seed/$n" || return 1
                mkdir -p "$APP/licenses/$n"
                cp "$pack"/COPYING* "$pack"/LICENSE* "$APP/licenses/$n/" 2> /dev/null || true
                [ -d "$pack/licences" ] && cp -r "$pack/licences"/. "$APP/licenses/$n/"
                echo "found: plug-in pack $n ($(find "$pack" -name '*.scx' | wc -l) .scx files)"
            else
                echo "NOTE: pack $n has no .scx files or no PACK-ID.txt (the build found no class files, or a class twice), not in the zip"
            fi
        done
        cp "$PLUGINS_DIR/m7-report.txt" "$APP/extensions-seed/BUILD-REPORT.txt" 2> /dev/null || true
    else
        echo "NOTE: no plug-in packs in this zip (PLUGINS_DIR='${PLUGINS_DIR:-}')"
    fi
    [ -f "$APP/ws-wrapper.exe" ] && echo "found: ws-wrapper.exe" || echo "NOTE: no ws-wrapper.exe"
    # the ASIO build: its PortAudio takes the place of the MSYS2 one (the same file name, the loader goes by it), the licence text of the SDK, the notices and the sources
    if [ "$FLAVOR" = asio ]; then
        [ -f "$ASIO_DIR/libportaudio-2.dll" ] || { echo "no libportaudio-2.dll in $ASIO_DIR"; return 1; }
        cp "$ASIO_DIR/libportaudio-2.dll" "$APP/libportaudio-2.dll" || return 1
        mkdir -p "$APP/licenses" "$APP/source"
        cp "$ASIO_DIR/source/ASIO-SDK-LICENSE.txt" "$APP/licenses/ASIO-SDK-LICENSE.txt" || return 1
        cp "$ASIO_DIR/source/portaudio-source.zip" "$ASIO_DIR/source/asio-sdk-source.zip" "$ASIO_DIR/PA-ASIO-BUILD.txt" "$APP/source/" || return 1
        cp "$REPO/windows/pack/ASIO-NOTICE.txt" "$APP/ASIO-NOTICE.txt" || return 1
        cp "$REPO/windows/pack/ASIO-NOTICE.txt" "$APP/licenses/ASIO-NOTICE.txt"
        echo "asio" > "$APP/FLAVOR.txt"
    fi
    # which build this is: the launcher logs it and norns shows it; update-and-run compares it with the newest release
    {
        echo "$BUILD"
        echo "flavor: ${FLAVOR:-wasapi}"
        echo "built: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "commit: $(git -C "$REPO" rev-parse HEAD 2> /dev/null || echo unknown)"
        echo "message: $(git -C "$REPO" log -1 --format=%s 2> /dev/null || echo unknown)"
    } > "$APP/BUILD.txt"
    # the updater: update-and-run.cmd (curl.exe and tar.exe of Windows 10/11) and update-and-run.ps1 (PowerShell); UPDATE-SOURCE.txt says where the releases are
    cp "$REPO/windows/update-and-run.cmd" "$REPO/windows/update-and-run.ps1" "$APP/" || return 1
    echo "${VERDANDI_REPO:-${GITHUB_REPOSITORY:-}}" > "$APP/UPDATE-SOURCE.txt"
    cp "$APP/BUILD.txt" "$OUT/BUILD.txt"
    cp "$REPO/windows/pack/README-M1.txt" "$APP/README.txt"
    cp "$REPO/windows/pack/max-for-live-osc-cc.md" "$APP/max-for-live-osc-cc.md"
    # sclang runs "jack_connect ..." to wire scsynth into crone (Linux, macOS): there is no JACK server here in M1, so these stand-ins do nothing, quietly
    cp "$REPO"/windows/pack/jack_*.cmd "$APP/"
    mkdir -p "$APP/smoke" && cp "$REPO"/windows/pack/smoke/verdandi_*.lua "$APP/smoke/"
    # M13: a small script for trying the virtual arc (copy its folder into dust\code)
    mkdir -p "$APP/examples/arc_demo" && cp "$REPO/windows/pack/examples/arc_demo/arc_demo.lua" "$APP/examples/arc_demo/"
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
    # the source offer (GPL-3.0 section 6): where the corresponding source of this exact build is
    {
        sed -e "s|@BUILD@|$BUILD|g" -e "s|@COMMIT@|$(git -C "$REPO" rev-parse HEAD 2> /dev/null || echo unknown)|g" -e "s|@REPO@|${VERDANDI_REPO:-${GITHUB_REPOSITORY:-unknown}}|g" "$REPO/windows/pack/SOURCE-OFFER.txt"
        if [ "$FLAVOR" = asio ]; then
            echo
            # shellcheck disable=SC2028
            echo "ASIO build: the source of PortAudio as it was built, and of the Steinberg ASIO SDK as it was used, are in this folder: source\\portaudio-source.zip, source\\asio-sdk-source.zip (build record: source\\PA-ASIO-BUILD.txt)."
        fi
        if [ -d "$APP/extensions-seed" ] && [ -n "$(find "$APP/extensions-seed" -name '*.scx' 2> /dev/null | head -n 1)" ]; then
            echo
            echo "Plug-in packs in extensions-seed\\ (copied to the extensions folder at the first start): the .scx files were built for Windows x86-64 from these public sources, which are the complete corresponding source of what is in the zip:"
            [ -f "$APP/extensions-seed/sc3-plugins/SOURCE-REVISION.txt" ] && echo "  sc3-plugins (GPL-2.0-or-later, some parts other free licences: licenses\\sc3-plugins\\): https://github.com/supercollider/sc3-plugins at commit $(tr -d '\r\n' < "$APP/extensions-seed/sc3-plugins/SOURCE-REVISION.txt")"
            [ -f "$APP/extensions-seed/mi-UGens/SOURCE-REVISION.txt" ] && echo "  mi-UGens (licences: licenses\\mi-UGens\\): https://github.com/v7b1/mi-UGens at commit $(tr -d '\r\n' < "$APP/extensions-seed/mi-UGens/SOURCE-REVISION.txt")"
            [ -f "$APP/extensions-seed/NamAmp/SOURCE-REVISION.txt" ] && echo "  NamAmp (licenses\\NamAmp\\): see extensions-seed\\NamAmp\\SOURCE-REVISION.txt"
            # shellcheck disable=SC2028
            echo "  built against the headers of SuperCollider 3.14.1 with MSVC; the build scripts are windows\\ci\\build-sc3plugins.sh of the repository above. The build record is extensions-seed\\BUILD-REPORT.txt."
        fi
    } > "$APP/SOURCE-OFFER.txt"
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
    echo "$ZIPNAME" > "$OUT/ZIPNAME"
    zip_dir "$OUT" "$APPNAME" "$OUT/$ZIPNAME" && find "$OUT" -maxdepth 1 -name "$ZIPNAME" -size +1k
}

m0_init
m0_run assemble assemble || exit 0
m0_run package package
exit 0
