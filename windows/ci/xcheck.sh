#!/usr/bin/env bash
# windows/ci/xcheck.sh: compile-check the Windows build on LINUX with the mingw-w64 cross compiler (apt: g++-mingw-w64-x86-64). -fsyntax-only, nothing is linked or run: it finds the code that cannot compile for Windows
# before a runner is needed. dependency headers (Lua, cairo, SDL2, liblo, sndfile, nng, libmonome) come from the Linux -dev packages / caches: they are the same text on both systems.
#   XC_DEFS   extra -D flags     XC_FILES   files to check (default: all norns sources of the Windows build)
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
cd "$REPO" || exit 1
CXX=x86_64-w64-mingw32-g++-posix; CC=x86_64-w64-mingw32-gcc-posix
command -v "$CXX" > /dev/null || { CXX=x86_64-w64-mingw32-g++; CC=x86_64-w64-mingw32-gcc; }
# a folder with links to ONLY the headers of the third-party libraries (never the Linux system headers, which the cross compiler must not see)
SHADOW="$REPO/build/xcheck-inc"
mkdir -p "$SHADOW"
for h in lo SDL2 cairo sndfile.h sndfile.hh nng fontconfig lua5.3 freetype2 pixman-1 libpng16 ; do
    [ -e "/usr/include/$h" ] && ln -sfn "/usr/include/$h" "$SHADOW/$h"
done
ln -sfn /usr/include/lua5.3/lua.h "$SHADOW/lua.h"; ln -sfn /usr/include/lua5.3/lualib.h "$SHADOW/lualib.h"; ln -sfn /usr/include/lua5.3/lauxlib.h "$SHADOW/lauxlib.h"
ln -sfn /usr/include/lua5.3/luaconf.h "$SHADOW/luaconf.h"; ln -sfn /usr/include/lua5.3/lua.hpp "$SHADOW/lua.hpp"
ln -sfn /usr/include/glib-2.0/glib.h "$SHADOW/glib.h" 2> /dev/null || true
MON="${LIBMONOME_INC:-build/package/cache/libmonome/public}"
INC="-I matron/src -I matron/src/hardware -I matron/src/device -I matron/src/platform/windows -I matron/src/platform/windows/include -I matron/src/platform/macos/include -I norns -I crone -I crone/src -I crone/faust \
 -I crone/softcut/softcut-lib/include -I third-party/concurrentqueue -I third-party/readerwriterqueue -I third-party/lua-cjson -I third-party/link/extensions/abl_link/include -I $MON \
 -isystem $SHADOW -isystem $SHADOW/SDL2 -isystem $SHADOW/cairo -isystem $SHADOW/freetype2"
DEFS=(-DNORNS_DESKTOP=1 -DNORNS_LINUX_DESKTOP=1 -DNORNS_WINDOWS=1 -DHAVE_LIBMONOME=1 -DHAVE_NNG=1 -DHAVE_LUA_CJSON=1 -DHAVE_ABLETON_LINK=0 -DVERSION_MAJOR=0 -DVERSION_MINOR=0 -DVERSION_PATCH=0 '-DVERSION_HASH="xcheck"')
# shellcheck disable=SC2206
DEFS+=(${XC_DEFS:-})
files="${XC_FILES:-}"
[ -n "$files" ] || files="$(find matron/src crone/src norns -type f \( -name '*.c' -o -name '*.cc' -o -name '*.cpp' \) -not -path '*/platform/macos/*' -not -path '*/platform/linux/*' -not -path '*/hardware/screen/ssd1322.cc' -not -path '*/hardware/input/gpio.cc' | sort)"
ok=0; bad=0
for f in $files; do
    case "$f" in *.c) cmd="$CC -std=gnu11" ;; *) cmd="$CXX -std=gnu++14" ;; esac
    # shellcheck disable=SC2086
    err=$($cmd -fsyntax-only -w "${DEFS[@]}" $INC "$f" 2>&1 | grep -m1 -E "error" || true)
    if [ -z "$err" ]; then ok=$((ok + 1)); [ "${XC_QUIET:-0}" = 1 ] || echo "OK   $f"; else bad=$((bad + 1)); echo "ERR  $f: $(printf '%s' "$err" | cut -c1-170)"; fi
done
echo "xcheck: $ok compile, $bad do not"
[ "$bad" -eq 0 ]
