#!/bin/bash
# Verdandi on Linux: build the .deb (docs/port/packaging.md, Gate B).
#
# usage: linux/package.sh sc            SuperCollider 3.14.1 (no Qt) and sc3-plugins, staged for /opt/verdandi
#        linux/package.sh maiden        maiden, built by linux/maiden-build.sh
#        linux/package.sh tree          the program tree and the files around it
#        linux/package.sh deb           control files, privacy scan, the .deb
#        linux/package.sh all           sc, maiden, tree, deb (norns itself must be built: linux/build.sh)
#        linux/package.sh clean-root    all of it in a fresh Ubuntu 24.04 root (debootstrap, needs root); the root has its own
#                                       root user and none of the account that starts it; the root is removed after a good build
#                                       (PACKAGE_KEEP_ROOT=1 keeps it; a failed build always keeps it)
#        linux/package.sh check FILE    metadata and privacy checks of a built .deb
# output: build/package/verdandi_<version>_<arch>.deb (clean-root: build/package/clean-root/). every command but check keeps its whole
# output in build/package/package-<command>.log and says on failure which stage failed
# environment (optional): PACKAGE_MAINTAINER (default: a neutral project identity), PACKAGE_PRIVACY_EXTRA
# (extra words that must not appear in the package, space separated), SOURCE_DATE_EPOCH, JOBS.
#
# the package holds: /opt/verdandi (norns, SuperCollider, maiden, libmonome, licences), /usr/bin/verdandi,
# a desktop entry, an icon and a udev rule for monome devices. nothing is written outside those.

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
PREFIX=/opt/verdandi
OUT="${PACKAGE_OUT:-$REPO/build/package}"
CACHE="$OUT/cache"
STAGE="$OUT/stage"
JOBS="${JOBS:-$(nproc)}"

# pinned: the same versions as macos/setup-deps.sh, so that both ports run the same engines
SC_TAG=Version-3.14.1
SC3_PLUGINS_COMMIT=b80a41b731922feac7755df5ba359d14dfb8f4d9
LIBMONOME_VERSION=1.4.9
MAINTAINER="${PACKAGE_MAINTAINER:-Verdandi packagers <verdandi-packaging@localhost.invalid>}"

# the stage that is running, said again if the script stops (and where the whole log is)
STAGE_NOW="start"
say() { STAGE_NOW="$*"; echo "== $*"; }
die() { echo "package.sh: $*" >&2; exit 1; }
on_exit() {
    local rc=$?
    if [ $rc -ne 0 ] && [ "${1:-}" != check ]; then
        echo "package.sh: FAILED (exit $rc) during: $STAGE_NOW" >&2
        [ -n "${PACKAGE_LOG:-}" ] && echo "package.sh: the whole log is in $PACKAGE_LOG" >&2
    fi
}
trap 'on_exit "${1:-}"' EXIT

# every command but check keeps its whole output in <out>/package-<command>.log (a second run overwrites it)
if [ -z "${PACKAGE_LOGGING:-}" ] && [ -n "${1:-}" ] && [ "${1:-}" != check ]; then
    mkdir -p "$OUT"
    export PACKAGE_LOGGING=1 PACKAGE_LOG="$OUT/package-$1.log"
    echo "package.sh: the log is $PACKAGE_LOG"
    trap - EXIT
    set +e
    bash "$0" "$@" 2>&1 | tee "$PACKAGE_LOG"
    exit "${PIPESTATUS[0]}"
fi

# git clones are done at a commit, with the submodules the build needs
clone_at() { # url dir commit
    [ -d "$2/.git" ] || { git clone -q "$1" "$2"; }
    git -C "$2" fetch -q --depth 1 origin "$3" 2>/dev/null || true
    git -C "$2" checkout -q "$3"
}

SC_PREFIX="$PREFIX/supercollider"
MAP="-ffile-prefix-map=$CACHE=. -ffile-prefix-map=$REPO=."

build_sc() {
    mkdir -p "$CACHE"
    say "SuperCollider $SC_TAG (jack, no Qt, no IDE) for $SC_PREFIX"
    # no Qt: the Ubuntu sclang pulls Qt5WebEngine (128 MB) for an IDE that norns does not use
    if [ ! -d "$CACHE/supercollider" ]; then
        git clone -q --depth 1 -b "$SC_TAG" --recurse-submodules --shallow-submodules \
            https://github.com/supercollider/supercollider.git "$CACHE/supercollider"
    fi
    if [ ! -x "$STAGE$SC_PREFIX/bin/sclang" ]; then
        # SuperCollider compiles its data path in (SC_DATA_DIR): the prefix has to be the final one
        cmake -S "$CACHE/supercollider" -B "$CACHE/sc-build" -G Ninja -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_INSTALL_PREFIX="$SC_PREFIX" -DCMAKE_INSTALL_RPATH='$ORIGIN/../lib' \
            -DAUDIOAPI=jack -DSC_QT=OFF -DSC_IDE=OFF -DSUPERNOVA=OFF -DSC_EL=OFF -DSC_VIM=OFF -DSC_ED=OFF \
            -DNO_X11=ON -DSC_ABLETON_LINK=OFF -DINSTALL_HELP=OFF -DENABLE_TESTSUITE=OFF \
            -DCMAKE_C_FLAGS="$MAP" -DCMAKE_CXX_FLAGS="$MAP"
        cmake --build "$CACHE/sc-build" -j "$JOBS"
        DESTDIR="$STAGE" cmake --install "$CACHE/sc-build"
    fi
    # without the Qt IDE the install skips the class library (macos/setup-deps.sh does the same)
    D="$STAGE$SC_PREFIX/share/SuperCollider"
    [ -d "$D/SCClassLibrary" ] || cp -R "$CACHE/supercollider/SCClassLibrary" "$D/"

    say "sc3-plugins $SC3_PLUGINS_COMMIT"
    PLUG="$STAGE$SC_PREFIX/lib/SuperCollider/plugins"
    # the plug-in binaries (.so, lib/SuperCollider/plugins) and the classes (share/SuperCollider/Extensions/SC3plugins)
    # both come from the install step: a binary-less SC3plugins folder loads its classes and then fails at the first UGen
    if [ ! -d "$D/Extensions/SC3plugins" ] || [ ! -f "$PLUG/SLUGens.so" ]; then
        [ -d "$CACHE/sc3-plugins" ] || git clone -q https://github.com/supercollider/sc3-plugins.git "$CACHE/sc3-plugins"
        git -C "$CACHE/sc3-plugins" checkout -q "$SC3_PLUGINS_COMMIT"
        git -C "$CACHE/sc3-plugins" submodule update -q --init --recursive
        # `0<=bufnum<= n` is always true, and a current compiler rejects it; the intended bounds check
        sed -i 's/	if(0<=bufnum<= world->mNumSndBufs) {/	if(bufnum < (int)world->mNumSndBufs) {/' \
            "$CACHE/sc3-plugins/source/NCAnalysisUGens/SMS.cpp"
        cmake -S "$CACHE/sc3-plugins" -B "$CACHE/sc3-plugins-build" -G Ninja -DSC_PATH="$CACHE/supercollider" \
            -DCMAKE_BUILD_TYPE=Release -DSUPERNOVA=OFF -DQUARKS=OFF -DSCX=ON \
            -DCMAKE_INSTALL_PREFIX="$SC_PREFIX" -DCMAKE_C_FLAGS="$MAP" -DCMAKE_CXX_FLAGS="$MAP"
        cmake --build "$CACHE/sc3-plugins-build" -j "$JOBS"
        DESTDIR="$STAGE" cmake --install "$CACHE/sc3-plugins-build"
        # help files are most of the size and unused at runtime
        find "$D/Extensions/SC3plugins" -type d \( -name HelpSource -o -name help \) -prune -exec rm -rf {} +
    fi
    [ -f "$PLUG/SLUGens.so" ] || die "sc3-plugins: no plug-in binaries in $PLUG"
}

# maiden is built by its own script into a scratch norns home, then copied into the tree
build_maiden() {
    say "maiden"
    local h="$CACHE/maiden-home"
    mkdir -p "$h"
    NORNS_HOME="$h" MAIDEN_BUILD_DIR="$CACHE/maiden-build" "$REPO/linux/maiden-build.sh"
    [ -x "$h/maiden/maiden" ] || die "maiden was not built"
    rm -rf "$STAGE$PREFIX/maiden"
    mkdir -p "$STAGE$PREFIX"
    cp -a "$h/maiden" "$STAGE$PREFIX/maiden"
    rm -f "$STAGE$PREFIX/maiden/.verdandi-build"
}
# libmonome with the pty patch (linux/patches), built for the final prefix: it opens its protocol modules from
# <prefix>/lib/monome/protocol_*.so, a path compiled in, so the copy in /usr/local would not be found
build_libmonome() {
    say "libmonome $LIBMONOME_VERSION + pty serial patch for $PREFIX"
    if [ ! -f "$STAGE$PREFIX/lib/monome/protocol_mext.so" ]; then
        rm -rf "$CACHE/libmonome"
        git clone -q --depth 1 --branch "v$LIBMONOME_VERSION" https://github.com/monome/libmonome.git "$CACHE/libmonome"
        (cd "$CACHE/libmonome" && git apply "$REPO/linux/patches/libmonome-pty-serial.patch" &&
            python3 ./waf configure --prefix="$PREFIX" --libdir="$PREFIX/lib" &&
            python3 ./waf build -j "$JOBS" && python3 ./waf install --destdir="$STAGE")
    fi
    # only the library and its protocol modules; no headers, tools or man pages
    rm -rf "$STAGE$PREFIX/include" "$STAGE$PREFIX/bin" "$STAGE$PREFIX/share" "$STAGE$PREFIX/lib/pkgconfig"
    [ -f "$STAGE$PREFIX/lib/monome/protocol_mext.so" ] || die "libmonome: no protocol modules in the stage"
}

# the program tree: the same layout as a checkout, because linux/norns.sh and matron look for these paths
build_tree() {
    say "program tree in $STAGE$PREFIX"
    local T="$STAGE$PREFIX" f
    for f in build/norns/norns build/ws-wrapper/ws-wrapper build/maiden-repl/maiden-repl \
        build/linux/audio_devices build/linux/plugin_arch_check; do
        [ -x "$REPO/$f" ] || die "$f is not built (linux/build.sh)"
        install -D -m 755 "$REPO/$f" "$T/$f"
    done
    # the dev repo's own folders. nothing from macos/ , docs/ or the build folders except what runs
    rm -rf "$T/lua" "$T/sc" "$T/resources" "$T/doc" "$T/linux"
    cp -a "$REPO/lua" "$REPO/sc" "$REPO/resources" "$REPO/doc" "$T/"
    mkdir -p "$T/update" "$T/linux"
    cp "$REPO/update/version.txt" "$T/update/"
    cp "$REPO/matronrc.lua" "$T/" 2>/dev/null || true
    install -m 755 "$REPO/linux/norns.sh" "$T/linux/norns.sh"
    cp -a "$REPO/linux/shims" "$REPO/linux/manual" "$T/linux/"
    # the marker that makes linux/norns.sh use the installed layout (home in ~/Verdandi, program tree read-only)
    echo "installed by the verdandi package" > "$T/INSTALLED"
    # editors' and test leftovers
    find "$T" \( -name '*.orig' -o -name '*.rej' -o -name '.git*' -o -name '__pycache__' \) -prune -exec rm -rf {} + 2>/dev/null || true
    # reproducible modes: files readable by all, programs executable, nothing writable by group or others
    find "$T" -type d -exec chmod 755 {} +
    find "$T" -type f ! -perm -u+x -exec chmod 644 {} +
    find "$T" -type f -perm -u+x -exec chmod 755 {} +
    # ELF files: strip (the compiler's paths in debug info are the usual leak of the build user's folders)
    find "$STAGE" -type f -exec sh -c 'head -c4 "$1" | grep -q "^.ELF"' _ {} \; -print | while read -r f; do
        strip --strip-unneeded "$f" 2>/dev/null || true
    done

    # the places the desktop looks in
    install -D -m 755 /dev/stdin "$STAGE/usr/bin/verdandi" <<WRAP
#!/bin/sh
exec $PREFIX/linux/norns.sh "\$@"
WRAP
    install -D -m 644 /dev/stdin "$STAGE/usr/share/applications/verdandi.desktop" <<'DESK'
[Desktop Entry]
Type=Application
Name=Verdandi
GenericName=norns on the desktop
Comment=The norns sound computer on your desktop
Exec=verdandi
Icon=verdandi
Terminal=false
Categories=AudioVideo;Audio;Music;
Keywords=norns;monome;grid;arc;
DESK
    install -D -m 644 "$REPO/macos/norns-icon.png" "$STAGE/usr/share/icons/hicolor/256x256/apps/verdandi.png"
    install -D -m 644 "$REPO/linux/udev/70-verdandi-monome.rules" "$STAGE/usr/lib/udev/rules.d/70-verdandi-monome.rules"
    build_licenses
}

# licence texts, unaltered, from the sources that were built; the copyright file points here
build_licenses() {
    local L="$STAGE$PREFIX/licenses" f
    rm -rf "$L"
    mkdir -p "$L/supercollider" "$L/sc3-plugins" "$L/libmonome" "$L/softcut" "$L/fonts" "$L/third-party"
    install -m 644 "$REPO/LICENSE.txt" "$L/norns-GPL-3.0.txt"
    install -m 644 "$REPO/crone/softcut/LICENSE.txt" "$L/softcut/LICENSE.txt"
    install -m 644 "$CACHE/supercollider/COPYING" "$L/supercollider/COPYING"
    install -m 644 "$CACHE/sc3-plugins/license.txt" "$L/sc3-plugins/license.txt"
    [ -f "$CACHE/libmonome/COPYRIGHT" ] || [ -f "$CACHE/libmonome/COPYING" ] || die "libmonome source (licence) missing: run '$0 all'"
    for f in COPYRIGHT COPYING; do [ -f "$CACHE/libmonome/$f" ] && install -m 644 "$CACHE/libmonome/$f" "$L/libmonome/$f"; done
    for f in resources/roboto-LICENSE.txt resources/vera-LICENSE.txt resources/bmp/bmp-LICENSE.txt resources/bmp/tom-thumb-LICENSE.txt; do
        install -m 644 "$REPO/$f" "$L/fonts/$(basename "$f")"
    done
    for f in third-party/link/LICENSE.md third-party/lua-cjson/LICENSE third-party/concurrentqueue/LICENSE.md \
        third-party/readerwriterqueue/LICENSE.md; do
        [ -f "$REPO/$f" ] && install -m 644 "$REPO/$f" "$L/third-party/$(echo "$f" | cut -d/ -f2)-$(basename "$f")"
    done
    for f in "$CACHE"/maiden-home/maiden/LICENSE*; do [ -f "$f" ] && install -D -m 644 "$f" "$L/maiden/$(basename "$f")"; done
    install -m 644 "$REPO/docs/port/DEPS.md" "$L/DEPS.md"
    cat > "$L/SOURCES.txt" <<SRC
Verdandi is free software (GPL-3.0). The source of every part of this package is available:

  Verdandi (norns, matron, crone, softcut, the Linux port): the source repository this package was built from, at
      commit $(git -C "$REPO" rev-parse HEAD)
  SuperCollider $SC_TAG (no Qt, no IDE):  https://github.com/supercollider/supercollider  (tag $SC_TAG)
  sc3-plugins:                            https://github.com/supercollider/sc3-plugins    (commit $SC3_PLUGINS_COMMIT)
  libmonome $LIBMONOME_VERSION + the pty patch:   https://github.com/monome/libmonome (tag v$LIBMONOME_VERSION),
      the patch is linux/patches/libmonome-pty-serial.patch of the Verdandi source
  maiden (patched by linux/patches and macos/patches/maiden-host-flag.patch of the Verdandi source):
      https://github.com/monome/maiden  (commit 2e64f7d59284962ac68055dd556e3fd8515462f8)

The build instructions are linux/package.sh of the Verdandi source. On request, the same source is available on
physical media or by download from whoever gave you this package.

Not a legal opinion; the fonts of the norns screen have an open licence question, see DEPS.md.
SRC
    chmod 644 "$L/SOURCES.txt"
}

# ---- the package ----
EPOCH="${SOURCE_DATE_EPOCH:-$(git -C "$REPO" log -1 --format=%ct)}"
export SOURCE_DATE_EPOCH="$EPOCH"
VERSION="0.1~git$(date -u -d "@$EPOCH" +%Y%m%d).$(git -C "$REPO" rev-parse --short HEAD)"
ARCH="$(dpkg --print-architecture)"
DEB="$OUT/verdandi_${VERSION}_${ARCH}.deb"

# words that identify the person who builds: the user name, the real name of the account, the git identity, the owner of the
# remote and the folder names of this checkout. never printed, only counted. words that every machine has are skipped
identity_words() {
    {
XX
        git config user.name | tr ' ' '\n'
        git config user.email | tr '@.' '\n\n'
        git -C "$REPO" config user.name | tr ' ' '\n'
        git -C "$REPO" config user.email | tr '@.' '\n\n'
        git -C "$REPO" remote get-url origin 2>/dev/null | tr -c 'A-Za-z0-9_.-' '\n'
        basename "${HOME:-/}"
        echo "${PACKAGE_PRIVACY_EXTRA:-}" | tr ' ' '\n'
    } 2>/dev/null | tr 'A-Z' 'a-z' | grep -E '^[a-z0-9_.-]{4,}$' |
        grep -vxE 'root|user|users|home|claude|anthropic|noreply|localhost|invalid|example|github|https|http|git|verdandi|norns|monome|ha1dcre|build|admin|ubuntu|debian|nobody|local_proxy|127.0.0.1|local|proxy|.*\.(com|org|net)' | sort -u
}

privacy_scan() { # dir...: fail when any identity word is in any file name or content
    local w n=0 words d
    words="$(identity_words)"
    for d in "$@"; do
        while read -r w; do
            [ -n "$w" ] || continue
            if find "$d" -iname "*$w*" 2>/dev/null | grep -q . || grep -raliF -e "$w" "$d" 2>/dev/null | grep -q .; then
                n=$((n + 1))
                echo "privacy scan: an identity word of the builder is in $d (word number $n of this scan; not printed)." >&2
                grep -raliF -e "$w" "$d" 2>/dev/null | head -3 >&2
            fi
        done <<< "$words"
    done
    [ "$n" -eq 0 ] || die "privacy scan failed: build in a neutral folder (linux/package.sh clean-root) or set PACKAGE_MAINTAINER; remove the files above"
    echo "privacy scan: $(echo "$words" | grep -c .) identity words of the builder, none found in $*"
}

build_deb() {
    say "control files and the .deb $DEB"
    [ -x "$STAGE$PREFIX/supercollider/bin/sclang" ] || die "run '$0 sc' first"
    [ -x "$STAGE$PREFIX/build/norns/norns" ] || die "run '$0 tree' first"
    local C="$OUT/control" D="$STAGE/DEBIAN" doc="$STAGE/usr/share/doc/verdandi" f
    rm -rf "$C" "$D" "$doc"
    mkdir -p "$C/debian" "$D" "$doc"
    # Depends from the libraries of every binary
    printf 'Source: verdandi\n\nPackage: verdandi\nArchitecture: any\n' > "$C/debian/control"
    local bins
    bins="$(find "$STAGE" -type f \( -perm -u+x -o -name '*.so' -o -name '*.so.*' \) -exec sh -c 'head -c4 "$1" | grep -q "^.ELF"' _ {} \; -print |
        sed 's/^/-e/' | tr '\n' ' ')"
    # shellcheck disable=SC2086
    SHL="$(cd "$C" && dpkg-shlibdeps -O --ignore-missing-info -l"$STAGE$PREFIX/lib" -l"$STAGE$PREFIX/supercollider/lib" \
        $bins 2>/dev/null | sed -n 's/^shlibs:Depends=//p')"
    [ -n "$SHL" ] || die "dpkg-shlibdeps found no dependencies"
    # sound server (the host's libjack: pw-jack works), a file dialog, the browser opener
    DEPENDS="$SHL, pipewire-jack | jackd2, zenity | xdg-desktop-portal, xdg-utils"
    local size
    size="$(du -sk --exclude=DEBIAN "$STAGE" | cut -f1)"
    cat > "$D/control" <<CTL
Package: verdandi
Version: $VERSION
Architecture: $ARCH
Maintainer: $MAINTAINER
Installed-Size: $size
Depends: $DEPENDS
Section: sound
Priority: optional
Description: norns sound computer on the desktop
 Verdandi runs the norns scripts, with the screen, keys and encoders in a
 window, on Linux. Includes SuperCollider and the norns audio engines, the maiden
 web editor, and virtual or real monome grids and arcs.
 .
 Free software (GPL-3.0). The licences and the source locations of every part are
 in /opt/verdandi/licenses.
CTL
    cat > "$D/postinst" <<'POST'
#!/bin/sh
set -e
# the udev rule for monome devices takes effect for devices plugged in from now on; devices already plugged in are asked again
if [ "$1" = configure ] && command -v udevadm >/dev/null 2>&1; then
    udevadm control --reload-rules >/dev/null 2>&1 || true
    udevadm trigger --subsystem-match=tty --action=add >/dev/null 2>&1 || true
fi
exit 0
POST
    cat > "$D/postrm" <<'POST'
#!/bin/sh
set -e
if { [ "$1" = remove ] || [ "$1" = purge ]; } && command -v udevadm >/dev/null 2>&1; then
    udevadm control --reload-rules >/dev/null 2>&1 || true
fi
exit 0
POST
    chmod 755 "$D/postinst" "$D/postrm"
    (cd "$STAGE" && find opt usr -type f -exec md5sum {} + | sort -k2 > DEBIAN/md5sums)

    # copyright file (machine readable) and changelog
    cat > "$doc/copyright" <<CPR
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: Verdandi (norns for the desktop)
Source: see /opt/verdandi/licenses/SOURCES.txt

Files: *
Copyright: the norns authors (monome), the Verdandi authors, the authors of the Linux port
License: GPL-3
 This package is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License
 version 3 as published by the Free Software Foundation. On Debian systems the full text is in
 /usr/share/common-licenses/GPL-3 and in /opt/verdandi/licenses/norns-GPL-3.0.txt.

Files: opt/verdandi/build/norns/*
Copyright: softcut authors (linked into norns), Ableton Link, lua-cjson, concurrentqueue, readerwriterqueue authors
License: GPL-3
 softcut: /opt/verdandi/licenses/softcut/LICENSE.txt. The other libraries: /opt/verdandi/licenses/third-party.

Files: opt/verdandi/supercollider/*
Copyright: the SuperCollider authors
License: GPL-3+
 See /opt/verdandi/licenses/supercollider/COPYING. sc3-plugins (GPL-2+, some parts under other terms) are in
 opt/verdandi/supercollider/lib/SuperCollider/plugins and share/SuperCollider/Extensions; see /opt/verdandi/licenses/sc3-plugins/license.txt.

Files: opt/verdandi/lib/*
Copyright: William Light and the libmonome authors
License: ISC
 See /opt/verdandi/licenses/libmonome/. The pty patch is part of the Verdandi source.

Files: opt/verdandi/maiden/*
Copyright: the maiden authors (monome)
License: GPL-3
 maiden's Go modules and web app packages carry their own licences (MIT, BSD, Apache-2.0, MPL-2.0); the list is in
 /opt/verdandi/licenses/DEPS.md and the texts in the sources named in /opt/verdandi/licenses/SOURCES.txt.

Files: opt/verdandi/resources/*
Copyright: see the licence files in /opt/verdandi/licenses/fonts
License: see-files
 The fonts norns.ttf, liquid.ttf, Particle.ttf and basis33.ttf have no licence file in the source; this question is open
 (DEPS.md) and has to be settled before the package goes to anyone else.

Files: opt/verdandi/licenses/third-party/*
Copyright: see each file
License: see-files
 Ableton Link (GPL-2+), lua-cjson (MIT), concurrentqueue (BSD-2-Clause or BSL-1.0), readerwriterqueue (BSD-2-Clause).
CPR
    {
        printf 'verdandi (%s) unstable; urgency=low\n\n  * Built from commit %s of the Verdandi source.\n\n -- %s  %s\n' \
            "$VERSION" "$(git -C "$REPO" rev-parse --short HEAD)" "$MAINTAINER" "$(date -u -R -d "@$EPOCH")"
    } | gzip -9n > "$doc/changelog.gz"
    chmod 644 "$doc/copyright" "$doc/changelog.gz"

    # modification times from the commit (reproducible); owner root through --root-owner-group
    find "$STAGE" -exec touch -h -d "@$EPOCH" {} +
    privacy_scan "$STAGE"
    rm -f "$OUT"/verdandi_*.deb
    dpkg-deb --build --root-owner-group -Zxz "$STAGE" "$DEB" > /dev/null
    check_deb "$DEB"
    ls -l "$DEB"
}

# metadata of a built .deb: the maintainer, ownership, the files outside /opt/verdandi, and the privacy scan of the extracted package
check_deb() {
    local f="$1" t
    [ -f "$f" ] || die "check: $f not found"
    t="$(mktemp -d)"
    dpkg-deb -x "$f" "$t/x"
    dpkg-deb -e "$f" "$t/c"
    local owners
    owners="$(dpkg-deb -c "$f" | awk '{print $2}' | sort -u | tr '\n' ' ')"
    [ "$owners" = "root/root " ] || { rm -rf "$t"; die "check: files are not all owned by root/root: $owners"; }
    local outside
    # files and links (directory entries are the parents of the places below)
    outside="$(dpkg-deb -c "$f" | grep -v '^d' | awk '{print $6}' | sed 's#^\./##' |
        grep -vE '^(opt/verdandi/|usr/bin/verdandi$|usr/share/applications/verdandi.desktop$|usr/share/icons/hicolor/256x256/apps/verdandi.png$|usr/share/doc/verdandi/|usr/lib/udev/rules.d/70-verdandi-monome.rules$)' || true)"
    [ -z "$outside" ] || { echo "$outside" | head; rm -rf "$t"; die "check: files outside the allowed places"; }
    grep -q "^Maintainer: " "$t/c/control" || { rm -rf "$t"; die "check: no Maintainer"; }
    privacy_scan "$t"
    rm -rf "$t"
    echo "check: $f: owners root/root, files only in /opt/verdandi and the desktop places, no identity word"
}

# the whole build in a fresh Ubuntu 24.04 root (debootstrap): the repository is copied to /build/verdandi (a neutral path, so no
# folder name of the builder reaches the binaries), the dependencies come from linux/setup-deps.sh, the package from this script.
# the result is copied to build/package/clean-root/. needs root, debootstrap and a network (apt, github, gitlab).
build_clean_root() {
    [ "$(id -u)" -eq 0 ] || die "clean-root needs root (debootstrap, chroot)"
    command -v debootstrap >/dev/null || die "debootstrap is not installed (apt install debootstrap)"
    local base="$CACHE/noble-build-base" R="$OUT/clean-root/root" mirror="${UBUNTU_MIRROR:-http://archive.ubuntu.com/ubuntu}" ca=""
    if [ ! -x "$base/bin/bash" ]; then
        say "debootstrap noble (once, cached in $base)"
        mkdir -p "$CACHE"
        debootstrap --variant=minbase --include=ca-certificates,git,curl,sudo noble "$base.tmp" "$mirror" > "$CACHE/debootstrap-build.log" 2>&1 ||
            { tail -5 "$CACHE/debootstrap-build.log"; die "debootstrap failed"; }
        mv "$base.tmp" "$base"
    fi
    rm -rf "$OUT/clean-root"
    mkdir -p "$OUT/clean-root"
    say "clean root: copy of the base root"
    cp -a "$base" "$R"
    say "clean root: copying the repository to /build/verdandi"
    mkdir -p "$R/build/verdandi"
    # owner 0: the account that runs this has no meaning inside the root (and must not be in its file ownership)
    (cd "$REPO" && tar --exclude=./build --owner=0 --group=0 --numeric-owner -cf - .) | tar -xf - -C "$R/build/verdandi" --no-same-owner
    for f in "${PACKAGE_CA_BUNDLE:-}" "${SSL_CERT_FILE:-}" /root/.ccr/ca-bundle.crt; do
        [ -n "$f" ] && [ -f "$f" ] && { ca="$f"; break; }
    done
    [ -n "$ca" ] && install -D -m 644 "$ca" "$R/usr/local/share/ca-certificates/host-proxy.crt"
    cat > "$R/root/clean-build.sh" <<'INNER'
#!/bin/bash
# runs INSIDE the clean root, as its own root user. nothing of the account that started the build is here: the environment is
# empty but for the proxy and mirror settings (no SUDO_USER, no HOME of the host)
set -eEu
set -o pipefail
export DEBIAN_FRONTEND=noninteractive
STAGE_NAME=start
stage() { STAGE_NAME="$1"; echo "$1" > /root/stage.txt; echo; echo "==== STAGE: $1 ($(date -u +%H:%M:%S))"; }
trap 'echo "==== FAILED in stage: $STAGE_NAME"' ERR
stage "apt sources and update"
printf 'deb %s noble main universe\ndeb %s noble-updates main universe\n' "$MIRROR" "$MIRROR" > /etc/apt/sources.list
rm -f /etc/apt/sources.list.d/*
apt-get update -q
stage "certificates and git"
[ -f /usr/local/share/ca-certificates/host-proxy.crt ] && update-ca-certificates > /dev/null
export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt GIT_SSL_CAINFO=/etc/ssl/certs/ca-certificates.crt CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
# node and npm (maiden's web app) do not read the system store by themselves
export NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt npm_config_cafile=/etc/ssl/certs/ca-certificates.crt
# maiden is built by "package.sh all" below, where a failure stops the build; in setup-deps.sh and build.sh it is only a warning
git config --global --add safe.directory '*'
cd /build/verdandi
stage "linux/setup-deps.sh (apt build dependencies, libmonome for /usr/local, waf)"
NORNS_NO_MAIDEN=1 linux/setup-deps.sh
stage "linux/build.sh (norns, maiden)"
NORNS_NO_MAIDEN=1 linux/build.sh
stage "linux/package.sh all (SuperCollider, sc3-plugins, libmonome, maiden, tree, .deb)"
linux/package.sh all
stage "done"
INNER
    chmod 755 "$R/root/clean-build.sh"
    say "build in the clean root (this takes a while: dependencies, SuperCollider, norns, maiden)"
    # the words that identify the person who builds are handed in so that the scan inside the root knows them
    local words
    words="$(identity_words | tr '\n' ' ')"
    local t0=$SECONDS
    if ! unshare -m sh -c "
        mount -t proc proc '$R/proc' && mount --rbind /dev '$R/dev' && mount -t tmpfs tmpfs '$R/dev/shm' && mount -t tmpfs tmpfs '$R/tmp'
        cp /etc/resolv.conf '$R/etc/resolv.conf' 2>/dev/null
        chroot '$R' /usr/bin/env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root LANG=C.UTF-8 MIRROR='$mirror' http_proxy='${http_proxy:-}' https_proxy='${https_proxy:-}' HTTP_PROXY='${HTTP_PROXY:-}' HTTPS_PROXY='${HTTPS_PROXY:-}' NO_PROXY='${NO_PROXY:-}' PACKAGE_PRIVACY_EXTRA='$words' /bin/bash /root/clean-build.sh"; then
        STAGE_NOW="in the clean root: $(cat "$R/root/stage.txt" 2>/dev/null || echo unknown)"
        echo "package.sh: the build in the clean root failed in the stage '$(cat "$R/root/stage.txt" 2>/dev/null || echo unknown)'; the root is kept in $R"
        exit 1
    fi
    mkdir -p "$OUT/clean-root"
    cp "$R"/build/verdandi/build/package/verdandi_*.deb "$OUT/clean-root/"
    local rootsize
    rootsize="$(du -sh "$R" | cut -f1)"
    echo "package.sh: build time in the root $(( (SECONDS - t0) / 60 )) min; the root is $rootsize"
    if [ "${PACKAGE_KEEP_ROOT:-0}" = 1 ]; then echo "package.sh: PACKAGE_KEEP_ROOT=1: the root is kept in $R"; else rm -rf "$R"; echo "package.sh: the root is removed (PACKAGE_KEEP_ROOT=1 keeps it)"; fi
    check_deb "$(ls "$OUT"/clean-root/verdandi_*.deb | head -1)"
    ls -l "$OUT"/clean-root/*.deb
}

case "${1:-}" in
    sc) build_sc ;;
    maiden) build_maiden ;;
    libmonome) build_libmonome ;;
    tree) build_libmonome; build_tree ;;
    deb) build_deb ;;
    all) build_sc; build_libmonome; build_maiden; build_tree; build_deb ;;
    clean-root) build_clean_root ;;
    check) check_deb "${2:?usage: package.sh check FILE.deb}" ;;
    *) die "usage: see the top of this file" ;;
esac
