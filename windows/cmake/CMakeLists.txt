# Verdandi for Windows: norns.exe (M1). built in the MSYS2 UCRT64 shell (windows/ci/build-norns.sh): Ninja + gcc 
#   cmake -S windows/cmake -B build/win -G Ninja -DCMAKE_PREFIX_PATH=<prefix with Lua 5.3 and libmonome>
# the sources are listed in norns-sources.txt (one list for this file and for windows/ci/xcheck.sh, the mingw cross-check on Linux). waf is not used on Windows.
cmake_minimum_required(VERSION 3.20)
project(verdandi LANGUAGES C CXX)

set(REPO "${CMAKE_CURRENT_SOURCE_DIR}/../..")
get_filename_component(REPO "${REPO}" ABSOLUTE)

if(NOT WIN32)
  message(FATAL_ERROR "this build is for Windows (MSYS2 UCRT64). on Linux use waf (linux/build.sh).")
endif()

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_EXTENSIONS ON)
set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_EXTENSIONS ON)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()
# no build paths (they contain the user name of whoever builds) in the binaries
add_compile_options(-ffile-prefix-map=${REPO}=/build/norns -O2 -Wall)

find_package(PkgConfig REQUIRED)
pkg_check_modules(LUA53 REQUIRED IMPORTED_TARGET lua53)
pkg_check_modules(LIBLO REQUIRED IMPORTED_TARGET liblo)
pkg_check_modules(CAIRO REQUIRED IMPORTED_TARGET cairo)
pkg_check_modules(SNDFILE REQUIRED IMPORTED_TARGET sndfile)
# box_style.c uses FreeType directly (cairo's pkg-config file does not pass it on)
pkg_check_modules(FREETYPE2 REQUIRED IMPORTED_TARGET freetype2)
pkg_check_modules(SDL2 REQUIRED IMPORTED_TARGET sdl2)
# nng: MSYS2 ships a CMake package, not a pkg-config file (first M1 run: "Package nng not found"); header and library are searched directly
find_path(NNG_INC nng/nng.h REQUIRED)
find_library(NNG_LIB NAMES nng libnng REQUIRED)
# the static library (no extra DLL to ship); it needs the Windows SetupAPI for the serial port lookup
find_library(MONOME_LIB NAMES libmonome.a monome REQUIRED)
find_path(MONOME_INC monome.h REQUIRED)

# the list of sources
file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/norns-sources.txt" _lines)
set(NORNS_SOURCES "")
foreach(_l IN LISTS _lines)
  string(STRIP "${_l}" _l)
  if(NOT _l STREQUAL "" AND NOT _l MATCHES "^#")
    list(APPEND NORNS_SOURCES "${REPO}/${_l}")
  endif()
endforeach()

# lua-cjson (the JSON module of the Lua side)
add_library(lua-cjson STATIC
  ${REPO}/third-party/lua-cjson/lua_cjson.c
  ${REPO}/third-party/lua-cjson/strbuf.c
  ${REPO}/third-party/lua-cjson/fpconv.c)
target_include_directories(lua-cjson PRIVATE ${REPO}/third-party/lua-cjson)
target_compile_definitions(lua-cjson PRIVATE NDEBUG)
target_link_libraries(lua-cjson PRIVATE PkgConfig::LUA53)
target_compile_options(lua-cjson PRIVATE -w)

add_executable(norns ${NORNS_SOURCES})
set_target_properties(norns PROPERTIES OUTPUT_NAME "norns")

# the version of the Windows build: 0.1.0 = milestone M1 (matron VERSION_*; the norns update number on the home screen comes from update/version.txt)
target_compile_definitions(norns PRIVATE
  # HAVE_ABLETON_LINK=1: the Lua side registers and calls the clock_link_* functions; in M1 they are the stand-ins of stubs_win.cc (no Link yet)
  NORNS_DESKTOP=1 NORNS_LINUX_DESKTOP=1 NORNS_WINDOWS=1
  HAVE_LIBMONOME=1 HAVE_NNG=1 HAVE_LUA_CJSON=1 HAVE_ABLETON_LINK=1
  VERSION_MAJOR=0 VERSION_MINOR=1 VERSION_PATCH=0 VERSION_HASH="${VERDANDI_VERSION_HASH}"
  _GNU_SOURCE=1)
# the force-included compatibility header: every translation unit sees it first
target_compile_options(norns PRIVATE "SHELL:-include ${REPO}/matron/src/platform/windows/compat_win.h")
# headers named like system headers (io.h, stat.h) are found only through #include "..." from their own folders, never as <...>
target_compile_options(norns PRIVATE
  "SHELL:-iquote ${REPO}/matron/src/hardware" "SHELL:-iquote ${REPO}/matron/src/device")
target_include_directories(norns PRIVATE
  ${REPO}/norns
  ${REPO}/matron/src
  ${REPO}/matron/src/platform/windows/include
  ${REPO}/matron/src/platform/windows/jack_null/include
  ${REPO}/matron/src/platform/macos/include
  ${REPO}/crone
  ${REPO}/crone/src
  ${REPO}/crone/faust
  ${REPO}/crone/softcut/softcut-lib/include
  ${REPO}/third-party/concurrentqueue
  ${REPO}/third-party/readerwriterqueue
  ${REPO}/third-party/lua-cjson
  ${MONOME_INC} ${NNG_INC})
# winsock macros (connect, close, ...) for the one file that talks to a socket
set_source_files_properties(${REPO}/matron/src/platform/macos/sdl_bridge.cc PROPERTIES
  COMPILE_OPTIONS "-include;${REPO}/matron/src/platform/windows/compat_win.h;-include;${REPO}/matron/src/platform/windows/compat_sock.h")
target_compile_options(norns PRIVATE -Wno-unused-parameter)
target_link_libraries(norns PRIVATE
  lua-cjson ${MONOME_LIB}
  PkgConfig::LUA53 PkgConfig::LIBLO PkgConfig::CAIRO PkgConfig::SNDFILE PkgConfig::FREETYPE2 PkgConfig::SDL2 ${NNG_LIB}
  ws2_32 mswsock advapi32 setupapi winmm ole32 shell32 dbghelp psapi pthread m)
target_link_options(norns PRIVATE -static-libgcc -static-libstdc++ -Wl,--stack,8388608)

install(TARGETS norns RUNTIME DESTINATION .)
