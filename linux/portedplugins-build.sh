#!/bin/bash
# builds the PortedPlugins pack for Linux x86_64 (docs/port/phase-m29.md). the pin is linux/portedplugins.pin; the seed (copy into the user's extension folder) is linux/portedplugins-seed.sh.
#
#   portedplugins-build.sh build <work dir> <SuperCollider source dir> [--other-classes <dir>]... [--version <verdandi version>]
#       builds the pinned PortedPlugins against the SuperCollider headers (<source dir>/include and common are enough, the nova-simd submodule is not needed) and leaves
#         <work dir>/PortedPlugins                the stamped pack (Classes/*.sc, X_scsynth.so, licence texts, BUILD-REPORT.txt)
#         <work dir>/LICENSE-GPL-3.0.txt          the licence of the collection
#       each plug-in is built on its own (ninja -k 0): one that does not compile is listed in the report, the others are shipped. the pack must hold every library twins needs
#       (PORTED_TWINS_NEEDS: class and plug-in) or the build fails. a class that SuperCollider, sc3-plugins or another shipped pack already defines (the --other-classes folders,
#       searched for *.sc) is taken out of the pack and listed: sclang stops at a duplicate class.
#   portedplugins-build.sh headers <dir> [<SuperCollider tag>]
#       the SuperCollider headers only (include/ and common/, a sparse shallow clone: seconds) in <dir>; the tag defaults to the version of the installed scsynth, else 3.14.1
#   portedplugins-build.sh sc-tag
#       the tag of the installed SuperCollider (Version-3.13.0), the one cmd_headers takes by default; linux/mi-ugens-build.sh uses it too
#   portedplugins-build.sh checkout [<repo dir>]
#       what linux/build.sh runs for a checkout: headers + build into <repo>/build/linux/portedplugins (the pack is <that>/PortedPlugins, where norns.sh looks); nothing is done when the
#       pack there is up to date (same serial and commit, same SuperCollider version). a failure is a warning and exit 0: norns does not need twins to start.
#   nothing is downloaded at run time of norns; the build needs the network (git clone of the pinned tag, cmake's CPM download)
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_DEFAULT="$(cd "$HERE/.." && pwd)"
. "$HERE/portedplugins.pin"
. "$HERE/tools-hint.sh"

say() { echo "portedplugins: $*"; }
die() { echo "portedplugins: $*" >&2; exit 1; }

# the version of the installed SuperCollider server as a tag name (Version-3.13.0), else the one Verdandi's own package is built against
sc_tag_of_installed() {
    local v
    v="$(scsynth -v 2> /dev/null | sed -n 's/^scsynth \([0-9][0-9.]*\).*/\1/p' | head -n 1)"
    if [ -n "$v" ] && git ls-remote --exit-code --tags https://github.com/supercollider/supercollider.git "refs/tags/Version-$v" > /dev/null 2>&1; then
        echo "Version-$v"
    else
        echo "Version-3.14.1"
    fi
}

cmd_headers() {
    local dir="$1" tag="${2:-$(sc_tag_of_installed)}"
    if [ -f "$dir/include/plugin_interface/SC_PlugIn.h" ] && [ "$(cat "$dir/.sc-tag" 2> /dev/null)" = "$tag" ]; then
        say "SuperCollider headers $tag are already in $dir"
        return 0
    fi
    rm -rf "${dir:?}"
    mkdir -p "$dir"
    git clone -q --depth 1 --branch "$tag" --filter=blob:none --sparse https://github.com/supercollider/supercollider.git "$dir"
    git -C "$dir" sparse-checkout set include common
    [ -f "$dir/include/plugin_interface/SC_PlugIn.h" ] || die "the SuperCollider headers are not in $dir after the clone of $tag"
    echo "$tag" > "$dir/.sc-tag"
    say "SuperCollider headers $tag in $dir"
}

# the class names (Foo : ... / + Foo) a folder defines
defined_classes() {
    find "$@" -name '*.sc' -type f 2> /dev/null | xargs -r sed -n -e 's/^\([A-Z][A-Za-z0-9_]*\)[ \t]*:.*/\1/p' -e 's/^\([A-Z][A-Za-z0-9_]*\)[ \t]*{.*/\1/p' 2> /dev/null | sort -u
}

cmd_build() {
    local work="$1" sc="$2"
    shift 2
    local others=() version="dev"
    while [ $# -gt 0 ]; do
        case "$1" in
            --other-classes) others+=("$2"); shift 2 ;;
            --version) version="$2"; shift 2 ;;
            *) die "unknown argument $1" ;;
        esac
    done
    [ -f "$sc/include/plugin_interface/SC_PlugIn.h" ] || die "no SuperCollider headers in $sc (portedplugins-build.sh headers <dir>)"
    mkdir -p "$work"
    local src="$work/src" b="$work/build" inst="$work/install" pack="$work/PortedPlugins" report="$work/BUILD-REPORT.txt"
    if [ ! -d "$src/.git" ]; then
        git clone -q --depth 1 --branch "$PORTED_TAG" --recurse-submodules --shallow-submodules "$PORTED_REPO" "$src"
    fi
    [ "$(git -C "$src" rev-parse HEAD)" = "$PORTED_COMMIT" ] || die "$PORTED_TAG is not $PORTED_COMMIT in $src (the pin is wrong or the tag moved)"
    rm -rf "${b:?}" "${inst:?}" "${pack:?}"
    cmake -S "$src" -B "$b" -G Ninja -DSC_PATH="$sc" -DCMAKE_BUILD_TYPE=Release -DNATIVE=OFF -DCMAKE_INSTALL_PREFIX="$inst" \
        -DCMAKE_C_FLAGS="-ffile-prefix-map=$work=." -DCMAKE_CXX_FLAGS="-ffile-prefix-map=$work=." > "$work/cmake-configure.log" 2>&1 \
        || { tail -n 20 "$work/cmake-configure.log" >&2; die "cmake could not configure PortedPlugins (log: $work/cmake-configure.log)"; }
    # each plug-in on its own: -k 0 goes on after a failure
    ninja -C "$b" -k 0 > "$work/ninja.log" 2>&1 || say "some plug-ins did not compile (the report lists them)"
    ninja -C "$b" install > "$work/ninja-install.log" 2>&1 || true
    [ -d "$inst/PortedPlugins" ] || die "PortedPlugins was not installed (log: $work/ninja.log)"
    cp -a "$inst/PortedPlugins" "$pack"
    rm -rf "${pack:?}/HelpSource"
    local f
    for f in "$pack"/*.so; do
        [ -f "$f" ] || continue
        strip --strip-unneeded "$f" 2> /dev/null || true
    done
    # the classes that something else already defines are taken out (sclang stops at a duplicate class)
    local taken=""
    if [ ${#others[@]} -gt 0 ]; then
        local c
        defined_classes "${others[@]}" > "$work/other-classes.txt"
        for f in "$pack"/Classes/*.sc; do
            [ -f "$f" ] || continue
            c="$(basename "$f" .sc)"
            if grep -qx "$c" "$work/other-classes.txt"; then
                rm -f "${f:?}"
                taken="$taken $c"
            fi
        done
    fi
    # twins needs these: the class file and the plug-in
    local need missing=""
    for need in $PORTED_TWINS_NEEDS; do
        [ -f "$pack/Classes/$need.sc" ] && [ -f "$pack/${need}_scsynth.so" ] || missing="$missing $need"
    done
    [ -z "$missing" ] || die "the pack lacks what twins needs:$missing (see $work/ninja.log)"
    # licences: the collection's own and every licence file inside the sources of the plug-ins
    cp "$src/LICENSE" "$work/LICENSE-GPL-3.0.txt"
    mkdir -p "$pack/licenses"
    cp "$src/LICENSE" "$pack/licenses/LICENSE-GPL-3.0.txt"
    (cd "$src/plugins" && find . \( -iname 'LICENSE*' -o -iname 'COPYING*' \) -type f | sort) | while IFS= read -r f; do
        mkdir -p "$pack/licenses/$(dirname "$f")"
        cp "$src/plugins/$f" "$pack/licenses/$f"
    done
    {
        echo "PortedPlugins for Linux x86_64, built for the SuperCollider headers in $(cat "$sc/.sc-tag" 2> /dev/null || echo "$sc") by Verdandi."
        echo "Source (GPL-3.0): $PORTED_REPO at revision $PORTED_COMMIT (tag $PORTED_TAG)."
        echo "The pin and the build are linux/portedplugins.pin and linux/portedplugins-build.sh in the Verdandi source; the plug-ins are unchanged."
    } > "$pack/SOURCE-OFFER.txt"
    local built notbuilt targets
    built="$(cd "$pack" && ls *_scsynth.so 2> /dev/null | sed 's/_scsynth\.so$//' | sort | tr '\n' ' ')"
    targets="$(sed -n 's/^-- Added server plugin target \(.*\)_scsynth$/\1/p' "$work/cmake-configure.log" | sort -u)"
    notbuilt=""
    for need in $targets; do
        [ -f "$pack/${need}_scsynth.so" ] || notbuilt="$notbuilt $need"
    done
    {
        echo "built: $built"
        echo "not built:${notbuilt:- none}"
        echo "classes taken out (another pack or SuperCollider defines them):${taken:- none}"
        echo "twins needs: $PORTED_TWINS_NEEDS (all present: class and plug-in)"
    } > "$report"
    cp "$report" "$pack/BUILD-REPORT.txt"
    "$HERE/portedplugins-seed.sh" stamp "$pack" "$PORTED_SERIAL" "$PORTED_COMMIT" "$(date -u -d "@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y-%m-%d)" "$version" "$PORTED_TAG of $PORTED_REPO"
    say "pack $pack: $(echo $built | wc -w) plug-ins, $(du -sk "$pack" | cut -f1) KB; not built:${notbuilt:- none}; classes taken out:${taken:- none}"
}

cmd_checkout() {
    local repo="${1:-$REPO_DEFAULT}"
    local work="$repo/build/linux/portedplugins" sc tag want
    tag="$(sc_tag_of_installed)"
    want="serial=$PORTED_SERIAL commit=$PORTED_COMMIT sc=$tag"
    if [ -f "$work/PortedPlugins/.verdandi-stamp" ] && [ "$(cat "$work/.built-for" 2> /dev/null)" = "$want" ]; then
        say "up to date ($want)"
        return 0
    fi
    missing_tools_warning "the PortedPlugins pack (the libraries the script twins asks for)" git cmake ninja c++ strip || return 0
    sc="$work/sc-headers"
    (
        cmd_headers "$sc" "$tag"
        local others=()
        local d
        for d in /usr/share/SuperCollider /usr/local/share/SuperCollider; do
            [ -d "$d" ] && others+=(--other-classes "$d")
        done
        cmd_build "$work" "$sc" "${others[@]}" --version "$(cat "$repo/windows/VERSION" 2> /dev/null || echo dev)"
    ) || { echo "portedplugins: WARNING: the PortedPlugins pack (twins' libraries) was not built (see above); norns works without it"; return 0; }
    echo "$want" > "$work/.built-for"
}

case "${1:-}" in
    headers) shift; cmd_headers "$@" ;;
    sc-tag) sc_tag_of_installed ;;
    build) shift; cmd_build "$@" ;;
    checkout) shift; cmd_checkout "$@" ;;
    *) echo "usage: $0 build <work> <sc source> [--other-classes dir]... | headers <dir> [tag] | checkout [repo]" >&2; exit 2 ;;
esac
