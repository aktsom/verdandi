#!/bin/bash
# builds the x86_64 mi-UGens pack (docs/port/phase-m35.md). ONE recipe for both users: linux/package.sh (the .deb, against the SuperCollider SOURCE it builds) and linux/build.sh (a checkout,
# against the headers of the installed SuperCollider). the pin is linux/mi-ugens.pin (v0.0.9 + the head of pull request 24, MiBeads); the seed (copy into the user's extension folder) is linux/mi-ugens-seed.sh.
#
#   mi-ugens-build.sh build <work dir> <SuperCollider dir> [--version <verdandi version>] [--map <prefix-map flags>]
#       <SuperCollider dir> needs include/ and common/ (a full source tree or the sparse headers clone: the build uses nothing else). leaves
#         <work>/mi-ugens-pack/mi-UGens           the stamped pack (the folder the tests and the seed use)
#         <work>/mi-ugens-pack/LICENSE-*          the licence texts
#       (the clone of the sources is <work>/mi-ugens, the build tree <work>/mi-ugens-build)
#   mi-ugens-build.sh checkout [<repo dir>]
#       what linux/build.sh runs for a checkout: the headers of the installed SuperCollider (linux/portedplugins-build.sh headers) + build into <repo>/build/linux/mi-ugens (the pack is
#       <that>/mi-ugens-pack/mi-UGens, where norns.sh looks); nothing is done when the pack there is up to date (same serial and commit, same SuperCollider version). a failure
#       is a warning and exit 0: norns starts without the pack, only the scripts that use MiPlaits, MiRings, ... do not work.
#   nothing is downloaded at run time of norns; the build needs the network once (git clone of the pinned tag and of pull request 24)
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_DEFAULT="$(cd "$HERE/.." && pwd)"
. "$HERE/tools-hint.sh"

say() { echo "mi-ugens: $*"; }
die() { echo "mi-ugens: $*" >&2; exit 1; }

cmd_build() {
    local work="$1" sc="$2" version="dev" map=""
    shift 2
    while [ $# -gt 0 ]; do
        case "$1" in
            --version) version="$2"; shift 2 ;;
            --map) map="$2"; shift 2 ;;
            *) die "unknown argument $1" ;;
        esac
    done
    . "$HERE/mi-ugens.pin"
    say "mi-UGens $MI_UGENS_TAG + pull request $MI_UGENS_PR ($MI_UGENS_PR_COMMIT)"
    mkdir -p "$work"
    local src="$work/mi-ugens" pack="$work/mi-ugens-pack/mi-UGens" b="$work/mi-ugens-build"
    [ -f "$sc/include/plugin_interface/SC_PlugIn.h" ] || die "no SuperCollider headers in $sc (linux/portedplugins-build.sh headers <dir>, or the SuperCollider source)"
    if [ ! -d "$src/.git" ]; then
        git clone -q "$MI_UGENS_REPO" "$src"
    fi
    git -C "$src" fetch -q origin "$MI_UGENS_COMMIT" 2> /dev/null || git -C "$src" fetch -q --tags origin
    git -C "$src" fetch -q origin "pull/$MI_UGENS_PR/head" 2> /dev/null || true
    git -C "$src" checkout -q -f "$MI_UGENS_COMMIT"
    [ "$(git -C "$src" rev-parse HEAD)" = "$MI_UGENS_COMMIT" ] || die "$MI_UGENS_COMMIT is not what $MI_UGENS_TAG points to"
    git -C "$src" cat-file -e "$MI_UGENS_PR_COMMIT^{commit}" 2> /dev/null || die "pull request $MI_UGENS_PR head $MI_UGENS_PR_COMMIT not fetched"
    git -C "$src" -c user.name=build -c user.email=build@localhost -c commit.gpgsign=false merge -q --no-edit "$MI_UGENS_PR_COMMIT" > /dev/null
    git -C "$src" submodule update -q --init --recursive
    rm -rf "${b:?}" "$work/mi-ugens-install" "$work/mi-ugens-pack"
    cmake -S "$src" -B "$b" -G Ninja -DSC_PATH="$sc" -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$work/mi-ugens-install" -DCMAKE_C_FLAGS="$map" -DCMAKE_CXX_FLAGS="-std=c++17 $map" > "$work/cmake-configure.log" 2>&1 \
        || { tail -n 20 "$work/cmake-configure.log" >&2; die "cmake could not configure mi-UGens (log: $work/cmake-configure.log)"; }
    # the libsamplerate that MiBraids links has to exist first (a parallel build races on it)
    cmake --build "$b" --target samplerate > "$work/build.log" 2>&1 || { tail -n 20 "$work/build.log" >&2; die "libsamplerate did not build (log: $work/build.log)"; }
    cmake --build "$b" -j "${JOBS:-$(nproc)}" >> "$work/build.log" 2>&1 || { tail -n 20 "$work/build.log" >&2; die "mi-UGens did not build (log: $work/build.log)"; }
    cmake --install "$b" > "$work/install.log" 2>&1 || die "mi-UGens did not install (log: $work/install.log)"
    mkdir -p "$work/mi-ugens-pack"
    cp -a "$work/mi-ugens-install/mi-UGens" "$pack"
    local f
    for f in "$pack"/*.so; do [ -f "$f" ] || continue; strip --strip-unneeded "$f" 2> /dev/null || true; done
    [ -f "$pack/MiPlaits.so" ] && [ -f "$pack/MiRings.so" ] && [ -f "$pack/MiBeads.so" ] && [ -f "$pack/Classes/MiBeads.sc" ] || die "the build did not make MiPlaits.so, MiRings.so, MiBeads.so and the classes (log: $work/build.log)"
    # help files are most of the size and unused at runtime
    rm -rf "${pack:?}/HelpSource"
    cp "$src/gpl-3.0.md" "$work/mi-ugens-pack/LICENSE-GPL-3.0.md"
    cp "$src/eurorack/LICENSE.txt" "$work/mi-ugens-pack/LICENSE-eurorack-MIT.txt"
    cp "$src/projects/MiBraids/libsamplerate/COPYING" "$work/mi-ugens-pack/LICENSE-libsamplerate-BSD-2.txt"
    "$HERE/mi-ugens-seed.sh" stamp "$pack" "$MI_UGENS_SERIAL" "$MI_UGENS_COMMIT" "$(date -u -d "@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y-%m-%d)" "$version" "$MI_UGENS_TAG + pull request $MI_UGENS_PR $MI_UGENS_PR_COMMIT"
    say "pack $pack: $(ls "$pack"/*.so | wc -l) plug-ins, $(du -sk "$pack" | cut -f1) KB"
}

cmd_checkout() {
    local repo="${1:-$REPO_DEFAULT}"
    . "$HERE/mi-ugens.pin"
    local work="$repo/build/linux/mi-ugens" tag want
    tag="$("$HERE/portedplugins-build.sh" sc-tag)"
    want="serial=$MI_UGENS_SERIAL commit=$MI_UGENS_COMMIT pr=$MI_UGENS_PR_COMMIT sc=$tag"
    if [ -f "$work/mi-ugens-pack/mi-UGens/.verdandi-stamp" ] && [ "$(cat "$work/.built-for" 2> /dev/null)" = "$want" ]; then
        say "up to date ($want)"
        return 0
    fi
    missing_tools_warning "mi-UGens (MiPlaits, MiRings, MiBeads, ...: scripts and mods that use them)" git cmake ninja c++ strip || return 0
    (
        "$HERE/portedplugins-build.sh" headers "$work/sc-headers" "$tag"
        cmd_build "$work" "$work/sc-headers" --version "$(cat "$repo/windows/VERSION" 2> /dev/null || echo dev)" --map "-ffile-prefix-map=$work=."
    ) || { echo "mi-ugens: WARNING: the mi-UGens pack (MiPlaits, MiRings, ...) was not built (see above); norns starts, but the scripts and mods that use those UGens will say they are missing. retry: linux/build.sh"; return 0; }
    echo "$want" > "$work/.built-for"
}

case "${1:-}" in
    build) shift; cmd_build "$@" ;;
    checkout) shift; cmd_checkout "$@" ;;
    *) echo "usage: $0 build <work> <sc dir> [--version v] [--map flags] | checkout [repo]" >&2; exit 2 ;;
esac
