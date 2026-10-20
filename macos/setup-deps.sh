#!/bin/bash
# setup-deps.sh: build everything norns needs on macOS that homebrew does not provide.
#
# result: <deps>/prefix (lua 5.3, nng 1.x, libmonome, SuperCollider.app with the jack
# backend), <deps>/bin/waf (waf 2.1; the bundled waf 2.0 needs python's removed `imp`)
# sc3-plugins in the norns home's SuperCollider extensions, and maiden in <norns home>/maiden.
#
# usage: macos/setup-deps.sh [deps dir, default: <norns home>/../../deps]
# paths must not contain spaces (lua's makefile); use a symlink if the disk name has one.

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
NORNS_HOME="$(dirname "$REPO")"
DEPS="${1:-$(cd "$NORNS_HOME/../.." && pwd)/deps}"
P="$DEPS/prefix"
SRC="$DEPS/src"
BREW="${HOMEBREW_PREFIX:-/opt/homebrew}"
J=$(sysctl -n hw.ncpu)

LUA_VERSION=5.3.6
LUA_SHA256=fc5fd69bb8736323f026672b1b7235da613d7177e72558893a0bdcd320466d60
WAF_VERSION=2.1.9
SC_TAG=Version-3.14.1
# maiden's web app (react-scripts 1.x) needs the node its own tooling pins
NODE_VERSION=v16.20.2

case "$DEPS" in *" "*) echo "setup-deps: '$DEPS' contains a space"; exit 1 ;; esac
# the oldest macOS the app runs on: clang and cmake take it from here
export MACOSX_DEPLOYMENT_TARGET="$(cat "$REPO/macos/MACOS_MIN")"
# keep build paths (they contain the user name) out of the binaries
MAP="-ffile-prefix-map=$DEPS=/build/deps -ffile-prefix-map=$NORNS_HOME=/build/home"
mkdir -p "$P/lib/pkgconfig" "$SRC" "$DEPS/bin"

echo "== homebrew packages"
brew install cairo boost cmake pkgconf readline jack liblo libsndfile sdl2 fftw yaml-cpp \
    coreutils findutils gnu-sed grep gawk go

echo "== homebrew bottles for macOS $MACOSX_DEPLOYMENT_TARGET (what make-app.sh bundles)"
python3 -I "$REPO/macos/fetch_bottles.py" "$DEPS/bottles"

# built for another oldest macOS: build it again
STAMP="$P/.macos-min"
if [ "$(cat "$STAMP" 2>/dev/null)" != "$MACOSX_DEPLOYMENT_TARGET" ]; then
    echo "== oldest macOS is now $MACOSX_DEPLOYMENT_TARGET: rebuilding lua, nng, libmonome, SuperCollider, sc3-plugins"
    rm -rf "$P/lib/liblua.a" "$P/lib/libnng.a" "$P/include/monome.h" "$P/SuperCollider" \
        "$SRC/lua-$LUA_VERSION" "$SRC/nng/build" "$SRC/libmonome/build" "$SRC/supercollider/build" \
        "$SRC/sc3-plugins/build" "$NORNS_HOME/Library/Application Support/SuperCollider/Extensions/SC3plugins"
fi

echo "== waf $WAF_VERSION"
[ -x "$DEPS/bin/waf" ] || { curl -sSfL -o "$DEPS/bin/waf" "https://waf.io/waf-$WAF_VERSION" && chmod +x "$DEPS/bin/waf"; }

echo "== lua $LUA_VERSION (C linkage)"
if [ ! -f "$P/lib/liblua.a" ]; then
    cd "$SRC"
    curl -sSfLO "https://www.lua.org/ftp/lua-$LUA_VERSION.tar.gz"
    echo "$LUA_SHA256  lua-$LUA_VERSION.tar.gz" | shasum -a 256 -c -
    tar xzf "lua-$LUA_VERSION.tar.gz"
    make -C "lua-$LUA_VERSION" macosx MYCFLAGS="-fPIC -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET"
    make -C "lua-$LUA_VERSION" install INSTALL_TOP="$P"
fi
cat > "$P/lib/pkgconfig/lua53.pc" <<EOF
prefix=$P
Name: Lua
Description: Lua 5.3
Version: $LUA_VERSION
Libs: -L\${prefix}/lib -llua -lm
Cflags: -I\${prefix}/include
EOF

echo "== nng 1.x (norns uses the 1.x api; homebrew has 2.x)"
if [ ! -f "$P/lib/libnng.a" ]; then
    cd "$SRC"
    T=$(git ls-remote --tags --refs https://github.com/nanomsg/nng.git 'v1.*' | awk -F/ '{print $3}' | sort -V | tail -1)
    [ -d nng ] || git clone -q --depth 1 -b "$T" https://github.com/nanomsg/nng.git
    cmake -S nng -B nng/build -DCMAKE_INSTALL_PREFIX="$P" -DNNG_TESTS=OFF -DNNG_TOOLS=OFF -DBUILD_SHARED_LIBS=OFF -DCMAKE_BUILD_TYPE=Release
    cmake --build nng/build -j "$J"
    cmake --install nng/build
fi

echo "== libmonome"
if [ ! -f "$P/include/monome.h" ]; then
    cd "$SRC"
    [ -d libmonome ] || git clone -q --depth 1 https://github.com/monome/libmonome.git
    cd libmonome
    # embedded protocols: otherwise libmonome dlopens them from this build's absolute prefix
    CFLAGS="-I$BREW/include $MAP" LDFLAGS="-L$BREW/lib" PKG_CONFIG_PATH="$P/lib/pkgconfig:$BREW/lib/pkgconfig" \
        python3 ./waf configure --prefix="$P" --enable-embedded-protos
    python3 ./waf
    python3 ./waf install
fi

echo "== SuperCollider $SC_TAG (jack backend, no IDE)"
SC_APP="$P/SuperCollider/SuperCollider.app/Contents"
if [ ! -x "$SC_APP/MacOS/sclang" ]; then
    cd "$SRC"
    [ -d supercollider ] || git clone -q --depth 1 -b "$SC_TAG" --recurse-submodules --shallow-submodules https://github.com/supercollider/supercollider.git
    # system boost/yaml-cpp: homebrew's headers are on the include path anyway, so the
    # bundled copies would be compiled against the wrong headers
    cmake -S supercollider -B supercollider/build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$P" \
        -DAUDIOAPI=jack -DSC_QT=OFF -DSC_IDE=OFF -DSUPERNOVA=OFF -DSC_EL=OFF -DSC_VIM=OFF -DSC_ED=OFF \
        -DNO_X11=ON -DSC_ABLETON_LINK=OFF -DINSTALL_HELP=OFF -DENABLE_TESTSUITE=OFF \
        -DSYSTEM_BOOST=ON -DSYSTEM_YAMLCPP=ON -DCMAKE_PREFIX_PATH="$BREW;$BREW/opt/readline" \
        -DCMAKE_C_FLAGS="$MAP" -DCMAKE_CXX_FLAGS="$MAP"
    cmake --build supercollider/build -j "$J"
    cmake --install supercollider/build
fi
# without the qt ide the install skips the class library
[ -d "$SC_APP/Resources/SCClassLibrary" ] || cp -R "$SRC/supercollider/SCClassLibrary" "$SC_APP/Resources/"

echo "== sc3-plugins"
EXT="$NORNS_HOME/Library/Application Support/SuperCollider/Extensions"
if [ ! -d "$EXT/SC3plugins" ]; then
    cd "$SRC"
    [ -d sc3-plugins ] || git clone -q --depth 1 --recurse-submodules --shallow-submodules https://github.com/supercollider/sc3-plugins.git
    # `0<=bufnum<= n` is always true, and clang 21 rejects it; the intended bounds check
    sed -i '' 's/	if(0<=bufnum<= world->mNumSndBufs) {/	if(bufnum < (int)world->mNumSndBufs) {/' \
        sc3-plugins/source/NCAnalysisUGens/SMS.cpp
    cmake -S sc3-plugins -B sc3-plugins/build -DSC_PATH="$SRC/supercollider" -DCMAKE_BUILD_TYPE=Release \
        -DSUPERNOVA=OFF -DQUARKS=OFF -DSCX=ON -DCMAKE_PREFIX_PATH="$BREW" \
        -DCMAKE_C_FLAGS="$MAP" -DCMAKE_CXX_FLAGS="$MAP"
    cmake --build sc3-plugins/build -j "$J"
    # on macOS the install step always lands in build/SC3plugins
    cmake --install sc3-plugins/build
    mkdir -p "$EXT"
    cp -R sc3-plugins/build/SC3plugins "$EXT/"
    # help files are most of the size and unused at runtime
    find "$EXT/SC3plugins" -type d -name HelpSource -prune -exec rm -rf {} +
fi

echo "== maiden"
M="$NORNS_HOME/maiden"
if [ ! -x "$M/maiden" ]; then
    cd "$SRC"
    if [ ! -x node16/bin/node ]; then
        F="node-$NODE_VERSION-darwin-arm64.tar.gz"
        curl -sSfLO "https://nodejs.org/dist/$NODE_VERSION/$F"
        curl -sSfL "https://nodejs.org/dist/$NODE_VERSION/SHASUMS256.txt" | grep " $F\$" | shasum -a 256 -c -
        mkdir -p node16 && tar xzf "$F" -C node16 --strip-components 1 && rm "$F"
    fi
    [ -d maiden ] || git clone -q --depth 1 https://github.com/monome/maiden.git
    # --host: listen on 127.0.0.1 only (maiden edits files and fronts code-running REPLs)
    git -C maiden apply --check "$REPO/macos/patches/maiden-host-flag.patch" 2>/dev/null &&
        git -C maiden apply "$REPO/macos/patches/maiden-host-flag.patch"
    (cd maiden && GOFLAGS=-mod=mod go build -trimpath -ldflags="-X github.com/monome/maiden/cmd.version=$(git describe --tags 2>/dev/null || echo head)-macos" -o maiden .)
    (cd maiden/web && PATH="$SRC/node16/bin:$PATH" npx -y yarn@1.22.22 install --frozen-lockfile &&
        PATH="$SRC/node16/bin:$PATH" npx -y yarn@1.22.22 build)
    mkdir -p "$M/app" "$M/dist/sources"
    cp maiden/maiden maiden/maiden.yaml "$M/"
    rm -rf "$M/app/build" && cp -R maiden/web/build "$M/app/"
    cp maiden/sources/*.json "$M/dist/sources/"
fi

echo "$MACOSX_DEPLOYMENT_TARGET" > "$STAMP"
echo "== done. build norns: cd $REPO && python3 $DEPS/bin/waf configure && python3 $DEPS/bin/waf"
