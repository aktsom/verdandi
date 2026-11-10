#!/usr/bin/env bash
# windows/ci/build-portaudio-asio.sh (M3): PortAudio WITH the ASIO host API, as a drop-in for the libportaudio-2.dll of MSYS2 (which has WASAPI, DirectSound and MME, no ASIO). run in the MSYS2 UCRT64 shell
# after the "packages" step of windows/ci/msys2-deps.sh (gcc, cmake, ninja). choice of MSYS2 over vcpkg: norns.exe and all its DLLs are MSYS2 UCRT64 builds; a vcpkg PortAudio would be an MSVC build
# with its own CRT and a second package manager, for the same DLL. the same norns.exe then serves both flavours: it asks the DLL which host APIs it has (audio_backend_pa.c).
#   OUT   result folder (default ./m3-asio): libportaudio-2.dll, PA-ASIO-BUILD.txt, source/portaudio-source.zip, source/asio-sdk-source.zip, source/ASIO-SDK-LICENSE.txt
# every step is recorded for the report (lib.sh). the sources are pinned by commit (windows/ci/asio-sdk.env); an empty pin prints the commit it used.
# shellcheck disable=SC2329
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=windows/ci/lib.sh
. "$HERE/lib.sh"
# shellcheck source=windows/ci/asio-sdk.env
. "${ASIO_ENV:-$HERE/asio-sdk.env}"
OUT="${OUT:-$PWD/m3-asio}"
WORK="${WORK:-$PWD/m3-work}"
mkdir -p "$OUT/source" "$WORK"

fetch() { # repo ref dir pin name
    local repo="$1" ref="$2" dir="$3" pin="$4" name="$5" got
    rm -rf "$dir"
    if [ -n "$ref" ]; then git clone --quiet --depth 1 --branch "$ref" "$repo" "$dir" || return 1; else git clone --quiet --depth 1 "$repo" "$dir" || return 1; fi
    got="$(git -C "$dir" rev-parse HEAD)"
    if [ -n "$pin" ] && [ "$got" != "$pin" ]; then
        echo "$name: the commit is $got, the pin says $pin: stopped (windows/ci/asio-sdk.env)"
        return 1
    fi
    if [ -z "$pin" ]; then echo "PINNED? $name is not pinned: used commit $got"; fi
    echo "$name: $got" >> "$OUT/PA-ASIO-BUILD.txt"
}

sources() {
    : > "$OUT/PA-ASIO-BUILD.txt"
    echo "PortAudio ASIO build for Verdandi, $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$OUT/PA-ASIO-BUILD.txt"
    fetch "$PA_REPO" "$PA_TAG" "$WORK/portaudio" "$PA_COMMIT" "portaudio $PA_TAG" || return 1
    fetch "$ASIO_SDK_REPO" "" "$WORK/asiosdk" "$ASIO_SDK_COMMIT" "asiosdk (default branch)" || return 1
    [ -f "$WORK/asiosdk/common/asio.h" ] || { echo "the SDK has no common/asio.h (a different layout?): $(find "$WORK/asiosdk" -maxdepth 2 | head -20 | tr '\n' ' ')"; return 1; }
    [ -f "$WORK/asiosdk/LICENSE.txt" ] || { echo "the SDK has no LICENSE.txt: stopped (the licence text must travel with the build)"; return 1; }
    echo "--- LICENSE.txt of the SDK, the first 12 lines:"
    head -n 12 "$WORK/asiosdk/LICENSE.txt"
    # the GPLv3 option has to be in the text we ship; if the file has no mention of it, stop and let a person read it
    grep -q -i "GPL" "$WORK/asiosdk/LICENSE.txt" || { echo "LICENSE.txt of the SDK does not mention the GPL: stopped, a person must read it"; return 1; }
    cp "$WORK/asiosdk/LICENSE.txt" "$OUT/source/ASIO-SDK-LICENSE.txt"
}

source_archives() {
    # what the GPL asks to travel with the binary (the corresponding source of the parts that are not ours): PortAudio as built and the SDK as used
    (cd "$WORK/portaudio" && git archive --format=zip -o "$OUT/source/portaudio-source.zip" HEAD) || return 1
    (cd "$WORK/asiosdk" && git archive --format=zip -o "$OUT/source/asio-sdk-source.zip" HEAD) || return 1
    ls -l "$OUT/source"
}

build() {
    local sdk="$WORK/asiosdk"
    if command -v cygpath > /dev/null 2>&1; then sdk="$(cygpath -m "$sdk")"; fi
    # the option names of PortAudio's CMake (19.7): PA_USE_ASIO, and the SDK is found through ASIOSDK_ROOT_DIR. both spellings are given; the first configure error lists what CMake missed
    ASIOSDK_ROOT_DIR="$sdk" cmake -S "$WORK/portaudio" -B "$WORK/pa-build" -G Ninja -DCMAKE_BUILD_TYPE=Release \
        -DPA_BUILD_SHARED_LIBS=ON -DPA_BUILD_TESTS=OFF -DPA_BUILD_EXAMPLES=OFF \
        -DPA_USE_ASIO=ON -DPA_USE_WASAPI=ON -DPA_USE_DS=ON -DPA_USE_WMME=ON -DPA_USE_WDMKS=OFF -DPA_USE_WDMKS_DEVICE_INFO=OFF \
        -DASIOSDK_ROOT_DIR="$sdk" -DASIO_SDK_PATH="$sdk" -DCMAKE_SHARED_LINKER_FLAGS="-static-libgcc -static-libstdc++" || return 1
    cmake --build "$WORK/pa-build" || return 1
    find "$WORK/pa-build" -maxdepth 1 \( -name '*.dll' -o -name '*.a' \)
}

collect() {
    local dll
    dll="$(find "$WORK/pa-build" -maxdepth 1 -name '*portaudio*.dll' | head -n 1)"
    [ -n "$dll" ] || { echo "no portaudio DLL was built"; return 1; }
    # norns.exe imports "libportaudio-2.dll" (the MSYS2 name): the loader goes by the file name, so this DLL takes its place
    cp "$dll" "$OUT/libportaudio-2.dll"
    ls -l "$OUT/libportaudio-2.dll"
    # the DLL must really contain the ASIO host API and must not need the C++ runtime next to it
    if strings -a "$OUT/libportaudio-2.dll" | grep -q -E "ASIO|asio"; then echo "found: ASIO in the DLL"; else echo "NOT FOUND: ASIO in the DLL (the build did not include it)"; return 1; fi
    if command -v objdump > /dev/null 2>&1; then
        echo "imports: $(objdump -p "$OUT/libportaudio-2.dll" | awk '/DLL Name/ { print $3 }' | tr '\n' ' ')"
        if objdump -p "$OUT/libportaudio-2.dll" | grep -q -E "DLL Name: (libstdc\+\+|libgcc)"; then echo "the DLL needs libstdc++ or libgcc DLLs next to it: they would have to be shipped"; return 1; fi
    fi
}

m0_init
m0_run m3-asio-sources sources || exit 0
m0_run m3-asio-source-archives source_archives
m0_run m3-asio-build build || exit 0
m0_run m3-asio-collect collect
exit 0
