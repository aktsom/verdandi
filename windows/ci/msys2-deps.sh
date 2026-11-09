#!/usr/bin/env bash
# windows/ci/msys2-deps.sh (M0a): the toolchain half. run inside MSYS2 UCRT64 (msys2/setup-msys2 with msystem UCRT64). it
#   1. installs the packages norns needs, ONE BY ONE, so that a name that does not exist in MSYS2 shows up in the report instead of stopping everything;
#   2. builds Lua 5.3 from source (MSYS2 ships 5.4, norns needs 5.3; the lua53 pkg-config name of the wscript is made by us);
#   3. builds libmonome 1.4.9 with its CMake file, as far as it goes (the Windows serial layer is src/platform/windows.c);
#   4. compiles and runs the Ableton Link probe with LINK_PLATFORM_WINDOWS.
# all four are steps of the report (PASS or FAIL), none of them stops the job.
#   LUA_VERSION  5.3.6
# the functions below are called through m0_run (shellcheck cannot see that)
# shellcheck disable=SC2329
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=windows/ci/lib.sh
. "$HERE/lib.sh"
REPO="$(cd "$HERE/../.." && pwd)"
LUA_VERSION="${LUA_VERSION:-5.3.6}"
PREFIX="${PREFIX:-$PWD/m0-work/prefix}"
mkdir -p "$PREFIX"
export PATH="$PREFIX/bin:$PATH"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

# package names as the MSYS2 UCRT64 repository names them; a missing one is a finding, not a failure of the job
PKGS="gcc cmake ninja make pkgconf liblo cairo freetype libsndfile SDL2 nng libsamplerate fftw readline"
install_pkgs() {
    local p rc=0
    : > "$M0_OUT/msys2-packages.txt"
    for p in $PKGS; do
        if pacman -S --noconfirm --needed "mingw-w64-ucrt-x86_64-$p" > /dev/null 2>&1; then
            echo "OK   $p" >> "$M0_OUT/msys2-packages.txt"
        else
            echo "MISSING $p" >> "$M0_OUT/msys2-packages.txt"
            rc=1
        fi
    done
    cat "$M0_OUT/msys2-packages.txt"
    return "$rc"
}

build_lua() {
    local d="$PWD/m0-work/lua-$LUA_VERSION"
    mkdir -p "$PWD/m0-work"
    [ -d "$d" ] || (cd "$PWD/m0-work" && curl -fL --retry 3 -o lua.tar.gz "https://www.lua.org/ftp/lua-$LUA_VERSION.tar.gz" && tar xzf lua.tar.gz) || return 1
    (cd "$d" && make -j4 mingw && make install INSTALL_TOP="$PREFIX") || return 1
    # pkg-config file with the name the wscript asks for
    mkdir -p "$PREFIX/lib/pkgconfig"
    cat > "$PREFIX/lib/pkgconfig/lua53.pc" <<PC
prefix=$PREFIX
Name: lua53
Description: Lua $LUA_VERSION
Version: $LUA_VERSION
Cflags: -I$PREFIX/include
Libs: -L$PREFIX/lib -llua
PC
    "$PREFIX/bin/lua.exe" -e 'print(_VERSION)' | grep -q "Lua 5.3"
}

build_libmonome() {
    local src="$REPO/build/package/cache/libmonome" d="$PWD/m0-work/libmonome-build"
    # the package cache is not in the repository: fetch the release the Linux build uses
    if [ ! -f "$src/CMakeLists.txt" ]; then
        src="$PWD/m0-work/libmonome-src"
        [ -d "$src/.git" ] || git clone --depth 1 --branch v1.4.9 https://github.com/monome/libmonome.git "$src" || return 1
    fi
    # upstream builds with -Wall -Werror for GCC; MinGW may warn where Linux does not. first as it is, then (and said in the log) without -Werror, so that the warnings are listed and the build goes on
    if ! { cmake -S "$src" -B "$d" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" && cmake --build "$d"; }; then
        echo "libmonome: the strict build (-Werror) failed, trying again without -Werror"
        rm -rf "$d"
        sed -i 's/ -Werror//' "$src/CMakeLists.txt"
        cmake -S "$src" -B "$d" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" || return 1
        cmake --build "$d" || return 1
        echo "libmonome: built WITHOUT -Werror"
    fi
    cmake --install "$d"
}

link_probe() {
    local inc="$REPO/third-party/link"
    g++ -std=c++14 -w -DLINK_PLATFORM_WINDOWS=1 -D_WIN32_WINNT=0x0601 -I "$inc/include" -I "$inc/modules/asio-standalone/asio/include" \
        "$HERE/link_probe.cpp" -o "$PWD/m0-work/link_probe.exe" -lws2_32 -lwinmm -liphlpapi -lmswsock || return 1
    "$PWD/m0-work/link_probe.exe"
}

m0_init
m0_run msys2-packages install_pkgs
m0_run lua53-build build_lua
m0_run libmonome-build build_libmonome
m0_run link-probe link_probe
exit 0
