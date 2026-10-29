# sourced by tests: SuperCollider 3.14.1 from the packaged build tree (build/package/cache) without installing the package.
#   sc314_link_tree   link the build tree's class library where the packaged sclang looks for it (/opt/verdandi/supercollider/share/SuperCollider) when nothing is installed there; the
#                     folders are put back as they were by sc314_unlink_tree (call it from the trap). returns 1 if that is not possible
#   sc314_path_dir D  make folder D with sclang and scsynth of the build tree; export PATH and SC_PLUGIN_PATH so that the launcher starts 3.14.1. returns 1 if there is no build tree
SC314_LINKED=""
sc314_link_tree() {
    local repo="$1" base=/opt/verdandi/supercollider/share/SuperCollider d src
    src="$repo/build/package/cache/supercollider"
    [ -d "$src/SCClassLibrary" ] || return 1
    for d in SCClassLibrary HID_Support; do
        [ -d "$src/$d" ] || continue
        if [ -L "$base/$d" ] || [ -z "$(ls -A "$base/$d" 2> /dev/null)" ]; then
            rm -rf "${base:?}/$d" 2> /dev/null
            mkdir -p "$base" 2> /dev/null && ln -s "$src/$d" "$base/$d" 2> /dev/null && SC314_LINKED="$SC314_LINKED $base/$d"
        fi
    done
    # the sc3-plugins classes (SawDPW and the like): the package installs them under Extensions
    src="$repo/build/package/cache/sc3-plugins-install/share/SuperCollider/Extensions/SC3plugins"
    if [ -d "$src" ] && [ ! -e "$base/Extensions/SC3plugins" ]; then
        mkdir -p "$base/Extensions" 2> /dev/null && ln -s "$src" "$base/Extensions/SC3plugins" 2> /dev/null && SC314_LINKED="$SC314_LINKED $base/Extensions/SC3plugins"
    fi
    [ -e "$base/SCClassLibrary/Common" ]
}
sc314_unlink_tree() { local d; for d in $SC314_LINKED; do rm -f "$d"; case "$d" in */Extensions/*) ;; *) mkdir -p "$d" ;; esac; done; SC314_LINKED=""; } # an empty folder is what sclang itself makes there
sc314_path_dir() {
    local repo="$1" dir="$2" c="$1/build/package/cache"
    [ -x "$c/sc-build/lang/sclang" ] && [ -x "$c/sc-build/server/scsynth/scsynth" ] || return 1
    mkdir -p "$dir" && ln -sf "$c/sc-build/lang/sclang" "$dir/sclang" && ln -sf "$c/sc-build/server/scsynth/scsynth" "$dir/scsynth" || return 1
    export PATH="$dir:$PATH"
    export SC_PLUGIN_PATH="$c/sc-build/server/plugins:$c/sc3-plugins-install/lib/SuperCollider/plugins"
}
