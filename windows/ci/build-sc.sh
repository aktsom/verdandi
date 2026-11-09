#!/usr/bin/env bash
# windows/ci/build-sc.sh: SuperCollider 3.14.1 for Windows, built from source with MSVC and without Qt (M0a). the same recipe as SuperCollider's own CI (build_windows.yml of the source), reduced to what
# Verdandi needs: sclang and scsynth, the class library and the server plug-ins; no IDE, no help, no tests, no supernova, no readline. run on a Windows runner from a shell with the MSVC environment (the
# workflow sets it up) and Git Bash; it needs: git, cmake, vcpkg (VCPKG_INSTALLATION_ROOT), 7z, curl.
#   SC_TAG        Version-3.14.1
#   WITH_ASIO     1: build SuperCollider's PortAudio with ASIO (needs the Steinberg SDK; see docs/port/windows-plan.md, decision on the ASIO licence). default 0: WASAPI, DirectSound, MME only
#   WORK          where to build (default: ./m0-work)
#   M0_OUT        logs and status (see lib.sh); the install tree zip goes to $M0_OUT/sc-win64.zip
# the functions below are only called through m0_run (shellcheck cannot see that)
# shellcheck disable=SC2329
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=windows/ci/lib.sh
. "$HERE/lib.sh"
SC_TAG="${SC_TAG:-Version-3.14.1}"
WITH_ASIO="${WITH_ASIO:-0}"
WORK="${WORK:-$PWD/m0-work}"
mkdir -p "$WORK"
SRC="$WORK/sc-src"
BLD="$WORK/sc-build"
FFTW_DIR="${FFTW_DIR:-/c/Program Files/fftw}"

fetch_source() {
    [ -d "$SRC/.git" ] || git clone -c core.autocrlf=false --depth 1 --branch "$SC_TAG" --recurse-submodules --shallow-submodules https://github.com/supercollider/supercollider.git "$SRC"
    git -C "$SRC" describe --tags
}

# Verdandi patches to SuperCollider (windows/patches): the null audio driver (VERDANDI_NULL_AUDIO=1: scsynth runs without an audio device). the clone is made with autocrlf off so that the patch applies
apply_patches() {
    local p
    for p in "$HERE"/../patches/*.patch; do
        echo "applying $p"
        if git -C "$SRC" apply --check "$p"; then git -C "$SRC" apply "$p"; else echo "patch does not apply: $p"; return 1; fi
    done
}

install_vcpkg_libs() {
    local vcpkg="${VCPKG_INSTALLATION_ROOT:-/c/vcpkg}/vcpkg.exe"
    "$vcpkg" install libsndfile --triplet=x64-windows-release --overlay-triplets="$SRC/vcpkg/triplets"
}

# the prebuilt single-precision FFTW for Windows, and an import library for MSVC made from its .def (as SuperCollider's own CI does)
install_fftw() {
    mkdir -p "$FFTW_DIR"
    (
        cd "$FFTW_DIR" || exit 1
        curl -fL --retry 3 -o fftw.zip https://fftw.org/pub/fftw/fftw-3.3.5-dll64.zip || curl -fL --retry 3 -o fftw.zip ftp://ftp.fftw.org/pub/fftw/fftw-3.3.5-dll64.zip
        7z x fftw.zip -y > /dev/null
        lib.exe /machine:x64 /def:libfftw3f-3.def
        find . -maxdepth 1 -type f -name "libfftw3f*"
    )
}

install_asio() {
    # only when asked for (WITH_ASIO=1): SuperCollider's CMake looks for the SDK in external_libraries/portaudio/asiosdk. the SDK is a build input, never part of our repository or our artifacts
    local tmp="$WORK/asio"
    mkdir -p "$tmp"
    (cd "$tmp" && curl -fL --retry 3 -o asio.zip https://www.steinberg.net/asiosdk && 7z x asio.zip -y > /dev/null)
    shopt -s nocaseglob
    mv "$tmp"/asiosdk* "$SRC/external_libraries/portaudio/asiosdk"
    shopt -u nocaseglob
    find "$SRC/external_libraries/portaudio/asiosdk" -maxdepth 1 | head
}

configure() {
    VCPKG_ROOT="${VCPKG_INSTALLATION_ROOT:-/c/vcpkg}" cmake -S "$SRC" -B "$BLD" -G "Visual Studio 17 2022" -A x64 \
        -DCMAKE_BUILD_TYPE=Release -DVCPKG_TARGET_TRIPLET=x64-windows-release \
        -DSC_QT=OFF -DSC_IDE=OFF -DSC_ED=OFF -DSC_EL=OFF -DSC_VIM=OFF -DSUPERNOVA=OFF -DSC_ABLETON_LINK=OFF \
        -DINSTALL_HELP=OFF -DENABLE_TESTSUITE=OFF -DNO_LIBSNDFILE=OFF
}

build() {
    cmake --build "$BLD" --config Release --target install --parallel "${JOBS:-4}"
}

package_tree() {
    local tree="$BLD/Install/SuperCollider"
    [ -f "$tree/sclang.exe" ] && [ -f "$tree/scsynth.exe" ] || { echo "no sclang.exe / scsynth.exe in $tree"; find "$BLD/Install" -maxdepth 2 2> /dev/null; return 1; }
    find "$tree" -maxdepth 1 | head -40
    (cd "$BLD/Install" && 7z a -tzip "$M0_OUT/sc-win64.zip" SuperCollider > /dev/null)
    find "$M0_OUT" -maxdepth 1 -name sc-win64.zip -size +1k
}

m0_init
m0_run sc-source fetch_source || exit 1
m0_run sc-patch apply_patches || exit 1
m0_run sc-vcpkg-libs install_vcpkg_libs || exit 1
m0_run sc-fftw install_fftw || exit 1
if [ "$WITH_ASIO" = 1 ]; then m0_run sc-asio install_asio || exit 1; else m0_skip sc-asio "WITH_ASIO=0 (no ASIO in M0)"; fi
m0_run sc-configure configure || exit 1
m0_run sc-build build || exit 1
m0_run sc-package package_tree || exit 1
exit 0
