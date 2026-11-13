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
for h in lo cairo sndfile.h sndfile.hh nng fontconfig lua5.3 freetype2 pixman-1 libpng16 ; do
    [ -e "/usr/include/$h" ] && ln -sfn "/usr/include/$h" "$SHADOW/$h"
done
# SDL2 on Debian has a multiarch SDL_config.h wrapper: a shadow copy of the folder with the real x86_64 config in its place
rm -rf "$SHADOW/SDL2"; mkdir -p "$SHADOW/SDL2"
for f in /usr/include/SDL2/*; do ln -sf "$f" "$SHADOW/SDL2/$(basename "$f")"; done
for cfg in /usr/include/x86_64-linux-gnu/SDL2/_real_SDL_config.h /usr/include/x86_64-linux-gnu/SDL2/SDL_config.h; do [ -f "$cfg" ] && cp "$cfg" "$SHADOW/SDL2/SDL_config.h" && break; done
ln -sfn /usr/include/lua5.3/lua.h "$SHADOW/lua.h"; ln -sfn /usr/include/lua5.3/lualib.h "$SHADOW/lualib.h"; ln -sfn /usr/include/lua5.3/lauxlib.h "$SHADOW/lauxlib.h"
ln -sfn /usr/include/lua5.3/luaconf.h "$SHADOW/luaconf.h"; ln -sfn /usr/include/lua5.3/lua.hpp "$SHADOW/lua.hpp"
ln -sfn /usr/include/glib-2.0/glib.h "$SHADOW/glib.h" 2> /dev/null || true
ln -sfn /usr/include/portaudio.h "$SHADOW/portaudio.h" 2> /dev/null || true # (M2: the header of PortAudio is the same on every system)
# Ableton Link includes Windows headers by their capitalised names (WS2tcpip.h): the real Windows has no case in file names, this Linux cross compiler has; links in the shadow folder make it find them
for h in WS2tcpip:ws2tcpip Iphlpapi:iphlpapi WinSock2:winsock2 Windows:windows MSWSock:mswsock; do
    for d in /usr/share/mingw-w64/include /usr/x86_64-w64-mingw32/include; do [ -f "$d/${h#*:}.h" ] && ln -sfn "$d/${h#*:}.h" "$SHADOW/${h%%:*}.h" && break; done
done
MON="${LIBMONOME_INC:-build/package/cache/libmonome/public}"
INC="-include $REPO/matron/src/platform/windows/compat_win.h -I matron/src -iquote matron/src/hardware -iquote matron/src/device -I matron/src/platform/windows -I matron/src/platform/windows/include -I matron/src/platform/windows/jack_null/include -I matron/src/platform/macos/include -I norns -I crone -I crone/src -I crone/faust \
 -I crone/softcut/softcut-lib/include -I third-party/concurrentqueue -I third-party/readerwriterqueue -I third-party/lua-cjson -I third-party/link/extensions/abl_link/include -I third-party/link/include -I third-party/link/modules/asio-standalone/asio/include -I $MON \
 -isystem $SHADOW -isystem $SHADOW/SDL2 -isystem $SHADOW/cairo -isystem $SHADOW/freetype2"
DEFS=(-DNORNS_DESKTOP=1 -DNORNS_LINUX_DESKTOP=1 -DNORNS_WINDOWS=1 -DHAVE_LIBMONOME=1 -DHAVE_NNG=1 -DHAVE_LUA_CJSON=1 -DHAVE_ABLETON_LINK=1 -DLINK_PLATFORM_WINDOWS=1 -D_WIN32_WINNT=0x0601 -DVERSION_MAJOR=0 -DVERSION_MINOR=0 -DVERSION_PATCH=0 '-DVERSION_HASH="xcheck"')
# shellcheck disable=SC2206
DEFS+=(${XC_DEFS:-})
files="${XC_FILES:-}"
[ -n "$files" ] || files="$(grep -v '^#' windows/cmake/norns-sources.txt | grep -v '^$') windows/ws-wrapper/ws_wrapper_win.c windows/shims/shim_win.c"
ok=0; bad=0
# XC_LINK=1: compile to objects (build/xlink) and report the symbols that no object defines and no known library provides
mode=-fsyntax-only; [ "${XC_LINK:-0}" = 1 ] && { mkdir -p build/xlink; rm -f build/xlink/*.o; }
for f in $files; do
    case "$f" in *.c) cmd="$CC -std=gnu11" ;; *) cmd="$CXX -std=gnu++14" ;; esac
    extra=""; case "$f" in */sdl_bridge.cc) extra="-include $REPO/matron/src/platform/windows/compat_sock.h" ;; windows/shims/*) extra="-municode -I $REPO/windows/shims" ;; esac
    out=""; if [ "${XC_LINK:-0}" = 1 ]; then out="-o build/xlink/$(echo "$f" | tr / _).o"; mode=-c; fi
    # shellcheck disable=SC2086
    err=$($cmd $mode $out -w "${DEFS[@]}" $INC $extra "$f" 2>&1 | grep -m1 -E "error" -B3 -A2 | tr "\n" " " || true)
    if [ -z "$err" ]; then ok=$((ok + 1)); [ "${XC_QUIET:-0}" = 1 ] || echo "OK   $f"; else bad=$((bad + 1)); echo "ERR  $f: $(printf '%s' "$err" | cut -c1-900)"; fi
done
echo "xcheck: $ok compile, $bad do not"
if [ "${XC_LINK:-0}" = 1 ] && [ "$bad" -eq 0 ]; then
    # every symbol the objects need that neither they nor the compiler's runtime define, minus the third-party libraries that the real link adds
    $CXX build/xlink/*.o -o /dev/null -Wl,--unresolved-symbols=report-all -lws2_32 -liphlpapi -lcfgmgr32 -lsetupapi -lpthread -lwinmm -lole32 -lshell32 -ldbghelp -lpsapi 2>&1 \
        | grep -o "undefined reference to .*" | sed -E "s/undefined reference to .(.*).$/\1/" | sort -u \
        | grep -v -E "^(lua|luaL|luaopen|SDL_|cairo_|lo_|nng_|sf_|monome_|FT_|Pa_|abl_link|__imp_|json|cJSON)" > build/xlink/unresolved.txt || true
    echo "unresolved project symbols: $(wc -l < build/xlink/unresolved.txt) (build/xlink/unresolved.txt)"
fi
[ "$bad" -eq 0 ]
