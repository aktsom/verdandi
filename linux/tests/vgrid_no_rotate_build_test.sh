#!/bin/bash
# M43: the window code of the virtual grid (matron/src/platform/macos/sdl_bridge.cc) must compile when VGRID_ROTATE is not defined, which is what the Windows build and the Mac build see (the Linux desktop
# build defines it). the Windows CI found that a macro moved into the VGRID_ROTATE part was missing there (windows-m1 70650caf: "GRID_DOWN_FLAGS was not declared"): the Linux build never saw it. this builds
# sdl_bridge.cc with -fsyntax-only and -DVGRID_TEST_NO_ROTATE (vgrid_skin.h then leaves VGRID_ROTATE undefined) with the Linux desktop's flags. skips when the headers are not here (no SDL, no Lua headers).
cd "$(dirname "$0")/../.." || exit 1
if ! pkg-config --exists sdl2 cairo lua5.3 glib-2.0 2> /dev/null; then echo "SKIP: the development headers of SDL2, Cairo, Lua or GLib are not installed"; exit 77; fi
INC="-I matron/src -I matron/src/device -I matron/src/hardware -I third-party/link/extensions/abl_link/include -I third-party/concurrentqueue -I third-party/readerwriterqueue -I crone -I crone/src -I crone/softcut/softcut-lib/include"
SYS="$(pkg-config --cflags sdl2 cairo freetype2 lua5.3 glib-2.0 gio-2.0 libevdev alsa opus 2> /dev/null) $(pkg-config --cflags avahi-compat-libdns_sd 2> /dev/null)"
DEFS='-DVERSION_MAJOR=0 -DVERSION_MINOR=0 -DVERSION_PATCH=0 -DVERSION_HASH="x" -D_GNU_SOURCE=1 -DHAVE_ALSA=1 -DHAVE_LIBUDEV=1 -DHAVE_LIBEVDEV=1 -DHAVE_GLIB_2_0=1 -DHAVE_GIO_2_0=1 -DHAVE_LIBLO=1 -DHAVE_CAIRO=1 -DHAVE_CAIRO_FT=1 -DHAVE_LUA53=1 -DHAVE_SNDFILE=1 -DHAVE_JACK=1 -DHAVE_LIBMONOME=1 -DHAVE_NNG=1 -DHAVE_ATOMIC=1 -DHAVE_SDL2=1 -DNORNS_DESKTOP=1 -DHAVE_ABLETON_LINK=1 -DHAVE_LUA_CJSON=1 -DNORNS_LINUX_DESKTOP=1'
out="$(eval g++ -std=c++14 -fsyntax-only -DVGRID_TEST_NO_ROTATE $DEFS $INC $SYS matron/src/platform/macos/sdl_bridge.cc 2>&1)"
rc=$?
if [ $rc -eq 0 ]; then echo "ok   sdl_bridge.cc compiles without VGRID_ROTATE (the Mac and Windows view)"; echo "vgrid_no_rotate_build_test: all passed"; exit 0; fi
echo "$out" | grep -E "error" | head -5
echo "FAIL: sdl_bridge.cc does not compile without VGRID_ROTATE"
exit 1
